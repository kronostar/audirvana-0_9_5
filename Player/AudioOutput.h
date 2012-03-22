/*
 AudioOutput.h

 This file is part of AudioNirvana.

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

#import <Cocoa/Cocoa.h>
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>

@interface AudioStreamDescription : NSObject
{
	AudioStreamRangedDescription *mPhysicalFormats;
	AudioStreamRangedDescription *mVirtualFormats;
	UInt32 mCountPhysicalFormats;
	UInt32 mCountVirtualFormats;
	UInt32 streamID;
	UInt32 startingChannel;
	UInt32 numChannels;
}
@property UInt32 streamID;
@property UInt32 startingChannel;
@property UInt32 numChannels;

- (void)setPhysicalFormats:(AudioStreamRangedDescription*)formats count:(UInt32)nbFormats;
- (BOOL)isPhysicalFormatAvailable:(UInt32)bitsPerSample;
- (void)setVirtualFormats:(AudioStreamRangedDescription*)formats count:(UInt32)nbFormats;
- (BOOL)getIntegerModeFormat:(AudioStreamBasicDescription*)streamFormat forSampleRate:(Float64)splRateToBe forMinChannels:(UInt32)minChannels;
- (BOOL)getPhysicalMixableFormat:(AudioStreamBasicDescription*)streamFormat forSampleRate:(Float64)splRateToBe forMinChannels:(UInt32)minChannels;
- (BOOL)isSampleRateHandled:(Float64)splRate withSameStreamFormat:(AudioStreamBasicDescription*)streamFormat;
- (Float64)maxSampleRateforFormat:(AudioStreamBasicDescription*)streamFormat;
@end


/*Lookup structure for audio channel mapping
 taking into account the multiple streams devices
 e.g. multiple mono streams */
typedef struct {
	AudioStreamID streamID;
	UInt32 stream;
	UInt32 channel;
} AudioChannelMapping;


/* This object is not thread safe and should be accessed only from the main thread */
@interface AudioDeviceDescription : NSObject
{
	AudioValueRange* mAvailableSampleRates;
	NSString *name;
	NSString *UID;
	NSMutableArray *streams;
	AudioValueRange mAudioBufferFrameSizeRange;
	AudioDeviceID audioDevID;
	UInt32 mPreferredChannelStereo[2];
	UInt32 mCountAvailableSampleRates;
	UInt32 availableVolumeControls;
}
@property AudioDeviceID audioDevID;
@property (copy) NSString *name;
@property (copy) NSString *UID;
@property UInt32 availableVolumeControls;
@property (retain) NSMutableArray *streams;

- (void)setBufferFrameSizeRange:(Float64)minSize maxFrameSize:(Float64)maxSize;
- (Float64)maximumBufferFrameSize;
- (void)setSampleRates:(AudioValueRange*)splRates count:(UInt32)nbSplRates;
- (Float64)maxSampleRate;
- (Float64)maxSampleRateNotLimited;
- (BOOL)isSampleRateHandled:(Float64)splRate withLimit:(BOOL)isLimitEnforced;
- (void)setPreferredChannelsStereo:(UInt32)leftChannel right:(UInt32)rightChannel;
- (UInt32)getPreferredChannel:(UInt32)channel;
- (void)getChannelMapping:(AudioChannelMapping*)channelMapping forChannel:(UInt32)channel;
@end

@class AppController;
@class AudioFileLoader;


/*data alignment optimized order */
typedef struct {
	Float64 sampleRate;
	SInt64 firstFrameOffset; //Number of frames in the audio track before the first one of this buffer
	SInt64 currentPlayingFrame;
	SInt64 lengthFrames;
	SInt64 loadedFrames;
	SInt64 inputFileNextPosition;
	UInt64 dataSizeInBytes;
	void *data;
	AudioFileLoader *inputFileLoader;
	UInt32 inputFileLoadStatus;
	UInt32 bytesPerFrame;
	UInt32 currentPlayingTimeInSeconds;
} AudioBufferItem;


@class AudioOutput;

/*
 AudioOutputBufferData
 The shared structure with the HAL IO Proc
 This structured is shared accross threads.
 Atomic read/writes on Intel processors is ensured through the correct data alignment
 */
struct _AudioOutputBufferData {
	AudioBufferItem buffers[2];
	AppController *appController;
	AudioOutput	*audioOut;
	AudioChannelMapping channelMap[2]; //stereo
	AudioStreamBasicDescription integerModeStreamFormat;
	AudioStreamBasicDescription integerModeStreamFormatToBe;
    AudioStreamBasicDescription buffersStreamFormat;
	SInt32 playingAudioBuffer;
	SInt32 bufferIndexForNextChunkToLoad; //Split loading: next chunk load is enqueued, will be launch at end of current chunk load
	UInt32 ditheringMode;
	AudioDeviceID selectedAudioDeviceID;

	UInt32 isIOPaused;
	UInt32 playbackStartPhase;

	bool isIntegerModeOn;
	bool isHoggingDevice;
	bool willChangePlayingBuffer;
	bool isSimpleStereoDevice;
};

typedef struct _AudioOutputBufferData AudioOutputBufferData;

@interface AudioOutput : NSObject {
	AudioStreamBasicDescription originalStreamFormat;
	AudioOutputBufferData mBufferData;
	AudioDeviceIOProcID audioOutIOProcID;
	NSMutableArray *audioDevicesList;

	Float64 audioDeviceCurrentNominalSampleRate;
	UInt32 audioDeviceCurrentPhysicalBitDepth;
	UInt32 audioDeviceInitialIOBufferFrameSize;

	SInt32 selectedAudioDeviceIndex;

	bool isPlaying;
}
@property (readonly) NSMutableArray *audioDevicesList;
@property (readonly) SInt32 selectedAudioDeviceIndex;
@property (readonly) bool isPlaying;
@property (readonly) Float64 audioDeviceCurrentNominalSampleRate;
@property (readonly) UInt32 audioDeviceCurrentPhysicalBitDepth;


- (id)initWithController:(AppController*)controller;
- (void)rebuildDevicesList;
- (void)handleDeviceChange:(NSNotification*)notification;
- (void)selectDevice:(NSString*)deviceUID;

- (void)loadDeviceBufferFrameSizeRange:(AudioDeviceDescription*)deviceDesc;
- (void)loadStreamPhysicalFormat:(AudioStreamDescription*)audioStream;
- (void)loadStreamVirtualFormat:(AudioStreamDescription*)audioStream;

- (bool)loadFile:(NSURL*)fileURL toBuffer:(int)bufferToFill;
/** loadNextChunk
 Loads the next chunk for a file that was not completely loaded in playing buffer
 @param bufferToFill the buffer to load index.
 @return true if a next chunk has been loaded, false if file was completely loaded in playing buffer, or any other error
 @comment This method uses information from the other buffer (status, fileloader)
 */
- (bool)loadNextChunk:(int)bufferToFill;
- (bool)loadNextChunk:(int)bufferToFill at:(SInt64)startingPosition;

- (bool)closeBuffers;
- (bool)closeBuffer:(int)bufferToClose;

- (int)playingBuffer;
- (void)setPlayingBuffer:(int)playingBuffer;
- (SInt32)bufferIndexForNextChunkToLoad;
- (bool)bufferContainsWholeTrack:(int)bufferIndex;

/** areBothBuffersFromSameFile
 @return true if both buffers contian data from same audio file (split loading)
 */
- (bool)areBothBuffersFromSameFile;
- (bool)isAudioBuffersEmpty:(int)bufferIndex;

- (bool)willChangePlayingBuffer;
- (void)resetWillChangePlayingBuffer;

- (void)unswapPlayingBuffer;

- (void)setSamplingRate:(Float64)newSamplingRate;
- (bool)isChangingSamplingRate;
- (bool)isIntegerModeOn;
- (UInt32)availableVolumeControls;
- (Float32)masterVolumeScalar:(UInt32)typeOfVolume;
- (Float32)masterVolumeDecibel:(UInt32)typeOfVolume;
- (void)setMasterVolumeScalar:(Float32)newVolume forType:(UInt32)typeOfVolume;
- (void)setMute:(BOOL)isToMute;
- (bool)isMute;

/* Playback control methods
 sequence is:
 1) initiatePlay that calls initiatePlaybackPart2
 2) startPlayback
 3) stop
 */
- (bool)initiatePlayback:(NSError**)outError;
- (BOOL)startPlayback:(NSError**)outError;
- (bool)seek:(UInt64)seekPosition;
- (UInt64)currentPlayingPosition;
- (bool)stop;

- (UInt32)deviceInitializationStatus;

- (bool)pause:(bool)isPaused;
- (bool)isPaused;

@end


/*
 Audio I/O Proc pause conditions flags
 */
enum {
	kAudioIOProcPause = 1,
	kAudioIOProcSampleRateChanging = 2,
	kAudioIOProcAudioBufferSizeChanging = 4
};

/*
 Playback start phases
 */
enum {
	kAudioPlaybackNotInStartingPhase = 0,
	kAudioPlaybackStartHoggingDevice = 1,
	kAudioPlaybackStartDeviceHogged = 2,
	kAudioPlaybackStartChangingStreamFormat = 3,
	kAudioPlaybackStartFinishingDeviceInitialization = 4,
	kAudioPlaybackSwitchingBackToFloatMode = 5
};

/*
 Device volume control flags
 */
enum
{
	kAudioVolumePhysicalControl = 1,
	kAudioVolumeVirtualControl = 2
};

/*
 Dithering modes
 */
enum
{
	kAudioNoDithering = 0,
	kAudioDitheringLinear = 1,
	kAudioDitheringTriangle = 2,
	kAudioDitheringNoiseShaping = 3,

	kAudioDither16bit = 0x100
};