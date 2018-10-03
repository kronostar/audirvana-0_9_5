/*
 AudioFileLoader.m

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

#include <AudioToolbox/AudioToolbox.h>

#import "AppController.h" //For notifying of background load progress
#import "PreferenceController.h"

#import "AudioFileLoader.h"
#import "AudioFileCoreAudioLoader.h"
#import	"AudioFileSndFileLoader.h"
#import "AudioFileFLACLoader.h"

#include <dispatch/dispatch.h>
#include <samplerate/samplerate.h>

@implementation AudioFileLoader
@synthesize mInputFileURL,mBitDepth,mNativeSampleRate,mTargetSampleRate,mLengthFrames,mChannels;

+ (NSArray*)supportedFileExtensions
{
	NSMutableArray *fileExts = [[NSMutableArray alloc] init];

	[fileExts addObjectsFromArray:[AudioFileFLACLoader supportedFileExtensions]];
	[fileExts addObjectsFromArray:[AudioFileSndFileLoader supportedFileExtensions]];
	[fileExts addObjectsFromArray:[AudioFileCoreAudioLoader supportedFileExtensions]];

	return [fileExts autorelease];
}

+ (bool)isFormatSupported:(NSURL*)fileURL
{
	return ([AudioFileFLACLoader isFormatSupported:fileURL]
			|| [AudioFileSndFileLoader isFormatSupported:fileURL]
			|| [AudioFileCoreAudioLoader isFormatSupported:fileURL]);
}

+ (id)createWithURL:(NSURL*)urlToOpen
{
	id newLoaderObject = nil;

	if ([AudioFileFLACLoader isFormatSupported:urlToOpen]) {
		newLoaderObject = [[AudioFileFLACLoader alloc] initWithURL:urlToOpen];
	}
	else if ([AudioFileSndFileLoader isFormatSupported:urlToOpen]) {
		newLoaderObject = [[AudioFileSndFileLoader alloc] initWithURL:urlToOpen];
	}
	else if ([AudioFileCoreAudioLoader isFormatSupported:urlToOpen]) {
			newLoaderObject = [[AudioFileCoreAudioLoader alloc] initWithURL:urlToOpen];
	}

	return [newLoaderObject autorelease];
}

- (id)initWithURL:(NSURL*)urlToOpen
{
	//Vars initializations
	mInputFileURL = urlToOpen;
	[mInputFileURL retain];
	mTargetSampleRate = mNativeSampleRate;
	mNextFrameToLoadPosition = 0;
	mIsUsingSRC = NO;
	mIsMakingBackgroundTask = 0;
	mBackgroundLoadGroup = dispatch_group_create();

	mIntModeAlignedLowZeroBits = 0;
	mIsIntegerModeOn = FALSE;
	mOutputStreamFormat.mBitsPerChannel = 32;
	mOutputStreamFormat.mChannelsPerFrame = 2;
	mOutputStreamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
	mOutputStreamFormat.mBytesPerFrame = mOutputStreamFormat.mChannelsPerFrame * mOutputStreamFormat.mBitsPerChannel / 8;
	mOutputStreamFormat.mBytesPerPacket = mOutputStreamFormat.mBytesPerFrame;
	mOutputStreamFormat.mFormatID = kAudioFormatLinearPCM;
	mOutputStreamFormat.mFramesPerPacket = 1;
	mOutputStreamFormat.mSampleRate = mTargetSampleRate;

	//Sample rate conversion settings
	if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDSampleRateConverterModel] == kAUDSRCModelSRClibSampleRate) {
		mSRCModel = kAUDSRCModelSRClibSampleRate;
		switch ([[NSUserDefaults standardUserDefaults] integerForKey:AUDSampleRateConverterQuality]) {
			case kAUDSRCQualityLowest:
				mSRCQuality = SRC_LINEAR;
				break;
			case kAUDSRCQualityLow:
				mSRCQuality = SRC_ZERO_ORDER_HOLD;
				break;
			case kAUDSRCQualityMedium:
				mSRCQuality = SRC_SINC_FASTEST;
				break;
			case kAUDSRCQualityHigh:
				mSRCQuality = SRC_SINC_MEDIUM_QUALITY;
				break;
			case kAUDSRCQualityMax:
			default:
				mSRCQuality = SRC_SINC_BEST_QUALITY;
				break;
		}
	}
	else {
		mSRCModel = kAUDSRCModelAppleCoreAudio; //Defaults to Apple Core Audio
		switch ([[NSUserDefaults standardUserDefaults] integerForKey:AUDSampleRateConverterQuality]) {
			case kAUDSRCQualityLowest:
				mSRCComplexity = kAudioConverterSampleRateConverterComplexity_Linear;
				mSRCQuality = kAudioConverterQuality_Min;
				break;
			case kAUDSRCQualityLow:
				mSRCComplexity = kAudioConverterSampleRateConverterComplexity_Normal;
				mSRCQuality = kAudioConverterQuality_Medium;
				break;
			case kAUDSRCQualityMedium:
				mSRCComplexity = kAudioConverterSampleRateConverterComplexity_Normal;
				mSRCQuality = kAudioConverterQuality_High;
				break;
			case kAUDSRCQualityHigh:
				mSRCComplexity = kAudioConverterSampleRateConverterComplexity_Mastering;
				mSRCQuality = kAudioConverterQuality_Medium;
				break;
			case kAUDSRCQualityMax:
			default:
				mSRCComplexity = kAudioConverterSampleRateConverterComplexity_Mastering;
				mSRCQuality = kAudioConverterQuality_Max;
				break;
		}
	}


	//Get album cover from folder.jpg if not already loaded from file metadata
	if ([self coverImage] == nil) {
		NSError *err;
		NSImage *albumArt = nil;
		NSURL *fileFolder = [mInputFileURL URLByDeletingLastPathComponent];

		NSURL *folderImage = [fileFolder URLByAppendingPathComponent:@"folder.jpg"];

		if ([folderImage checkResourceIsReachableAndReturnError:&err]) {
			albumArt = [[NSImage alloc] initWithContentsOfURL:folderImage];
		} else {
			folderImage = [fileFolder URLByAppendingPathComponent:@"cover.jpg"];
			if ([folderImage checkResourceIsReachableAndReturnError:&err]) {
				albumArt = [[NSImage alloc] initWithContentsOfURL:folderImage];
			}
			else {
				NSFileManager *fileMgr = [[NSFileManager alloc] init];
				NSArray *folderContents = [fileMgr contentsOfDirectoryAtPath:[fileFolder path] error:NULL];
				NSArray *sleevePngs = [folderContents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH 'Sleeve.png'"]];

				if ([sleevePngs count]>0) {
					albumArt = [[NSImage alloc] initWithContentsOfURL:[fileFolder URLByAppendingPathComponent:[sleevePngs objectAtIndex:0]]];
				}
                else {
                    NSArray *sleeveOtherJpgs = [folderContents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH '.jpg'"]];
                    if ([sleeveOtherJpgs count]>0) {
                        albumArt = [[NSImage alloc] initWithContentsOfURL:[fileFolder URLByAppendingPathComponent:[sleeveOtherJpgs objectAtIndex:0]]];
                    }
                }
				[fileMgr release];
			}

		}

		if (albumArt) {
			[mFileMetadata setObject:albumArt
							  forKey:[NSString stringWithUTF8String: kAFInfoDictionary_CoverImage]];
			[albumArt release];
		}
	}
	return [super init];
}

-(void)close
{
}

-(void)dealloc
{
	[self abortLoading];
	[self close];
	if (mFileMetadata) {
		[mFileMetadata release];
		mFileMetadata = nil;
	}
	if (mInputFileURL) {
		[mInputFileURL release];
		mInputFileURL = nil;
	}
	if (mBackgroundLoadGroup)
		dispatch_release(mBackgroundLoadGroup);
	[super dealloc];
}

- (void)enableBackgroundReporting:(AppController*)appCtrl
{
	mAppController = appCtrl;
}

- (void)setIntegerMode:(BOOL)intEnable streamFormat:(AudioStreamBasicDescription*)intStreamFormat
{
	mIsIntegerModeOn = intEnable;
	if (intEnable && intStreamFormat) {
		memcpy(&mOutputStreamFormat, intStreamFormat,sizeof(AudioStreamBasicDescription));
		mOutputStreamFormat.mSampleRate = mTargetSampleRate;

		// Need to use workaround for missing format conversion by AudioConverter ?
		// The workaround consists in getting an aligned high stream, and shift right the frame bits to get an aligned low stream
		if ((mOutputStreamFormat.mFormatFlags & (kAudioFormatFlagIsPacked | kAudioFormatFlagIsAlignedHigh)) == 0) {
            if ((mOutputStreamFormat.mFormatFlags & kAudioFormatFlagIsBigEndian) == 0) {
                //Little endian low aligned is like
                mOutputStreamFormat.mFormatFlags |= kAudioFormatFlagIsAlignedHigh;
            }
            else {
                mIntModeAlignedLowZeroBits = (mOutputStreamFormat.mBytesPerFrame *8)/mOutputStreamFormat.mChannelsPerFrame - mOutputStreamFormat.mBitsPerChannel;
                mOutputStreamFormat.mFormatFlags |= kAudioFormatFlagIsAlignedHigh;
            }
		}
		else
			mIntModeAlignedLowZeroBits = 0;
	}
	else {
		mOutputStreamFormat.mBitsPerChannel = 32;
		mOutputStreamFormat.mChannelsPerFrame = 2;
		mOutputStreamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
		mOutputStreamFormat.mBytesPerFrame = mOutputStreamFormat.mChannelsPerFrame * mOutputStreamFormat.mBitsPerChannel / 8;
		mOutputStreamFormat.mBytesPerPacket = mOutputStreamFormat.mBytesPerFrame;
		mOutputStreamFormat.mFormatID = kAudioFormatLinearPCM;
		mOutputStreamFormat.mFramesPerPacket = 1;
		mOutputStreamFormat.mSampleRate = mTargetSampleRate;
	}

}

- (void)alignAudioBufferFromHighToLow:(UInt32*)buffer framesToConvert:(UInt64)nbFrames
{
	UInt64 frameIdx;
	UInt32 channelIdx;

	if ((mOutputStreamFormat.mFormatFlags & kAudioFormatFlagIsBigEndian) == kAudioFormatFlagsNativeEndian) {
		// Audio stream endianess is CPU native
		for (frameIdx=0;frameIdx<nbFrames;frameIdx++) {
			for(channelIdx=0;channelIdx<mOutputStreamFormat.mChannelsPerFrame;channelIdx++) {
				buffer[frameIdx*mOutputStreamFormat.mChannelsPerFrame +channelIdx]
				= buffer[frameIdx*mOutputStreamFormat.mChannelsPerFrame +channelIdx] >> mIntModeAlignedLowZeroBits;
			}
		}
	}
	else {
		// Audio stream endianess is not the CPU native
		UInt32 nativeEndianValue;

		for (frameIdx=0;frameIdx<nbFrames;frameIdx++) {
			for(channelIdx=0;channelIdx<mOutputStreamFormat.mChannelsPerFrame;channelIdx++) {
				nativeEndianValue = Endian32_Swap(buffer[frameIdx*mOutputStreamFormat.mChannelsPerFrame +channelIdx]);
				nativeEndianValue = nativeEndianValue >> mIntModeAlignedLowZeroBits;
				buffer[frameIdx*mOutputStreamFormat.mChannelsPerFrame +channelIdx] = Endian32_Swap(nativeEndianValue);
			}
		}
	}

}

-(NSString*)title
{
	NSString *fileTitle = [mFileMetadata objectForKey:[NSString stringWithUTF8String: kAFInfoDictionary_Title]];

	if (fileTitle) return fileTitle;
	else return [mInputFileURL lastPathComponent];
}

-(NSString*)artist
{
	return [mFileMetadata objectForKey:[NSString stringWithUTF8String: kAFInfoDictionary_Artist]];
}

-(NSString*)album
{
	return [mFileMetadata objectForKey:[NSString stringWithUTF8String: kAFInfoDictionary_Album]];
}

-(NSString*)composer
{
	return [mFileMetadata objectForKey:[NSString stringWithUTF8String: kAFInfoDictionary_Composer]];
}

- (NSImage*)coverImage
{
	return [mFileMetadata objectForKey:[NSString stringWithUTF8String: kAFInfoDictionary_CoverImage]];
}

- (float)durationInSeconds
{
	if (mNativeSampleRate == 0) return (float)-1.0;

	return ((float)mLengthFrames)/((float)mNativeSampleRate);
}

- (UInt64)trackNumber
{
	id obj = [mFileMetadata
			  objectForKey:[NSString stringWithUTF8String: kAFInfoDictionary_TrackNumber]];
	if (obj)
		return [obj intValue];
	else
		return 0;
}

- (void)setSampleRateConversion:(Float64)targetSampleRate
{
	mTargetSampleRate = targetSampleRate;
	mOutputStreamFormat.mSampleRate = mTargetSampleRate;
	if (mTargetSampleRate != mNativeSampleRate) mIsUsingSRC = YES;
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
	return -1;
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
	return -1;
}

- (void)abortLoading
{
	if (mIsMakingBackgroundTask != 0) {
		mIsMakingBackgroundTask = 0;
		dispatch_group_wait(mBackgroundLoadGroup, DISPATCH_TIME_FOREVER);
	}
}

#pragma optimization_level 0

- (void)unswapBuffer:(Float32*)bufferData bufferSize:(SInt64)bufSize from:(SInt64)startingPos
{
	mIsMakingBackgroundTask |= kAudioFileLoaderScanningBuffer;
	dispatch_group_async(mBackgroundLoadGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		SInt64 pos=startingPos;
		Float32 x=0;
		while ((pos < bufSize) && ((mIsMakingBackgroundTask & kAudioFileLoaderScanningBuffer) != 0)) {
			x += bufferData[pos];
			pos += 1024; // A mem page size is 4kB, so 1k floats
		}
	});
}

#pragma optimization_level reset
@end