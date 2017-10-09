//
//  SpeexEncoder.h
//  SpeexEncodingDemo
//
//  Created by Mikhail Dudarev (mikejd@mikejd.ru) on 09.05.13.
//  Copyright (c) 2013 Mihteh Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Speex/Speex.h>

// This value is picked quite arbitrarily here.
#define MAX_FRAMES_PER_OGG_PAGE 79

typedef int SpeexQuality;
typedef void SpeexEncState;
typedef char * SpeexCompressedBits;

typedef enum {
    SAMPLE_RATE_8000_HZ = 8000,
    SAMPLE_RATE_16000_HZ = 16000,
    SAMPLE_RATE_32000_HZ = 32000,
    SAMPLE_RATE_44100_HZ = 44100,
} SampleRate;

typedef enum {
    NUMBER_OF_CHANNELS_MONO = 1,
    //NUMBER_OF_CHANNELS_STEREO = 2, unsupported now
} NumberOfChannels;

typedef struct {
    char vendorStringLength[4];
    char vendorString[32];
    char numberOfCommentFields[4];
} oggVorbisCommentStruct;

typedef enum {
    ERROR_CODE_WAVE_PARSER_INCORRECT_FILESIZE,
    ERROR_CODE_WAVE_PARSER_CONTAINER_ID_NOT_FOUND,
    ERROR_CODE_WAVE_PARSER_FORMAT_ID_NOT_FOUND,
    ERROR_CODE_WAVE_PARSER_DATA_CHUNK_ID_NOT_FOUND,
    ERROR_CODE_WAVE_PARSER_AUDIO_PROPERTIES_NOT_EXTRACTED,
    ERROR_CODE_SPEEX_ENCODER_COULD_ALLOCATE_ENCODER_STATE,
    ERROR_CODE_SPEEX_ENCODER_COULD_NOT_SETUP_RESAMPLER,
    ERROR_CODE_SPEEX_ENCODER_COULD_NOT_OBTAIN_FRAME_SIZE,
    ERROR_CODE_SPEEX_ENCODER_COULD_NOT_OBTAIN_BITRATE,
    ERROR_CODE_SPEEX_ENCODER_COULD_NOT_SET_QUALITY,
    ERROR_CODE_SPEEX_ENCODER_NOT_ENOUGH_DATA_TO_CREATE_SPEEX_HEADER,
} ErrorCode;

@interface SpeexEncoder : NSObject

@property (nonatomic, readonly) SpeexQuality encodingQuality;
@property (nonatomic, readonly) SpeexMode encodingMode;
@property (nonatomic, readonly) SampleRate outSampleRate;

/***
 * @Description: Creates an object responsible for encoding different audio types into speex.
 * @Return: Returns the encoder.
 */
+(SpeexEncoder *)encoderWithMode:(SpeexMode)mode quality:(SpeexQuality)quality outputSampleRate:(SampleRate)outSampleRate;

/***
 * @Description: Encodes wave pcm file at specified path into speex.
 * @Return: Returns encoded data or nil if error occured (for details see error.description).
 */
-(NSData *)encodeAudio:(short *)samples nrSamples:(int)nrSamples sr:(SampleRate)sampleRate error:(NSError **)error;
-(NSData *)startEncoding:(SampleRate)sampleRate error:(NSError **)error;

@end
