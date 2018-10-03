/*
 AudioFileCoreAudioLoader.mm

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

 Original code written by Damien Plisson 08/2010
 */

#include <AudioToolbox/AudioToolbox.h>
#include <taglib/mp4file.h>
#include <taglib/mp4tag.h>
#include <taglib/mpegfile.h>
#include <taglib/id3v2tag.h>
#include <taglib/attachedpictureframe.h>

#include <dispatch/dispatch.h>
#include </usr/include/mach/vm_map.h>

#import "AppController.h"
#import "AudioFileCoreAudioLoader.h"
#import "PreferenceController.h"

#define TMP_SRC_BUFFER_SIZE 4096
#define LIBSRC_OUTPUTBUF_SECONDS 5

@interface AudioFileCoreAudioLoader (mp4Metadata)
- (bool)getMp4Metadata:(NSURL*)fileURL;
- (bool)getMp3Metadata:(NSURL*)fileURL;
- (long)readSRCdata:(float**)data;
@end


#pragma mark SRC callback

static long sampleRateCallBack(void *cb_data, float **data)
{
	AudioFileCoreAudioLoader *coreAudioFileLoader = (AudioFileCoreAudioLoader*) cb_data;
	return [coreAudioFileLoader readSRCdata:data];
}

@implementation AudioFileCoreAudioLoader


+ (NSArray*)supportedFileExtensions
{
	NSArray *coreAudioExtensions;
	UInt32 propertySize;

	propertySize = sizeof(coreAudioExtensions);
	AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AllExtensions, 0, NULL, &propertySize, &coreAudioExtensions);

	return [coreAudioExtensions autorelease];
}

+ (bool)isFormatSupported:(NSURL*)fileURL
{
	NSString *fileExtension;
	bool isSupported = false;

	fileExtension = [[fileURL pathExtension] lowercaseString];


	if ([[self supportedFileExtensions] containsObject:fileExtension]) isSupported = true;
	else isSupported = false;

	return isSupported;
}


- (id)initWithURL:(NSURL*)urlToOpen
{
	OSStatus err;
	UInt32 propertySize;
	AudioFileID audioFileID;
	NSString *fileExtension;

	mTmpSRCdata = NULL;
	mLibSrcState = NULL;
	mTmplibSampleRateOutBuf = NULL;

	fileExtension = [[urlToOpen pathExtension] lowercaseString];

	//Start opening file, and getting metadata (including sampling rate)
	err = ExtAudioFileOpenURL((CFURLRef)urlToOpen, &mInputFileRef);

	if (err != noErr)
	{
		[self release];
		return nil;
	}

	//Get input stream description
	propertySize = sizeof(AudioStreamBasicDescription);
	ExtAudioFileGetProperty(mInputFileRef, kExtAudioFileProperty_FileDataFormat, &propertySize, &mInputStreamFormat);

	if (mInputStreamFormat.mBitsPerChannel == 0) {
		if (mInputStreamFormat.mFormatID == kAudioFormatAppleLossless) {
			switch (mInputStreamFormat.mFormatFlags) {
				case kAppleLosslessFormatFlag_20BitSourceData:
					mBitDepth = 20;
					break;
				case kAppleLosslessFormatFlag_24BitSourceData:
					mBitDepth = 24;
					break;
				case kAppleLosslessFormatFlag_32BitSourceData:
					mBitDepth = 32;
					break;
				case kAppleLosslessFormatFlag_16BitSourceData:
				default:
					mBitDepth = 16;
					break;
			}
		}
		else mBitDepth = 16; //Assume 16bit for other compressed formats
	}
	else mBitDepth = mInputStreamFormat.mBitsPerChannel;

	mNativeSampleRate = mInputStreamFormat.mSampleRate;

	mChannels = 2; //TODO: Implement multi-channel

	propertySize = sizeof(SInt64);
	ExtAudioFileGetProperty(mInputFileRef, kExtAudioFileProperty_FileLengthFrames, &propertySize, &mLengthFrames);

	//Get metadata
	propertySize = sizeof(AudioFileID);
	err = ExtAudioFileGetProperty(mInputFileRef, kExtAudioFileProperty_AudioFile, &propertySize, &audioFileID);
	propertySize = sizeof(CFDictionaryRef);
	err = AudioFileGetProperty(audioFileID, kAudioFilePropertyInfoDictionary, &propertySize, &mFileMetadata);

	//Strangely AAC files metadata is not retrieved by CoreAudio API, need to use mp4v2
	if (([fileExtension caseInsensitiveCompare:@"mp4"] == NSOrderedSame)
		|| ([fileExtension caseInsensitiveCompare:@"m4a"] == NSOrderedSame))
		[self getMp4Metadata:urlToOpen];
	else if ([fileExtension caseInsensitiveCompare:@"mp3"] == NSOrderedSame)
		[self getMp3Metadata:urlToOpen]; //And not recovering mp3 cover art

	return [super initWithURL:urlToOpen];
}

-(void)close
{
	if (mInputFileRef) {
		ExtAudioFileDispose(mInputFileRef);
		mInputFileRef = NULL;
	}
	if (mTmpSRCdata) { free(mTmpSRCdata); mTmpSRCdata = NULL; }
	if (mLibSrcState) { src_delete(mLibSrcState); mLibSrcState = NULL; }
	if (mTmplibSampleRateOutBuf) { free(mTmplibSampleRateOutBuf); mTmplibSampleRateOutBuf = NULL; }
	if (mCoreAudioConverterRef) { AudioConverterDispose(mCoreAudioConverterRef); mCoreAudioConverterRef = NULL; }

	[super close];
}

- (long)readSRCdata:(float**)data
{
	AudioBufferList readData;
	UInt32 framesRead = TMP_SRC_BUFFER_SIZE;

	readData.mNumberBuffers = 1;
	readData.mBuffers[0].mNumberChannels = 2;
	readData.mBuffers[0].mData = mTmpSRCdata;
	readData.mBuffers[0].mDataByteSize = (UInt32)(framesRead*readData.mBuffers[0].mNumberChannels*sizeof(Float32)); //libSampleRate expects 32bit float data

	ExtAudioFileRead(mInputFileRef, &framesRead, &readData);
	*data = mTmpSRCdata;
	return (long)framesRead;
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
	OSStatus err=noErr;
	AudioChannelLayout outLayout;
	AudioConverterRef audioConverter;
	UInt32 propertySize,tmpInt;

	if (mIsUsingSRC && (mSRCModel == kAUDSRCModelSRClibSampleRate)) {
		AudioStreamBasicDescription CAoutputFormat;

		CAoutputFormat.mFormatID = kAudioFormatLinearPCM;
		CAoutputFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
		CAoutputFormat.mBitsPerChannel = 32;
		CAoutputFormat.mSampleRate = mNativeSampleRate;
		CAoutputFormat.mChannelsPerFrame = 2;
		CAoutputFormat.mBytesPerPacket = CAoutputFormat.mChannelsPerFrame * (CAoutputFormat.mBitsPerChannel / 8);
		CAoutputFormat.mFramesPerPacket = 1;
		CAoutputFormat.mBytesPerFrame = CAoutputFormat.mBytesPerPacket;

		err = ExtAudioFileSetProperty(mInputFileRef, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &CAoutputFormat);
	}
	else {
		err = ExtAudioFileSetProperty(mInputFileRef, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &mOutputStreamFormat);
	}


	propertySize = sizeof(AudioChannelLayout);
	err = ExtAudioFileGetProperty(mInputFileRef, kExtAudioFileProperty_FileChannelLayout, &propertySize, &outLayout);
	outLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
	err = ExtAudioFileSetProperty(mInputFileRef, kExtAudioFileProperty_ClientChannelLayout, sizeof(AudioChannelLayout), &outLayout);

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
				propertySize = sizeof(AudioConverterRef);
				ExtAudioFileGetProperty(mInputFileRef, kExtAudioFileProperty_AudioConverter, &propertySize, &audioConverter);

				tmpInt = mSRCComplexity;
				AudioConverterSetProperty(audioConverter, kAudioConverterSampleRateConverterComplexity,
										  sizeof(tmpInt), &tmpInt);

				tmpInt = mSRCQuality;
				AudioConverterSetProperty(audioConverter, kAudioConverterSampleRateConverterQuality,
										  sizeof(tmpInt), &tmpInt);

				// Force converter to resync with file format
				CFArrayRef cfar = NULL;
				err = ExtAudioFileSetProperty(mInputFileRef, kExtAudioFileProperty_ConverterConfig, sizeof(cfar), &cfar);
			}
				break;
		}
	}

	if (err != noErr) return err;

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
	OSStatus err=noErr;
	__block bool loadWholeFile;

	//Get uncompressed file size
	sizeInBytes = mLengthFrames * mOutputStreamFormat.mBytesPerFrame * mTargetSampleRate / mNativeSampleRate; //TODO: allow multiple channels
    sizeInBytes -= startInputPosition * mOutputStreamFormat.mBytesPerFrame;

	if (maxBufSize > INT32_MAX) maxBufSize = INT32_MAX;

	if (sizeInBytes > maxBufSize) {
		loadWholeFile = FALSE;
		sizeInBytes = maxBufSize;
	}
	else
		loadWholeFile = TRUE;

	*numTotalFrames = sizeInBytes / mOutputStreamFormat.mBytesPerFrame;
	*numLoadedFrames = 0;

	kern_return_t theKernelError = vm_allocate(mach_task_self(),
											   (vm_address_t*)outBufferData,
											   (vm_size_t)sizeInBytes,
											   VM_FLAGS_ANYWHERE);

	if (theKernelError != KERN_SUCCESS) {
		*status = 0;
		*outBufferData = NULL;
		*outBufferDataSize = 0;
		return -1;
	}
	*outBufferDataSize = sizeInBytes;

	//Check if need to seek the file read position
	if (startInputPosition != mNextFrameToLoadPosition) {
		ExtAudioFileSeek(mInputFileRef, (SInt64)(startInputPosition*mNativeSampleRate/mTargetSampleRate));
	}

	*status = (loadWholeFile?kAudioFileLoaderStatusEOF:0) | kAudioFileLoaderStatusLoading;
	mIsMakingBackgroundTask |= kAudioFileLoaderLoadingBuffer;

	if (mIsUsingSRC && (mSRCModel == kAUDSRCModelSRClibSampleRate)) {
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
												framesToConvert:framesRead];
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
		return err;
	}
	else {
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
				readErr = ExtAudioFileRead(mInputFileRef, &readStep, &outData);

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

		return err;
	}
}

using namespace std;

-(bool)getMp4Metadata:(NSURL*)fileURL
{
	const char *filePathStr = [[fileURL path] fileSystemRepresentation];
	if (filePathStr == NULL) return FALSE;

	TagLib::MP4::File mp4file(filePathStr, false);

	if (mp4file.isValid() && mp4file.tag() ) {
		TagLib::MP4::Tag *tag = mp4file.tag();
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

		if (!tag->itemListMap().isEmpty() && tag->itemListMap().contains("\251wrt")) {
			[mFileMetadata setObject:[NSString stringWithUTF8String:tag->itemListMap()["\251wrt"].toStringList().toString().toCString(true)]
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_Composer]];
		}

		if (!tag->itemListMap().isEmpty() && tag->itemListMap().contains("covr")) {
			TagLib::MP4::CoverArtList coverartlist = tag->itemListMap()["covr"].toCoverArtList();
			if (!coverartlist.isEmpty()) {
				NSImage	*albumArt = [[NSImage alloc] initWithData:[NSData dataWithBytes:coverartlist.front().data().data() length:coverartlist.front().data().size()]];
				if(albumArt) {
					[mFileMetadata setObject:albumArt
									  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_CoverImage]];
					[albumArt release];
				}
			}
		}
	}

	return true;
}

- (bool)getMp3Metadata:(NSURL *)fileURL
{
	const char *filePathStr = [[fileURL path] fileSystemRepresentation];
	if (filePathStr == NULL) return FALSE;

	TagLib::MPEG::File mp3file(filePathStr, false);

	if (mp3file.isValid() && mp3file.ID3v2Tag(false)) {
		TagLib::ID3v2::Tag *tag = mp3file.ID3v2Tag(false);

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