/*
 AudioFileSndFileLoader.mm

 This file is part of AudioNirvana.

 AudioNirvana is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 AudioNirvana is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Audirvana.  If not, see <http://www.gnu.org/licenses/>.

 Original code written by Damien Plisson 09/2010 */


#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioFile.h>
#include <taglib/aifffile.h>
#include <taglib/wavfile.h>
#include <taglib/id3v2tag.h>
#include <taglib/attachedpictureframe.h>

#include <dispatch/dispatch.h>
#include </usr/include/mach/vm_map.h>

#import "AppController.h"
#import "AudioFileSndFileLoader.h"
#import "PreferenceController.h"


#define TMP_SRC_BUFFER_SIZE 4096
#define LIBSRC_OUTPUTBUF_SECONDS 5

@interface AudioFileSndFileLoader (metadata)
- (bool)getAiffMetadata:(NSURL*)fileURL;
- (bool)getWavMetadata:(NSURL*)fileURL;
- (long)readSRCdata:(float**)data;
- (UInt32)readSRCdata:(Float64 **)data forFrames:(UInt32)nbFramesToRead; //For CoreAudio SRC
@end


#pragma mark SRC callbacks

static long sampleRateCallBack(void *cb_data, float **data)
{
	AudioFileSndFileLoader *sndFileLoader = (AudioFileSndFileLoader*) cb_data;
	return [sndFileLoader readSRCdata:data];
}

static OSStatus CoreAudioEncoderDataProc(AudioConverterRef inAudioConverter,
										 UInt32* ioNumberDataPackets,
										 AudioBufferList* ioData,
										 AudioStreamPacketDescription** outDataPacketDescription,
										 void* inUserData)
{
	AudioFileSndFileLoader *sndFileLoader = (AudioFileSndFileLoader*) inUserData;

	*ioNumberDataPackets = (UInt32)[sndFileLoader readSRCdata:(Float64**)&ioData->mBuffers[0].mData forFrames:*ioNumberDataPackets];
	ioData->mBuffers[0].mDataByteSize = (UInt32)(*ioNumberDataPackets*2*sizeof(Float64));
	ioData->mBuffers[0].mNumberChannels = 2;

	return noErr;
}


@implementation AudioFileSndFileLoader

+ (NSArray*)supportedFileExtensions
{
	SF_FORMAT_INFO format_info;
	int i,nbFileTypes;
	NSMutableArray *fileExts = [[NSMutableArray alloc] init];

	sf_command (NULL, SFC_GET_FORMAT_MAJOR_COUNT, &nbFileTypes, sizeof (int)) ;

	for (i=0;i<nbFileTypes;i++)
	{   format_info.format=i;
		sf_command (NULL, SFC_GET_FORMAT_MAJOR, &format_info, sizeof (format_info));
		[fileExts addObject:[NSString stringWithCString:format_info.extension encoding:NSUTF8StringEncoding]];
	}
	return [fileExts autorelease];
}

+ (bool)isFormatSupported:(NSURL*)fileURL
{
	SF_FORMAT_INFO format_info;
	int i,nbFileTypes;
	NSString *fileExtension;

	fileExtension = [[fileURL pathExtension] lowercaseString];

	sf_command (NULL, SFC_GET_FORMAT_MAJOR_COUNT, &nbFileTypes, sizeof (int)) ;

	for (i=0;i<nbFileTypes;i++)
	{   format_info.format=i;
		sf_command (NULL, SFC_GET_FORMAT_MAJOR, &format_info, sizeof (format_info));
		if ([fileExtension isEqualToString:[NSString stringWithCString:format_info.extension encoding:NSUTF8StringEncoding]])
			return true;
	}

	return false;
}

- (id)initWithURL:(NSURL*)urlToOpen
{
	NSString *fileExtension;
    NSString *strValue;
	const char *str = [[urlToOpen path] cStringUsingEncoding:NSUTF8StringEncoding];

	fileExtension = [[urlToOpen pathExtension] lowercaseString];

	mSndFileRef = NULL;

	mSF_Info.format = 0; //As requested by libSndFile

	if (str) mSndFileRef = sf_open(str, SFM_READ, &mSF_Info);

	if (mSndFileRef == NULL) {
		[self release];
		return nil;
	}

	mNativeSampleRate = mSF_Info.samplerate;
	mLengthFrames = mSF_Info.frames;
	mChannels = 2;

	switch (mSF_Info.format & SF_FORMAT_SUBMASK) {
		case SF_FORMAT_PCM_S8:
		case SF_FORMAT_PCM_U8:
		case SF_FORMAT_DPCM_8:
			mBitDepth = 8;
			break;

		case SF_FORMAT_PCM_16:
			mBitDepth = 16;
			break;

		case SF_FORMAT_PCM_24:
		case SF_FORMAT_DWVW_24:
			mBitDepth = 24;
			break;

		case SF_FORMAT_PCM_32:
		case SF_FORMAT_FLOAT:
			mBitDepth = 32;
			break;

		case SF_FORMAT_DOUBLE:
			mBitDepth = 64;
			break;

		default:
			mBitDepth = 16;
			break;
	}


	//Get metadata

	mFileMetadata = [[NSMutableDictionary alloc] initWithCapacity:3];

	str = sf_get_string(mSndFileRef, SF_STR_TITLE);
	if (str) {
        strValue = [NSString stringWithCString:str encoding:NSUTF8StringEncoding];
        if (!strValue)
            strValue = [NSString stringWithCString:str encoding:NSMacOSRomanStringEncoding];

        if (strValue)
            [mFileMetadata setObject:strValue
                              forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Title]];
    }

	str = sf_get_string(mSndFileRef, SF_STR_ARTIST);
	if (str) {
        strValue = [NSString stringWithCString:str encoding:NSUTF8StringEncoding];
        if (!strValue)
            strValue = [NSString stringWithCString:str encoding:NSMacOSRomanStringEncoding];

        if (strValue)
            [mFileMetadata setObject:strValue
                              forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Artist]];
    }

	str = sf_get_string(mSndFileRef, SF_STR_ALBUM);
	if (str) {
        strValue = [NSString stringWithCString:str encoding:NSUTF8StringEncoding];
        if (!strValue)
            strValue = [NSString stringWithCString:str encoding:NSMacOSRomanStringEncoding];

        if (strValue)
            [mFileMetadata setObject:strValue
                              forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Album]];
    }

	//Get additional metadata from the ID3v2 tags
	if (([fileExtension caseInsensitiveCompare:@"aif"] == NSOrderedSame)
		|| ([fileExtension caseInsensitiveCompare:@"aiff"] == NSOrderedSame))
		[self getAiffMetadata:urlToOpen];
	else if ([fileExtension caseInsensitiveCompare:@"wav"] == NSOrderedSame)
		[self getWavMetadata:urlToOpen];

	mLibSrcState = NULL;
	mCoreAudioConverterRef = NULL;
	mTmpSRCdata = NULL;
	mTmplibSampleRateOutBuf = NULL;
	mTmpSndFileSourceData = NULL;

	return [super initWithURL:urlToOpen];
}

-(void)close
{
	sf_close(mSndFileRef);
	if (mLibSrcState) { src_delete(mLibSrcState); mLibSrcState = NULL; }
	if (mTmpSRCdata) { free(mTmpSRCdata); mTmpSRCdata = NULL; }
	if (mTmplibSampleRateOutBuf) { free(mTmplibSampleRateOutBuf); mTmplibSampleRateOutBuf = NULL; }
	if (mTmpSndFileSourceData) { free(mTmpSndFileSourceData); mTmpSndFileSourceData = NULL; }
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
				mLibSrcState = src_callback_new(&sampleRateCallBack, mSRCQuality, 2, &srcError, self);
				if (mLibSrcState == NULL) return srcError;
				mTmpSRCdata = (Float32*)malloc(TMP_SRC_BUFFER_SIZE*sizeof(Float32)*2);

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

					mTmplibSampleRateOutBuf = (Float32*)malloc((size_t)(LIBSRC_OUTPUTBUF_SECONDS * mTargetSampleRate * sizeof(Float32) * 2)); //Output of libSampleRate is Float32
				}
			}
				break;
			case kAUDSRCModelAppleCoreAudio:
			default:
			{
				AudioStreamBasicDescription inStreamFormat;
				OSErr err;
				UInt32 tmpInt;

				//libSndFile outputs 64bit float at max precision
				inStreamFormat.mFormatID = kAudioFormatLinearPCM;
				inStreamFormat.mBitsPerChannel = 64;
				inStreamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
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

				mTmpSndFileSourceData = (Float64*)malloc(TMP_SRC_BUFFER_SIZE*sizeof(Float64)*2);
			}
				break;
		}
	}
	else if (mIsIntegerModeOn) {
		AudioStreamBasicDescription inStreamFormat;
		OSErr err;

		//libSndFile can output 64bit float
		inStreamFormat.mFormatID = kAudioFormatLinearPCM;
		inStreamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
		inStreamFormat.mBitsPerChannel = 64;
		inStreamFormat.mSampleRate = mTargetSampleRate;
		inStreamFormat.mChannelsPerFrame = 2;
		inStreamFormat.mBytesPerPacket = inStreamFormat.mChannelsPerFrame * (inStreamFormat.mBitsPerChannel / 8);
		inStreamFormat.mFramesPerPacket = 1;
		inStreamFormat.mBytesPerFrame = inStreamFormat.mBytesPerPacket;

		err = AudioConverterNew(&inStreamFormat, &mOutputStreamFormat, &mCoreAudioConverterRef);
		if (err != noErr) return -1;

		mTmpSndFileSourceData = (Float64*)malloc((size_t)(5 * mTargetSampleRate * sizeof(Float64) * 2)); //Native libSndFile 64bit float format
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
	sizeInBytes = mLengthFrames * mOutputStreamFormat.mBytesPerFrame * mTargetSampleRate / mNativeSampleRate; //TODO: allow multiple channels
    sizeInBytes -= startInputPosition * mOutputStreamFormat.mBytesPerFrame; // inputPosition is expressed in target sample rate

	if (maxBufSize > SF_COUNT_MAX) maxBufSize = INT32_MAX;

	if (sizeInBytes > maxBufSize) {
		loadWholeFile = FALSE;
		sizeInBytes = maxBufSize;
	}
	else
		loadWholeFile = TRUE;

	kern_return_t theKernelError = vm_allocate(mach_task_self(),
											   (vm_address_t*)outBufferData,
											   (vm_size_t)sizeInBytes,
											   VM_FLAGS_ANYWHERE);
	*numLoadedFrames = 0;
	*numTotalFrames = sizeInBytes / mOutputStreamFormat.mBytesPerFrame;

	if (theKernelError != KERN_SUCCESS) {
		*status = 0;
		*outBufferData = NULL;
		*outBufferDataSize = 0;
		return -1;
	}
	*outBufferDataSize = sizeInBytes;

	//Check if need to seek the file read position
	if (startInputPosition != mNextFrameToLoadPosition) {
		sf_seek(mSndFileRef, (sf_count_t)(startInputPosition*mNativeSampleRate/mTargetSampleRate), SEEK_SET);
        if (mIsUsingSRC && mSRCModel == kAUDSRCModelAppleCoreAudio)
            AudioConverterReset(mCoreAudioConverterRef);
	}

	*status = (loadWholeFile?kAudioFileLoaderStatusEOF:0) | kAudioFileLoaderStatusLoading;
	mIsMakingBackgroundTask	|= kAudioFileLoaderLoadingBuffer;

	if (!mIsUsingSRC) {
		dispatch_group_async(mBackgroundLoadGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			SInt64 readStep = 5 * mTargetSampleRate;
			int readError = noErr;

			while (((mIsMakingBackgroundTask & kAudioFileLoaderLoadingBuffer) != 0)
				   && (loadWholeFile || (((UInt64)*numLoadedFrames * mOutputStreamFormat.mBytesPerFrame) < sizeInBytes))) {
				readStep = 5 * mTargetSampleRate;
				if ((*numLoadedFrames + readStep) > *numTotalFrames)
					readStep = *numTotalFrames - *numLoadedFrames;

				if (mIsIntegerModeOn) {
					OSErr err=noErr;
					UInt32 bytesConverted;

					readStep = sf_readf_double(mSndFileRef, mTmpSndFileSourceData, readStep);
					readError = sf_error(mSndFileRef);

					if ((readError == noErr) && (readStep > 0)) {
						bytesConverted = (UInt32)(readStep*mOutputStreamFormat.mBytesPerFrame);
						err = AudioConverterConvertBuffer(mCoreAudioConverterRef,
														  (UInt32)(readStep*sizeof(Float64)*2),
														  mTmpSndFileSourceData,
														  &bytesConverted,
														  ((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame));
						readStep = bytesConverted / mOutputStreamFormat.mBytesPerFrame;

						if ((err == noErr) && (mIntModeAlignedLowZeroBits > 0))
							[self alignAudioBufferFromHighToLow:(UInt32*)(((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame))
												framesToConvert:readStep];

						readError |= err;
					}
				}
				else {
					readStep = sf_readf_float(mSndFileRef, (float*)(((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame)), readStep);
					readError = sf_error(mSndFileRef);
				}

				if ((readError != noErr) || (readStep <=0)) break;

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

            if (loadWholeFile && (readError == noErr)) {
                //Core audio file length initial value may just be an estimate >= actual length
                //Actual length is known after reading up to the file end.
                *numTotalFrames = *numLoadedFrames;
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
	} else {
		//Use sample rate converter
		switch (mSRCModel) {
			case kAUDSRCModelSRClibSampleRate:
			{
				dispatch_group_async(mBackgroundLoadGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					long readStep = (long)(LIBSRC_OUTPUTBUF_SECONDS * mTargetSampleRate);
					long framesRead;
					OSStatus err = noErr;

					while (((mIsMakingBackgroundTask & kAudioFileLoaderLoadingBuffer) != 0)
						   && (loadWholeFile || (((UInt64)*numLoadedFrames * mOutputStreamFormat.mBytesPerFrame) < sizeInBytes))) {
						readStep = (long)(LIBSRC_OUTPUTBUF_SECONDS * mTargetSampleRate);
						if ((*numLoadedFrames + readStep) > *numTotalFrames)
							readStep = (long)(*numTotalFrames - *numLoadedFrames);

						if (mIsIntegerModeOn) {
							UInt32 bytesConverted;

							framesRead = src_callback_read(mLibSrcState, mTargetSampleRate / mNativeSampleRate,
														   readStep , mTmplibSampleRateOutBuf);

							if (framesRead > 0) {
								bytesConverted = (UInt32)(framesRead*mOutputStreamFormat.mBytesPerFrame);
								err = AudioConverterConvertBuffer(mCoreAudioConverterRef, (UInt32)(framesRead * sizeof(Float32) * 2),
															mTmplibSampleRateOutBuf, &bytesConverted,
															((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame));
								framesRead = bytesConverted / mOutputStreamFormat.mBytesPerFrame;

								if ((err == noErr) && (mIntModeAlignedLowZeroBits > 0))
									[self alignAudioBufferFromHighToLow:(UInt32*)(((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame))
														framesToConvert:readStep];
							}
						}
						else framesRead = src_callback_read(mLibSrcState, mTargetSampleRate / mNativeSampleRate,
													   readStep ,(float*)(((UInt8*)*outBufferData) + (*numLoadedFrames*mOutputStreamFormat.mBytesPerFrame)));
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

					if (loadWholeFile && (framesRead >= 0)) {
						//Core audio file length initial value may just be an estimate >= actual length
						//Actual length is known after reading up to the file end.
						*numTotalFrames = *numLoadedFrames;
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

- (long)readSRCdata:(float**)data
{
	*data = mTmpSRCdata;
	return (long)sf_readf_float(mSndFileRef, mTmpSRCdata, TMP_SRC_BUFFER_SIZE);
}

- (UInt32)readSRCdata:(Float64 **)data forFrames:(UInt32)nbFramesToRead
{
	if (nbFramesToRead > TMP_SRC_BUFFER_SIZE) nbFramesToRead = TMP_SRC_BUFFER_SIZE;
	*data = mTmpSndFileSourceData;
	return (UInt32)sf_readf_double(mSndFileRef, mTmpSndFileSourceData, nbFramesToRead);
}


#pragma mark additional metadata gathering

- (bool)getAiffMetadata:(NSURL*)fileURL
{
	const char *filePathStr = [[fileURL path] fileSystemRepresentation];
	if (filePathStr == NULL) return FALSE;

	TagLib::RIFF::AIFF::File aifffile(filePathStr, false);

	if (aifffile.isValid() && aifffile.tag() ) {
		TagLib::ID3v2::Tag *tag = aifffile.tag();
		TagLib::String str;
		TagLib::uint trackNumber;

		str = tag->title();
		if (!str.isNull())
			[mFileMetadata setObject:[NSString stringWithUTF8String:str.toCString(true)]
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Title]];
		str = tag->artist();
		if (!str.isNull())
			[mFileMetadata setObject:[NSString stringWithUTF8String:str.toCString(true)]
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Artist]];
		str = tag->album();
		if (!str.isNull())
			[mFileMetadata setObject:[NSString stringWithUTF8String:str.toCString(true)]
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Album]];

		trackNumber = tag->track();
		if (trackNumber != 0)
			[mFileMetadata setObject:[NSNumber numberWithInt:trackNumber]
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_TrackNumber]];

		if (!tag->frameListMap().isEmpty() && tag->frameListMap().contains("TCOM")) {
			TagLib::ID3v2::FrameList composerList = tag->frameListMap()["TCOM"];
			if (!composerList.isEmpty())
				[mFileMetadata setObject:[NSString stringWithUTF8String:composerList.front()->toString().toCString(true)]
								  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Composer]];
		}

		if (!tag->frameListMap().isEmpty() && tag->frameListMap().contains("APIC")) {
			TagLib::ID3v2::FrameList coverartList = tag->frameListMap()["APIC"];
			if (!coverartList.isEmpty()) {
				NSImage	*albumArt = nil;
				for(TagLib::ID3v2::FrameList::Iterator coverartIter = coverartList.begin(); coverartIter != coverartList.end(); coverartIter++) {
					TagLib::ID3v2::AttachedPictureFrame *coverart =  dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(*coverartIter);
					if (coverart && (!albumArt || (coverart->type() == TagLib::ID3v2::AttachedPictureFrame::FrontCover))) {
						if (albumArt) [albumArt release];
						albumArt = [[NSImage alloc] initWithData:[NSData dataWithBytes:coverart->picture().data() length:coverart->picture().size()]];
					}
				}
				if (albumArt) {
					[mFileMetadata setObject:albumArt
									  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_CoverImage]];
					[albumArt release];
				}
			}
		}
	}

	return true;
}

- (bool)getWavMetadata:(NSURL*)fileURL
{
	const char *filePathStr = [[fileURL path] fileSystemRepresentation];
	if (filePathStr == NULL) return FALSE;

	TagLib::RIFF::WAV::File wavfile(filePathStr, false);

	if (wavfile.isValid() && wavfile.tag() ) {
		TagLib::ID3v2::Tag *tag = wavfile.tag();
		TagLib::String str;
		TagLib::uint trackNumber;

		str = tag->title();
		if (!str.isNull())
			[mFileMetadata setObject:[NSString stringWithUTF8String:str.toCString(true)]
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Title]];
		str = tag->artist();
		if (!str.isNull())
			[mFileMetadata setObject:[NSString stringWithUTF8String:str.toCString(true)]
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Artist]];
		str = tag->album();
		if (!str.isNull())
			[mFileMetadata setObject:[NSString stringWithUTF8String:str.toCString(true)]
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Album]];

		trackNumber = tag->track();
		if (trackNumber != 0)
			[mFileMetadata setObject:[NSNumber numberWithInt:trackNumber]
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_TrackNumber]];

		if (!tag->frameListMap().isEmpty() && tag->frameListMap().contains("TCOM")) {
			TagLib::ID3v2::FrameList composerList = tag->frameListMap()["TCOM"];
			if (!composerList.isEmpty())
				[mFileMetadata setObject:[NSString stringWithUTF8String:composerList.front()->toString().toCString(true)]
								  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Composer]];
		}

		if (!tag->frameListMap().isEmpty() && tag->frameListMap().contains("APIC")) {
			TagLib::ID3v2::FrameList coverartList = tag->frameListMap()["APIC"];
			if (!coverartList.isEmpty()) {
				NSImage	*albumArt = nil;
				for(TagLib::ID3v2::FrameList::Iterator coverartIter = coverartList.begin(); coverartIter != coverartList.end(); coverartIter++) {
					TagLib::ID3v2::AttachedPictureFrame *coverart =  dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(*coverartIter);
					if (coverart && (!albumArt || (coverart->type() == TagLib::ID3v2::AttachedPictureFrame::FrontCover))) {
						if (albumArt) [albumArt release];
						albumArt = [[NSImage alloc] initWithData:[NSData dataWithBytes:coverart->picture().data() length:coverart->picture().size()]];
					}
				}
				if (albumArt) {
					[mFileMetadata setObject:albumArt
									  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_CoverImage]];
					[albumArt release];
				}
			}
		}
	}

	return true;
}

@end