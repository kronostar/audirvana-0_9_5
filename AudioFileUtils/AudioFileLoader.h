/*
 AudioFileLoader.h

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

 Original code written by Damien Plisson 09/2010
 */

#ifndef __AUDIOFILELOADER_H__
#define __AUDIOFILELOADER_H__

#include <dispatch/dispatch.h>
#include <AudioToolbox/AudioToolbox.h>

@class AppController;

/**
 class AudioFileLoader
 Provides utilities for loading and converting files
 */
@interface AudioFileLoader : NSObject
{
	NSURL *mInputFileURL;
	Float64 mNativeSampleRate,mTargetSampleRate;
	SInt64 mLengthFrames;
	UInt64 mNextFrameToLoadPosition;
	NSMutableDictionary *mFileMetadata;
	AppController *mAppController;
	AudioStreamBasicDescription mOutputStreamFormat;
	dispatch_group_t mBackgroundLoadGroup;
	int mBitDepth;
	int mChannels;
	int mIsMakingBackgroundTask;
	int mSRCModel;
	int mSRCQuality;
	int mSRCComplexity;
	int mIntModeAlignedLowZeroBits; //used for the AudioConverter missing feature: #bits to shift right in the 32bit chunks
	bool mIsIntegerModeOn;
	bool mIsUsingSRC;
}
@property (readonly, getter=inputFileURL) NSURL *mInputFileURL;
@property (readonly, getter=bitDepth) int mBitDepth;
@property (readonly, getter=channels) int mChannels;
@property (readonly, getter=nativeSampleRate) Float64 mNativeSampleRate;
@property (readonly, getter=targetSampleRate) Float64 mTargetSampleRate;
@property (readonly, getter=lengthFrames) SInt64 mLengthFrames;
//@property (getter=bufferIndexForNextChunkToLoad,setter=setBufferIndexForNextChunkToLoad:) SInt32 mbufferIndexForNextChunkToLoad;

/**
 supportedFileExtensions
 Returns the list of supported file extensions
 @return An array of NSString representing supported file extensions
 */
+ (NSArray*)supportedFileExtensions;

/**
 isFormatSupported
 Check if the audio file can be opened with this AudioFileXXXXLoader object
 @param urlToOpen the file to check
 @return true if the file can be opened
 */
+ (bool)isFormatSupported:(NSURL*)fileURL;

/**
 createWithURL
 Creates an AudioFileLoader object with the decoder needed for the audio file to open
 @param urlToOpen the file to open
 @return a new AudioFileLoader object if successful
 */
+ (id)createWithURL:(NSURL*)urlToOpen;

- (id)initWithURL:(NSURL*)urlToOpen;

- (void)close;

/* Metadata getters */
- (NSString*)title;
- (NSString*)artist;
- (NSString*)album;
- (NSString*)composer;
- (NSImage*)coverImage;
- (float)durationInSeconds;
- (UInt64)trackNumber;

/**
 setSampleRateConversion
 Switch on sample rate converter if the target sample rate is not the native one
 @param targetSampleRate the sample rate the output data should be using
 */
- (void)setSampleRateConversion:(Float64)targetSampleRate;

/** enableBackgroundLoadReporting
 Enables reporting of background load progress
 @param appCtrl The AppController which provides the updateLoadStatus method
 */
- (void)enableBackgroundReporting:(AppController*)appCtrl;

/** setIntegerMode
 File will be decoded in an Integer format (different from the standard 32bit float)
 @param intEnable True to enable Integer Mode
 @param intStreamFormat AudioStreamBasicDescription of the integer stream format
 */
- (void)setIntegerMode:(BOOL)intEnable streamFormat:(AudioStreamBasicDescription*)intStreamFormat;


/** alignAudioBufferFromHighToLow
 Converts an integer buffer with 32-mIntModeAlignedLowZeroBits significant bits aligned high to aligned low in 32bit
 @param buffer the audio buffer to convert
 @param nbFrames number of frames to covert
 @comment All other parameters (nbchannels, frameByteSize, endianess, ...) are retrieved internally from the class members
 */
- (void)alignAudioBufferFromHighToLow:(UInt32*)buffer framesToConvert:(UInt64)nbFrames;

/** loadInitialBuffer
 Attempts to load and decode the whole file
 @param outBufferData On output: the audio buffer data (32bit float or other format samples) To be freed by application using vm_deallocate
 @param outBufferDataSize The actual allocated buffer size in bytes
 @param maxBufSize Maximum allowed buffer size in bytes
 @param numTotalFrames The total number of audio frames in the file, may be updated at end of read if the initial value was just an estimate
 @param numLoadedFrames The actual number of audio frames read, will increment during background load
 @param status Status flags (see enum)
 @param nextInputPosition In case of an incomplete file read (due to memory constraints, the next position in frames in target sample rate)
 @param bufIdx Index of the loaded buffer
 @return 0 if success
 */
- (int)loadInitialBuffer:(void**)outBufferData
		AllocatedBufSize:(UInt64*)outBufferDataSize
		   MaxBufferSize:(UInt64)maxBufSize
		  NumTotalFrames:(SInt64*)numTotalFrames
		   NumLoadedFrames:(SInt64*)numLoadedFrames
				  Status:(UInt32*)status
	   NextInputPosition:(SInt64*)nextInputPosition
			   ForBuffer:(int)bufIdx;

/** loadChunk
 Loads and decodes a chunk of the source file.
 @comment Used when loadInitialBuffer was unable to load the whole file due to buffer size limitation.
 @param startInputPosition The start position to read from in the input file in frames in target sample rate.
						   Usually is given by previous call to loadInitialBuffer or to this function
 @param outBufferData On output: the audio buffer data (32bit float or other format samples) To be freed by application using vm_deallocate.
 @param outBufferDataSize The actual allocated buffer size in bytes
 @param maxBufSize Maximum allowed buffer size in bytes
 @param numTotalFrames The total number of audio frames in the file, may be updated at end of read if the initial value was just an estimate
 @param numLoadedFrames The actual number of audio frames read, will increment during background load
 @param status Status flags (see enum)
 @param nextInputPosition In case of an incomplete file read (due to memory constraints, the next position in frames in target sample rate)
 @param bufIdx Index of the loaded buffer
 */
- (int)loadChunk:(UInt64)startInputPosition
   OutBufferData:(void**)outBufferData
AllocatedBufSize:(UInt64*)outBufferDataSize
   MaxBufferSize:(UInt64)maxBufSize
  NumTotalFrames:(SInt64*)numTotalFrames
   NumLoadedFrames:(SInt64*)numLoadedFrames
		  Status:(UInt32*)status
NextInputPosition:(SInt64*)nextInputPosition
	   ForBuffer:(int)bufIdx;

/** abortLoading
 Aborts the background loading operation. Returns only when the background operation is completely aborted.
 */
- (void)abortLoading;

/** unswapBuffer
 Scans through the buffer mem pages to force them to be in memory
 @param bufferData the audio buffer to scan
 @param bufSize the audio buffer size
 @param startingPos The starting position (usually the current playing one) from which the scan is starting
 */
- (void)unswapBuffer:(Float32*)bufferData bufferSize:(SInt64)bufSize from:(SInt64)startingPos;
@end


#define kAFInfoDictionary_CoverImage "cover image"


/*Load status bits*/
enum
{
	kAudioFileLoaderStatusEOF = 1,
	kAudioFileLoaderStatusLoading = 2
};

/* Loading status bits */
enum  {
	kAudioFileLoaderLoadingBuffer = 1,
	kAudioFileLoaderScanningBuffer = 2
};

#endif