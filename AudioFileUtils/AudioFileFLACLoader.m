/*
 AudioFileFLACLoader.m

 This file is part of Audirvana.

 Audirvana is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Audirvana is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Audirvana.  If not, see <http://www.gnu.org/licenses/>.

 Original code written by Damien Plisson 08/2010
 */

#import <AudioToolbox/AudioToolbox.h>
#import "AudioFileFLACLoader.h"

#include <FLAC/metadata.h>
#include <dispatch/dispatch.h>
#include </usr/include/mach/vm_map.h>

#import "AppController.h"
#import "PreferenceController.h"

#define LIBSRC_OUTPUTBUF_SECONDS 5

@interface AudioFileFLACLoader (PrivateMethods)
- (void)setMetadata:(const FLAC__StreamMetadata *)metadata;
- (FLAC__StreamDecoderWriteStatus)fillAudioBuffer:(const FLAC__Frame *)frame
									   FLACbuffer:(const FLAC__int32 * const[])buffer;
- (long)readSRCdata:(float**)data;
- (UInt32)readSRCdata:(SInt32 **)data forFrames:(UInt32)nbFramesToRead; //For CoreAudio SRC
@end

#pragma mark FLAC decoder callbacks

static FLAC__StreamDecoderWriteStatus writeCallback(const FLAC__StreamDecoder *decoder,
													const FLAC__Frame *frame,
													const FLAC__int32 * const buffer[],
													void *client_data)
{
	AudioFileFLACLoader *flacLoader = (AudioFileFLACLoader*) client_data;

	return [flacLoader fillAudioBuffer:frame FLACbuffer:buffer];
}


static void metadataCallback(const FLAC__StreamDecoder *decoder,
							 const FLAC__StreamMetadata *metadata,
							 void *client_data)
{
	AudioFileFLACLoader *flacLoader = (AudioFileFLACLoader*) client_data;

	[flacLoader setMetadata:metadata];
}

static void errorCallback(const FLAC__StreamDecoder *decoder,
						  FLAC__StreamDecoderErrorStatus status,
						  void *client_data)
{
}

static long sampleRateCallBack(void *cb_data, float **data)
{
	AudioFileFLACLoader *flacLoader = (AudioFileFLACLoader*) cb_data;
	return [flacLoader readSRCdata:data];
}

static OSStatus CoreAudioEncoderDataProc(AudioConverterRef inAudioConverter,
						 UInt32* ioNumberDataPackets,
						 AudioBufferList* ioData,
						 AudioStreamPacketDescription** outDataPacketDescription,
						 void* inUserData)
{
	AudioFileFLACLoader *flacLoader = (AudioFileFLACLoader*) inUserData;

	*ioNumberDataPackets = (UInt32)[flacLoader readSRCdata:(SInt32**)&ioData->mBuffers[0].mData forFrames:*ioNumberDataPackets];
	ioData->mBuffers[0].mDataByteSize = (UInt32)(*ioNumberDataPackets*2*sizeof(SInt32));
	ioData->mBuffers[0].mNumberChannels = 2;

	return noErr;
}


#pragma mark AudioFileFLACLoader implementation

@implementation AudioFileFLACLoader

@synthesize mFLACmaxBlockSize;

+ (NSArray*)supportedFileExtensions
{
	return [NSArray arrayWithObjects:@"flac",@"oga",nil];
}


+ (bool)isFormatSupported:(NSURL*)fileURL
{
	NSString *fileExtension;

	fileExtension = [[fileURL pathExtension] lowercaseString];

	if ([fileExtension isEqualToString:@"flac"] || [fileExtension isEqualToString:@"oga"])
			return true;

	return false;
}


- (FLAC__StreamDecoderWriteStatus)fillAudioBuffer:(const FLAC__Frame *)frame
									   FLACbuffer:(const FLAC__int32 * const[])buffer
{
	unsigned int sample;
	float bitDepthFactor = (float)(1L << ((((frame->header.bits_per_sample + 7) / 8) * 8) - 1));

	if (!mFLACbufferData) return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;

	if (!mIsUsingSRC) {
        unsigned int samplesToConvert = frame->header.blocksize;

        if ((samplesToConvert*mOutputStreamFormat.mBytesPerFrame) > (mFLACbufferSizeInBytes - mFLACreadFrames*mOutputStreamFormat.mBytesPerFrame))
            samplesToConvert = (unsigned int)((mFLACbufferSizeInBytes - mFLACreadFrames*mOutputStreamFormat.mBytesPerFrame)/mOutputStreamFormat.mBytesPerFrame);


		if (mIsIntegerModeOn) {
			if (tmpInt32buf) {
				OSErr err;
				UInt32 readData;
                for (sample=0;sample<samplesToConvert;sample++) {
					tmpInt32buf[sample*2] = buffer[0][sample] << (32 - frame->header.bits_per_sample);
					tmpInt32buf[sample*2+1] = mFLACchannels>1 ? buffer[1][sample] << (32 - frame->header.bits_per_sample) : 0;
				}

				readData = (UInt32)(frame->header.blocksize*mOutputStreamFormat.mBytesPerFrame);
				err = AudioConverterConvertBuffer(mCoreAudioConverterRef,
											(UInt32)(frame->header.blocksize*sizeof(SInt32)*2), tmpInt32buf,
											&readData,
											((UInt8*)mFLACbufferData) + (mFLACreadFrames*mOutputStreamFormat.mBytesPerFrame));

				if ((err == noErr) && (mIntModeAlignedLowZeroBits > 0))
					[self alignAudioBufferFromHighToLow:(UInt32*)(((UInt8*)mFLACbufferData) + (mFLACreadFrames*mOutputStreamFormat.mBytesPerFrame))
										framesToConvert:(readData / mOutputStreamFormat.mBytesPerFrame)];

				mFLACreadFrames += readData / mOutputStreamFormat.mBytesPerFrame;
			}
		} else {
			for (sample=0;sample<samplesToConvert;sample++) {
				mFLACbufferData[mFLACreadFrames*2] = buffer[0][sample] / bitDepthFactor;
				mFLACbufferData[mFLACreadFrames*2+1] = mFLACchannels>1 ? buffer[1][sample] / bitDepthFactor : (float)0.0;
				mFLACreadFrames++;
			}
		}
	} else {
		//Fill SRC conversion
		if (tmpInt32buf)
			for (sample=0;sample<frame->header.blocksize;sample++) {
				tmpInt32buf[mFLACreadFrames*2] = buffer[0][sample] << (32 - frame->header.bits_per_sample);
				tmpInt32buf[mFLACreadFrames*2+1] = mFLACchannels>1 ? buffer[1][sample] << (32 - frame->header.bits_per_sample) : 0;
				mFLACreadFrames++;
			}
		else if (tmpSRCbuf)
			for (sample=0;sample<frame->header.blocksize;sample++) {
				tmpSRCbuf[mFLACreadFrames*2] = buffer[0][sample] / bitDepthFactor;
				tmpSRCbuf[mFLACreadFrames*2+1] = mFLACchannels>1 ? buffer[1][sample] / bitDepthFactor : (float)0.0;
				mFLACreadFrames++;
			}
	}


	return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

- (long)readSRCdata:(float**)data
{
	mFLACreadFrames = 0;

	FLAC__stream_decoder_process_single(mFLACStreamDecoder);

	*data = tmpSRCbuf;

	return (long)mFLACreadFrames;
}

- (UInt32)readSRCdata:(SInt32 **)data forFrames:(UInt32)nbFramesToRead
{
	if (mFLACtmpInt32bufUnreadFrames > 0) {
		//Remaining frames in the tmpSrcBuffer : read them first
		*data = (tmpInt32buf + 2*(mFLACreadFrames - mFLACtmpInt32bufUnreadFrames));
	}
	else {
		//Need to fetch a new frame
		mFLACreadFrames = 0;
		FLAC__stream_decoder_process_single(mFLACStreamDecoder);
		*data = tmpInt32buf;
		mFLACtmpInt32bufUnreadFrames = mFLACreadFrames;
	}

	if (nbFramesToRead < mFLACtmpInt32bufUnreadFrames) {
		mFLACtmpInt32bufUnreadFrames -= nbFramesToRead;
		return nbFramesToRead;
	}
	else {
		UInt32 readFrames = (UInt32)mFLACtmpInt32bufUnreadFrames;
		mFLACtmpInt32bufUnreadFrames = 0;
		return readFrames;
	}
}

-(void)setMetadata:(const FLAC__StreamMetadata *)metadata
{
	char *FLACfieldName, *FLACfieldValue;
	NSImage *albumArt;
	unsigned int i;

	if (!mFileMetadata)
		mFileMetadata = [[NSMutableDictionary alloc] initWithCapacity:5];

	switch(metadata->type) {
		case FLAC__METADATA_TYPE_STREAMINFO:
			mNativeSampleRate = metadata->data.stream_info.sample_rate;
			mBitDepth = metadata->data.stream_info.bits_per_sample;
			mLengthFrames = metadata->data.stream_info.total_samples;
			mFLACchannels = metadata->data.stream_info.channels;
			mFLACmaxBlockSize = metadata->data.stream_info.max_blocksize;
			break;

		case FLAC__METADATA_TYPE_VORBIS_COMMENT:
			for(i = 0; i < metadata->data.vorbis_comment.num_comments; ++i) {

				if(FLAC__metadata_object_vorbiscomment_entry_to_name_value_pair(metadata->data.vorbis_comment.comments[i],
																				&FLACfieldName,
																				&FLACfieldValue) == NO) {
					continue;
				}

				if(strcasecmp(FLACfieldName,"TITLE")==0) {
					[mFileMetadata setObject:[NSString stringWithUTF8String:FLACfieldValue]
									  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Title]];
				} else if(strcasecmp(FLACfieldName,"ARTIST")==0){
					[mFileMetadata setObject:[NSString stringWithUTF8String:FLACfieldValue]
									  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Artist]];
				} else if(strcasecmp(FLACfieldName,"ALBUM")==0){
					[mFileMetadata setObject:[NSString stringWithUTF8String:FLACfieldValue]
									  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Album]];
				} else if(strcasecmp(FLACfieldName,"COMPOSER")==0){
					[mFileMetadata setObject:[NSString stringWithUTF8String:FLACfieldValue]
									  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Composer]];
				} else if(strcasecmp(FLACfieldName,"TRACKNUMBER")==0){
					[mFileMetadata setObject:[NSString stringWithUTF8String:FLACfieldValue]
									  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_TrackNumber]];
				}

				free(FLACfieldValue);
				free(FLACfieldName);
				FLACfieldValue = NULL;
				FLACfieldName = NULL;
			}
			break;

		case FLAC__METADATA_TYPE_PICTURE:
			if ((metadata->data.picture.type != FLAC__STREAM_METADATA_PICTURE_TYPE_FRONT_COVER)
				&& ([mFileMetadata objectForKey:[NSString stringWithUTF8String: kAFInfoDictionary_CoverImage]] != nil))
				break; //Keep only the front cover picture in case of several pictures

			albumArt = [[NSImage alloc] initWithData:[NSData dataWithBytes:metadata->data.picture.data length:metadata->data.picture.data_length]];
			if (albumArt) {
				[mFileMetadata setObject:albumArt
								  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_CoverImage]];
				[albumArt release];
			}
			break;

		default:
			break;
	}
}


#pragma mark loader public functions

- (id)initWithURL:(NSURL*)urlToOpen
{
	FLAC__StreamDecoderInitStatus FLACstatus;
	FLAC__bool FLACresult;
	const char *str = [[urlToOpen path] cStringUsingEncoding:NSUTF8StringEncoding];
	if (str == NULL) {
		[self release];
		return nil;
	}

	mFLACStreamDecoder = FLAC__stream_decoder_new();
	if (mFLACStreamDecoder == NULL) {
		[self release];
		return nil;
	}

	FLAC__stream_decoder_set_metadata_respond(mFLACStreamDecoder, FLAC__METADATA_TYPE_VORBIS_COMMENT);
	FLAC__stream_decoder_set_metadata_respond(mFLACStreamDecoder, FLAC__METADATA_TYPE_PICTURE);

	if ([[[urlToOpen pathExtension] lowercaseString] isEqualToString:@"oga"])
		FLACstatus = FLAC__stream_decoder_init_ogg_file(mFLACStreamDecoder, str,
														writeCallback, metadataCallback,
														errorCallback, self);
	else
		FLACstatus = FLAC__stream_decoder_init_file(mFLACStreamDecoder, str,
													writeCallback, metadataCallback,
													errorCallback, self);

	if (FLACstatus != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
		NSLog(@"Error opening the FLAC file for decoding: file=%s error = 0x%x",str,FLACstatus);
		FLAC__stream_decoder_delete(mFLACStreamDecoder);
		mFLACStreamDecoder = NULL;
		[self release];
		return nil;
	}

	FLACresult = FLAC__stream_decoder_process_until_end_of_metadata(mFLACStreamDecoder);
	if (FLACresult != YES) {
		NSLog(@"Error reading FLAC file metadata: file=%s error = 0x%x",str,FLACstatus);
		FLAC__stream_decoder_finish(mFLACStreamDecoder);
		FLAC__stream_decoder_delete(mFLACStreamDecoder);
		mFLACStreamDecoder = NULL;
		[self release];
		return nil;
	}

	mChannels = 2; //TODO: implement multi-channel

	mlibSrcState = NULL;
	mCoreAudioConverterRef = NULL;
	tmpSRCbuf = NULL;
	tmpInt32buf = NULL;
	tmplibSampleRateOutBuf = NULL;

	return [super initWithURL:urlToOpen];
}

-(void)close
{
	if (mFLACStreamDecoder) {
		FLAC__stream_decoder_finish(mFLACStreamDecoder);
		FLAC__stream_decoder_delete(mFLACStreamDecoder);
		mFLACStreamDecoder = NULL;
	}
	if (tmpSRCbuf) { free(tmpSRCbuf); tmpSRCbuf = NULL; }
	if (tmplibSampleRateOutBuf) { free(tmplibSampleRateOutBuf); tmplibSampleRateOutBuf = NULL; }
	if (tmpInt32buf) { free(tmpInt32buf); tmpInt32buf = NULL; }
	if (mlibSrcState) { src_delete(mlibSrcState); mlibSrcState = NULL; }
	if (mCoreAudioConverterRef) { AudioConverterDispose(mCoreAudioConverterRef); mCoreAudioConverterRef = NULL; }

	[super close];
}


- (int)loadInitialBuffer:(void**)outBufferData
		AllocatedBufSize:(UInt64*)outBufferDataSize
		   MaxBufferSize:(UInt64)maxBufSize
		  NumTotalFrames:(SInt64*)numTotalFrames
		   NumLoadedFrames:(SInt64*)numLoadedFrames
				  Status:(UInt32*)status
	   NextInputPosition:(SInt64*)nextInputPosition
			   ForBuffer:(int)bufIdx
{
	//Perform SRC initialization
	if (mIsUsingSRC) {
		switch (mSRCModel) {
			case kAUDSRCModelSRClibSampleRate:
			{
				int srcError;
				mlibSrcState = src_callback_new(&sampleRateCallBack, mSRCQuality, 2, &srcError, self);
				if (mlibSrcState == NULL) return srcError;
				tmpSRCbuf = malloc(mFLACmaxBlockSize* sizeof(Float32) * 2);

				if (mIsIntegerModeOn) {
					AudioStreamBasicDescription inStreamFormat;
					OSErr err;

					//LibSampleRate outputs 32bit float
					inStreamFormat.mFormatID = kAudioFormatLinearPCM;
					inStreamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
					inStreamFormat.mBitsPerChannel = 32;
					inStreamFormat.mSampleRate = mTargetSampleRate;
					inStreamFormat.mChannelsPerFrame = 2;
					inStreamFormat.mBytesPerPacket = inStreamFormat.mChannelsPerFrame * (inStreamFormat.mBitsPerChannel / 8);
					inStreamFormat.mFramesPerPacket = 1;
					inStreamFormat.mBytesPerFrame = inStreamFormat.mBytesPerPacket;

					err = AudioConverterNew(&inStreamFormat, &mOutputStreamFormat, &mCoreAudioConverterRef);
					if (err != noErr) return -1;

					tmplibSampleRateOutBuf = (Float32*)malloc((size_t)(LIBSRC_OUTPUTBUF_SECONDS * mTargetSampleRate * sizeof(Float32) * 2)); //Output of libSampleRate is Float32
				}
			}
				break;
			case kAUDSRCModelAppleCoreAudio:
			default:
			{
				AudioStreamBasicDescription inStreamFormat;
				OSErr err;
				UInt32 tmpInt;

				inStreamFormat.mFormatID = kAudioFormatLinearPCM;
				inStreamFormat.mBitsPerChannel = 32;
				inStreamFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
				inStreamFormat.mSampleRate = mNativeSampleRate;
				inStreamFormat.mChannelsPerFrame = 2; //TODO : implement optional multi-channel
				inStreamFormat.mBytesPerPacket = inStreamFormat.mChannelsPerFrame * (inStreamFormat.mBitsPerChannel / 8);
				inStreamFormat.mFramesPerPacket = 1;
				inStreamFormat.mBytesPerFrame = inStreamFormat.mBytesPerPacket;

				err = AudioConverterNew(&inStreamFormat, &mOutputStreamFormat, &mCoreAudioConverterRef);
				if (err != noErr) return -1;

				tmpInt = mSRCComplexity;
				AudioConverterSetProperty(mCoreAudioConverterRef, kAudioConverterSampleRateConverterComplexity, sizeof(tmpInt), &tmpInt);
				tmpInt = mSRCQuality;
				AudioConverterSetProperty(mCoreAudioConverterRef, kAudioConverterSampleRateConverterQuality, sizeof(tmpInt), &tmpInt);

				tmpInt32buf = malloc(mFLACmaxBlockSize * sizeof(SInt32) * 2); //Native FLAC library format
			}
				break;
		}
	}
	else if (mIsIntegerModeOn) {
		AudioStreamBasicDescription inStreamFormat;
		OSErr err;

		//FLAC outputs 32bit signed integer
		inStreamFormat.mFormatID = kAudioFormatLinearPCM;
		inStreamFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
		inStreamFormat.mBitsPerChannel = 32;
		inStreamFormat.mSampleRate = mTargetSampleRate;
		inStreamFormat.mChannelsPerFrame = 2;
		inStreamFormat.mBytesPerPacket = inStreamFormat.mChannelsPerFrame * (inStreamFormat.mBitsPerChannel / 8);
		inStreamFormat.mFramesPerPacket = 1;
		inStreamFormat.mBytesPerFrame = inStreamFormat.mBytesPerPacket;

		err = AudioConverterNew(&inStreamFormat, &mOutputStreamFormat, &mCoreAudioConverterRef);
		if (err != noErr) return -1;

		tmpInt32buf = malloc(mFLACmaxBlockSize * sizeof(SInt32) * 2); //Native FLAC library format
	}

	return [self loadChunk:0
			 OutBufferData:outBufferData
		  AllocatedBufSize:outBufferDataSize
			 MaxBufferSize:maxBufSize
			NumTotalFrames:numTotalFrames
		   NumLoadedFrames:numLoadedFrames
					Status:status
		 NextInputPosition:nextInputPosition
				 ForBuffer:bufIdx];
}

- (int)loadChunk:(UInt64)startInputPosition
   OutBufferData:(void**)outBufferData
AllocatedBufSize:(UInt64*)outBufferDataSize
   MaxBufferSize:(UInt64)maxBufSize
  NumTotalFrames:(SInt64*)numTotalFrames
 NumLoadedFrames:(SInt64*)numLoadedFrames
		  Status:(UInt32*)status
NextInputPosition:(SInt64*)nextInputPosition
	   ForBuffer:(int)bufIdx
{
	UInt64 sizeInBytes;
	__block bool loadWholeFile;

	//Get uncompressed file size
	sizeInBytes = mLengthFrames* mOutputStreamFormat.mBytesPerFrame * mTargetSampleRate / mNativeSampleRate; //TODO: allow multiple channels
    sizeInBytes -= startInputPosition * mOutputStreamFormat.mBytesPerFrame;

	if (sizeInBytes > maxBufSize) {
		loadWholeFile = FALSE;
		sizeInBytes = maxBufSize;
	}
	else
		loadWholeFile = TRUE;

	*numTotalFrames = sizeInBytes / mOutputStreamFormat.mBytesPerFrame;

	kern_return_t theKernelError = vm_allocate(mach_task_self(),
											   (vm_address_t*)outBufferData,
											   (vm_size_t)sizeInBytes,
											   VM_FLAGS_ANYWHERE);

	mFLACreadFrames = 0;
	mFLACtmpInt32bufUnreadFrames = 0;
	mFLACLoadedSeconds = 0;
	*numLoadedFrames = 0;

	if (theKernelError != KERN_SUCCESS) {
		*status = 0;
		*outBufferData = NULL;
		*outBufferDataSize = 0;
		return -1;
	}
	*outBufferDataSize = sizeInBytes;

	mFLACbufferData = *outBufferData;
    mFLACbufferSizeInBytes = sizeInBytes;

	//Check if need to seek the file read position
	if (startInputPosition != mNextFrameToLoadPosition) {
		FLAC__stream_decoder_seek_absolute(mFLACStreamDecoder, (FLAC__uint64)(startInputPosition*mNativeSampleRate/mTargetSampleRate));
        if (mIsUsingSRC && mSRCModel == kAUDSRCModelAppleCoreAudio)
            AudioConverterReset(mCoreAudioConverterRef);
	}

	*status = (loadWholeFile?kAudioFileLoaderStatusEOF:0) | kAudioFileLoaderStatusLoading;
	mIsMakingBackgroundTask |= kAudioFileLoaderLoadingBuffer;

	if (!mIsUsingSRC) {
		dispatch_group_async(mBackgroundLoadGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            BOOL reachedEOF = NO;

			while (((mIsMakingBackgroundTask & kAudioFileLoaderLoadingBuffer) != 0)
				   && (loadWholeFile || ((mFLACreadFrames * mOutputStreamFormat.mBytesPerFrame + mFLACmaxBlockSize) < sizeInBytes))) {

				if (!FLAC__stream_decoder_process_single(mFLACStreamDecoder)) {
                    reachedEOF = YES;
                    break;
                }

				if (FLAC__stream_decoder_get_state(mFLACStreamDecoder) >= FLAC__STREAM_DECODER_END_OF_STREAM) {
                    reachedEOF = YES;
                    break;
                }

				   //Report load progress every 10s loaded
				if ((mFLACreadFrames /mTargetSampleRate /10) > (mFLACLoadedSeconds/10)) {
					mFLACLoadedSeconds = (UInt32)(mFLACreadFrames /mTargetSampleRate);
					*numLoadedFrames = mFLACreadFrames;
					dispatch_async(dispatch_get_main_queue(), ^{[mAppController updateLoadStatus:startInputPosition
																							  to:mFLACreadFrames
																							upTo:*numTotalFrames
																					   forBuffer:bufIdx
																					   completed:NO
                                                                                           reset:NO];});
				}
			}

			*numLoadedFrames = mFLACreadFrames;

            if (reachedEOF) {
                loadWholeFile = YES;
                *status |= kAudioFileLoaderStatusEOF;
            }

            if (loadWholeFile && (*numLoadedFrames >=0)) {
                //Core audio file length initial value may just be an estimate >= actual length
                //Actual length is known after reading up to the file end.
                *numTotalFrames = *numLoadedFrames;
                dispatch_async(dispatch_get_main_queue(), ^{[mAppController updateCurrentTrackTotalLength:startInputPosition+*numTotalFrames
                                                                                                 duration:(startInputPosition+*numTotalFrames)/mTargetSampleRate
                                                                                                forBuffer:bufIdx];});
            }

			*status &= ~kAudioFileLoaderStatusLoading;
			*nextInputPosition = startInputPosition + *numLoadedFrames;
			mNextFrameToLoadPosition = *nextInputPosition;

			dispatch_async(dispatch_get_main_queue(), ^{[mAppController updateLoadStatus:startInputPosition
																					  to:mFLACreadFrames
																					upTo:*numTotalFrames
																			   forBuffer:bufIdx
																			   completed:YES
                                                                                   reset:NO];});
		});
	} else {
		//Use sample rate converter
		switch (mSRCModel) {
			case kAUDSRCModelSRClibSampleRate:
				dispatch_group_async(mBackgroundLoadGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					long readStep;
					long framesRead=0;
					OSStatus err = noErr;

					while (((mIsMakingBackgroundTask & kAudioFileLoaderLoadingBuffer) != 0)
						   && (loadWholeFile || (((UInt64)*numLoadedFrames * mOutputStreamFormat.mBytesPerFrame) < sizeInBytes))) {
						readStep = (long)(LIBSRC_OUTPUTBUF_SECONDS * mTargetSampleRate);
						if ((*numLoadedFrames + readStep) > *numTotalFrames)
							readStep = (long)(*numTotalFrames - *numLoadedFrames);
						if (mIsIntegerModeOn) {
							UInt32 bytesConverted;

							framesRead = src_callback_read(mlibSrcState, mTargetSampleRate / mNativeSampleRate,
														   readStep , tmplibSampleRateOutBuf);

							if (framesRead > 0) {
								bytesConverted = (UInt32)(framesRead*mOutputStreamFormat.mBytesPerFrame);
								err = AudioConverterConvertBuffer(mCoreAudioConverterRef, (UInt32)(framesRead * sizeof(Float32) * 2),
															tmplibSampleRateOutBuf, &bytesConverted,
															((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame));

								if ((err == noErr) && (mIntModeAlignedLowZeroBits > 0))
									[self alignAudioBufferFromHighToLow:(UInt32*)(((UInt8*)mFLACbufferData) + (mFLACreadFrames*mOutputStreamFormat.mBytesPerFrame))
														framesToConvert:(bytesConverted / mOutputStreamFormat.mBytesPerFrame)];

								framesRead = bytesConverted / mOutputStreamFormat.mBytesPerFrame;
							}
						}
						else framesRead = src_callback_read(mlibSrcState, mTargetSampleRate / mNativeSampleRate,
													   readStep , (float*)(((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame)));
						if (framesRead <=0) break;
						*numLoadedFrames += framesRead;
						dispatch_async(dispatch_get_main_queue(), ^{[mAppController updateLoadStatus:startInputPosition
																								  to:*numLoadedFrames
																								upTo:*numTotalFrames
																						   forBuffer:bufIdx
																						   completed:NO
                                                                                               reset:NO];});
					}

                    if (framesRead <= 0) {
                        loadWholeFile = YES;
                        *status |= kAudioFileLoaderStatusEOF;
                    }

                    if (loadWholeFile && (framesRead >=0)) {
                        //Core audio file length initial value may just be an estimate >= actual length
                        //Actual length is known after reading up to the file end.
                        *numTotalFrames = *numLoadedFrames;
                        dispatch_async(dispatch_get_main_queue(), ^{[mAppController updateCurrentTrackTotalLength:startInputPosition+*numTotalFrames
                                                                                                         duration:(startInputPosition+*numTotalFrames)/mTargetSampleRate
                                                                                                        forBuffer:bufIdx];});
                    }

					*status &= ~kAudioFileLoaderStatusLoading;
					*nextInputPosition = startInputPosition + *numLoadedFrames;
					mNextFrameToLoadPosition = *nextInputPosition;

					dispatch_async(dispatch_get_main_queue(), ^{[mAppController updateLoadStatus:startInputPosition
																							  to:*numLoadedFrames
																							upTo:*numTotalFrames
																					   forBuffer:bufIdx
																					   completed:YES
                                                                                           reset:NO];});
				});
				break;
			case kAUDSRCModelAppleCoreAudio:
			default:
			{
				dispatch_group_async(mBackgroundLoadGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					UInt32 readStep = 5 * (UInt32)mTargetSampleRate;
					AudioBufferList outData;
					OSStatus readErr = noErr;

					outData.mNumberBuffers = 1;
					outData.mBuffers[0].mNumberChannels = 2;
					outData.mBuffers[0].mData = *outBufferData;
					outData.mBuffers[0].mDataByteSize = (UInt32)sizeInBytes;

					while (((mIsMakingBackgroundTask & kAudioFileLoaderLoadingBuffer) != 0)
						   && (loadWholeFile || (((UInt64)*numLoadedFrames * mOutputStreamFormat.mBytesPerFrame) < sizeInBytes))) {
						readStep = 5 * (UInt32)mTargetSampleRate;
						if ((*numLoadedFrames + readStep) > *numTotalFrames)
							readStep = (UInt32)(*numTotalFrames - *numLoadedFrames);
						outData.mBuffers[0].mData = ((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame);
						outData.mBuffers[0].mDataByteSize = (UInt32)(sizeInBytes - (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame));
						readErr = AudioConverterFillComplexBuffer(mCoreAudioConverterRef, CoreAudioEncoderDataProc, self, &readStep, &outData, NULL);

						if ((readErr == noErr) && (mIntModeAlignedLowZeroBits > 0))
							[self alignAudioBufferFromHighToLow:(UInt32*)(((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame))
												framesToConvert:readStep];

						if ((readErr != noErr) || (readStep ==0)) break;

						*numLoadedFrames += readStep;
						dispatch_async(dispatch_get_main_queue(), ^{[mAppController updateLoadStatus:startInputPosition
																								  to:*numLoadedFrames
																								upTo:*numTotalFrames
																						   forBuffer:bufIdx
																						   completed:NO
                                                                                               reset:NO];});
					}

                    if (readStep == 0) {
                        loadWholeFile = YES;
                        *status |= kAudioFileLoaderStatusEOF;
                    }

					if (loadWholeFile && (readErr == noErr)) {
						//Core audio file length initial value may just be an estimate >= actual length
						//Actual length is known after reading up to the file end.
						*numTotalFrames = *numLoadedFrames;
                        dispatch_async(dispatch_get_main_queue(), ^{[mAppController updateCurrentTrackTotalLength:startInputPosition+*numTotalFrames
                                                                                                         duration:(startInputPosition+*numTotalFrames)/mTargetSampleRate
                                                                                                        forBuffer:bufIdx];});
					}

					*status &= ~kAudioFileLoaderStatusLoading;
					*nextInputPosition = startInputPosition + *numLoadedFrames;
					mNextFrameToLoadPosition = *nextInputPosition;

					dispatch_async(dispatch_get_main_queue(), ^{[mAppController updateLoadStatus:startInputPosition
																							  to:*numLoadedFrames
																							upTo:*numTotalFrames
																					   forBuffer:bufIdx
																					   completed:YES
                                                                                           reset:NO];});
				});
			}
				break;
		}
	}


	return 0;
}


@end