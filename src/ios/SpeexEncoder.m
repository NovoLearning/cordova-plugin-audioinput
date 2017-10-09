#import "SpeexEncoder.h"
#import <Speex/speex_header.h>
#import <Speex/speex_resampler.h>
#import <Ogg/Ogg.h>

@interface SpeexEncoder ()

-(SpeexEncoder *)_initWithMode:(SpeexMode)mode quality:(SpeexQuality)quality outputSampleRate:(int)outSampleRate;
-(void)_spxCleanup;
-(void)_oggCleanup;
-(void)_spxSetup;
-(void)_oggSetup;

-(SpeexHeader)_makeSpeexHeader;
-(oggVorbisCommentStruct *)_makeOggVorbisComment;

-(void)_appendOggPageWithSpeexHeader:(SpeexHeader)speexHeader toMutableData:(NSMutableData *)mutableData;
-(void)_appendOggPageWithVorbisComment:(oggVorbisCommentStruct *)oggVorbisComment toMutableData:(NSMutableData *)mutableData;
-(void)_appendOggPageWithCompressedBits:(SpeexCompressedBits)compressedBits toMutableData:(NSMutableData *)mutableData;
-(void)_appendCurrentOggPageToMutableData:(NSMutableData *)mutableData;
-(int)numberOfCompleteFramesForFrameSize:(int)frameSize nrSamples:(int)nrSamples;
-(int)numberOfRemainingSamplesForFrameSize:(int)frameSize nrSamples:(int)nrSamples;

@end

#pragma mark

@implementation SpeexEncoder {
    int  _numberOfChannels;
    NSError *_encodingError;
    
    SpeexBits  _spxBits;
    char _spxCompressedBits[200];
    SpeexEncState *_spxEncoderState;
    SpeexResamplerState *_spxResamplerState;
    int _spxSamplesPerFrame;
    int  _spxBytesPerFrame;
    int  _spxBitrate;
    int _spxNrFrames;
    NSMutableData *lastFrameData;
    
    ogg_stream_state  _oggStreamState;
    int _oggVorbisCommentLength;
    ogg_packet  _oggPacket;
    ogg_page  _oggPage;
}

+(SpeexEncoder *)encoderWithMode:(SpeexMode)mode quality:(SpeexQuality)quality outputSampleRate:(SampleRate)outSampleRate {
    return [[SpeexEncoder alloc] _initWithMode:mode quality:quality outputSampleRate:outSampleRate];
}

-(NSData *)startEncoding:(SampleRate)sampleRate error:(NSError **)error {
    
    _spxNrFrames = 0;
    _encodingError = *error;
    NSMutableData *resultData = [NSMutableData dataWithCapacity:(100 * 1024)];
    
    [self _spxSetup:sampleRate];
    if (*error) { return nil; }
    
    [self _oggSetup];
    if (*error) { return nil; }
    
    SpeexHeader spxHeader = [self _makeSpeexHeader];
    [self _appendOggPageWithSpeexHeader:spxHeader toMutableData:resultData];
    
    oggVorbisCommentStruct *oggVorbisComment = [self _makeOggVorbisComment];
    [self _appendOggPageWithVorbisComment:oggVorbisComment toMutableData:resultData];
    
    return [NSData dataWithData:resultData];
}

-(NSData *)encodeAudio:(short *)samples nrSamples:(int)nrSamples sr:(SampleRate)sampleRate error:(NSError **)error {
    
    int bytesPerSample = 2;
    NSMutableData *audioData = [[NSMutableData alloc] init];
    
    if ([lastFrameData length] > 0) {
        [audioData appendData:lastFrameData];
        lastFrameData = nil;
    }
    [audioData appendBytes:samples length:nrSamples*bytesPerSample];
    nrSamples = [audioData length] / bytesPerSample;
    _encodingError = *error;
    NSMutableData *resultData = [NSMutableData dataWithCapacity:(100 * 1024)];
    
    int numberOfCompleteFrames = [self numberOfCompleteFramesForFrameSize:_spxSamplesPerFrame nrSamples:nrSamples];
    int numberOfRemainingSamples = [self numberOfRemainingSamplesForFrameSize:_spxSamplesPerFrame nrSamples:nrSamples];
    
    for (int currentFrameIdx = 0; currentFrameIdx < numberOfCompleteFrames; currentFrameIdx++) {
        
        NSRange nextFrameRange = NSMakeRange(currentFrameIdx * bytesPerSample * _spxSamplesPerFrame, bytesPerSample * _spxSamplesPerFrame);
        NSData *nextFrameData = [audioData subdataWithRange:nextFrameRange];
        speex_bits_reset(&_spxBits);
        speex_encode_int(_spxEncoderState, (short *)nextFrameData.bytes, &_spxBits);
        
        int nextFrameCompressedBytesNumber = speex_bits_write(&_spxBits, _spxCompressedBits, _spxSamplesPerFrame);
        _oggPacket.packet = (unsigned char *)&_spxCompressedBits;
        _oggPacket.bytes = nextFrameCompressedBytesNumber;
        _oggPacket.granulepos = (_spxNrFrames + currentFrameIdx + 1) * _spxSamplesPerFrame;
        _oggPacket.packetno = _oggStreamState.packetno;
        ogg_stream_packetin(&_oggStreamState, &_oggPacket);
    }
    
    // Add remaining audio
    NSRange lastFrameRange = NSMakeRange([audioData length] - (numberOfRemainingSamples * bytesPerSample), bytesPerSample * numberOfRemainingSamples);
    lastFrameData = [NSMutableData dataWithData:[audioData subdataWithRange:lastFrameRange]];
    _spxNrFrames += numberOfCompleteFrames;
    
    // Write ogg page
    [self _appendCurrentOggPageToMutableData:resultData];
    
    // Return result
    return [NSData dataWithData:resultData];
}

-(int)numberOfCompleteFramesForFrameSize:(int)frameSize nrSamples:(int)nrSamples {
    return ( nrSamples / frameSize );
}

-(int)numberOfRemainingSamplesForFrameSize:(int)frameSize nrSamples:(int)nrSamples {
    return ( nrSamples - [self numberOfCompleteFramesForFrameSize:frameSize nrSamples:nrSamples] * frameSize );
}

-(SpeexEncoder *)_initWithMode:(SpeexMode)mode quality:(SpeexQuality)quality outputSampleRate:(int)outSampleRate {
    
    self = [super init];
    
    if (self) {
        _encodingMode = mode;
        _encodingQuality = quality;
        _outSampleRate = outSampleRate;
        _numberOfChannels = NUMBER_OF_CHANNELS_MONO;
    }
    
    return self;
}

-(void)_spxCleanup {
    if (_spxBits.nbBits > 0) {
        speex_bits_destroy(&_spxBits);
    }
    if (_spxEncoderState) {
        speex_encoder_destroy(_spxEncoderState);
    }
}

-(void)_oggCleanup {
    ogg_stream_clear(&_oggStreamState);
}

-(void)_spxSetup:(SampleRate)sr {
    
    [self _spxCleanup];
    
    speex_bits_init(&_spxBits);
    _spxEncoderState = speex_encoder_init(&_encodingMode);
    if (_spxEncoderState == NULL) {
        _encodingError = [self errorWithCode:ERROR_CODE_SPEEX_ENCODER_COULD_ALLOCATE_ENCODER_STATE];
        return;
    }
    
    int spxResamplerStateErr;
    _spxResamplerState = speex_resampler_init(NUMBER_OF_CHANNELS_MONO, sr, self.outSampleRate, SPEEX_RESAMPLER_QUALITY_MIN, &spxResamplerStateErr);
    if (spxResamplerStateErr != 0) {
        _encodingError = [self errorWithCode:ERROR_CODE_SPEEX_ENCODER_COULD_NOT_SETUP_RESAMPLER];
        return;
    }
    
    int getFrameSizeErr = speex_encoder_ctl(_spxEncoderState, SPEEX_GET_FRAME_SIZE, &_spxSamplesPerFrame);
    if (getFrameSizeErr != 0) {
        
        _encodingError = [self errorWithCode:ERROR_CODE_SPEEX_ENCODER_COULD_NOT_OBTAIN_FRAME_SIZE];
        return;
    }
    
    int getBitrateErr = speex_encoder_ctl(_spxEncoderState, SPEEX_GET_BITRATE, &_spxBitrate);
    if (getBitrateErr != 0) {
        _encodingError = [self errorWithCode:ERROR_CODE_SPEEX_ENCODER_COULD_NOT_OBTAIN_BITRATE];
        return;
    }
    
    int setQualityErr = speex_encoder_ctl(_spxEncoderState, SPEEX_SET_QUALITY, &_encodingQuality);
    if (setQualityErr != 0) {
        _encodingError = [self errorWithCode:ERROR_CODE_SPEEX_ENCODER_COULD_NOT_SET_QUALITY];
        return;
    }
}

-(NSError *)errorWithCode:(ErrorCode)errorCode {
    return [NSError errorWithDomain:@"com.novolanguage.speex" code:errorCode userInfo:nil];
}

-(void)_oggSetup {
    
    [self _oggCleanup];
    ogg_stream_init(&_oggStreamState, 1);
}

-(SpeexHeader)_makeSpeexHeader {
    
    SpeexHeader spxHeader;
    
    if (_spxBitrate == 0 || _spxSamplesPerFrame == 0) {
        _encodingError = [self errorWithCode:ERROR_CODE_SPEEX_ENCODER_NOT_ENOUGH_DATA_TO_CREATE_SPEEX_HEADER];
        return spxHeader;
    }
    
    speex_init_header(&spxHeader, self.outSampleRate, NUMBER_OF_CHANNELS_MONO, &_encodingMode);
    
    spxHeader.bitrate = _spxBitrate;
    spxHeader.frame_size = _spxSamplesPerFrame;
    spxHeader.frames_per_packet = 1;
    
    return spxHeader;
}

-(oggVorbisCommentStruct *)_makeOggVorbisComment {
    
    NSString *vendorString = @"****SpeexCommentVendorString****";
    int vendorStringLength = vendorString.length;
    oggVorbisCommentStruct *oggVorbisComment = calloc(sizeof(oggVorbisCommentStruct), sizeof(char));
    NSData *vendorStringLengthData = [NSData dataWithBytes:&vendorStringLength length:4];
    
    for (int i = 0; i < vendorStringLengthData.length; i++) {
        oggVorbisComment->vendorStringLength[i] = *(char *)[[vendorStringLengthData subdataWithRange:NSMakeRange(i, 1)] bytes];
    }
    for (int i = 0; i < vendorStringLength; i++) {
        oggVorbisComment->vendorString[i] = *(const char *)[vendorString substringWithRange:NSMakeRange(i, 1)].UTF8String;
    }
    for (int i = 0; i < 4; i++) {
        oggVorbisComment->numberOfCommentFields[i] = 0x00;
    }
    
    _oggVorbisCommentLength = 4 + vendorStringLength + 4;
    
    return oggVorbisComment;
}

-(void)_appendOggPageWithSpeexHeader:(SpeexHeader)speexHeader toMutableData:(NSMutableData *)mutableData {
    int oggPacketSize;
    _oggPacket.packet = (unsigned char *)speex_header_to_packet(&speexHeader, &oggPacketSize);
    _oggPacket.bytes = oggPacketSize;
    _oggPacket.b_o_s = 1;
    _oggPacket.packetno = _oggStreamState.packetno;
    ogg_stream_packetin(&_oggStreamState, &_oggPacket);
    free(_oggPacket.packet);
    [self _appendCurrentOggPageToMutableData:mutableData];
}

-(void)_appendOggPageWithVorbisComment:(oggVorbisCommentStruct *)oggVorbisComment toMutableData:(NSMutableData *)mutableData {
    _oggPacket.packet = (unsigned char *)oggVorbisComment;
    _oggPacket.bytes = _oggVorbisCommentLength;
    _oggPacket.packetno = _oggStreamState.packetno;
    ogg_stream_packetin(&_oggStreamState, &_oggPacket);
    free(_oggPacket.packet);
    [self _appendCurrentOggPageToMutableData:mutableData];
}

-(void)_appendOggPageWithCompressedBits:(SpeexCompressedBits)compressedBits toMutableData:(NSMutableData *)mutableData {
    
}

-(void)_appendCurrentOggPageToMutableData:(NSMutableData *)mutableData {
    
    if (ogg_stream_pageout(&_oggStreamState, &_oggPage) == 0) {
        ogg_stream_flush(&_oggStreamState, &_oggPage);
    }
    
    [mutableData appendBytes:&_oggStreamState.header length:_oggStreamState.header_fill];
    [mutableData appendBytes:_oggStreamState.body_data length:_oggStreamState.body_fill];
}

@end

