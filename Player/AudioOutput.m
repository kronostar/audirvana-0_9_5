/*
 AudioOutput.m

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

#include <strings.h>
#include <libkern/OSAtomic.h>
#include <dispatch/dispatch.h>
#include </usr/include/mach/vm_map.h>

#import "AudioOutput.h"
#import "AppController.h"
#import "PreferenceController.h"
#import "AudioFileLoader.h"


#pragma mark Simple structures implementation

#pragma mark AudioStreamDescription implementation

@implementation AudioStreamDescription
@synthesize streamID,startingChannel,numChannels;

- (id)init {
	mPhysicalFormats = NULL;
	mCountPhysicalFormats = 0;
	mVirtualFormats = NULL;
	mCountVirtualFormats = 0;
	return [super init];
}

- (void)dealloc {
	if (mPhysicalFormats) free(mPhysicalFormats);
	mPhysicalFormats = NULL;
	if (mVirtualFormats) free(mVirtualFormats);
	mVirtualFormats = NULL;
	[super dealloc];
}

- (void)setPhysicalFormats:(AudioStreamRangedDescription*)formats count:(UInt32)nbFormats
{
	if (mPhysicalFormats) free(mPhysicalFormats);
	mPhysicalFormats = formats;
	mCountPhysicalFormats = nbFormats;
}

- (void)setVirtualFormats:(AudioStreamRangedDescription*)formats count:(UInt32)nbFormats
{
	if (mVirtualFormats) free(mVirtualFormats);
	mVirtualFormats = formats;
	mCountVirtualFormats = nbFormats;
}


- (BOOL)isPhysicalFormatAvailable:(UInt32)bitsPerSample
{
	BOOL isAvail = FALSE;
	UInt32 formatIdx;

	for (formatIdx=0;formatIdx<mCountPhysicalFormats;formatIdx++) {
		if (mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel == bitsPerSample) {
			isAvail = TRUE;
			break;
		}
	}

	return isAvail;
}

- (BOOL)getIntegerModeFormat:(AudioStreamBasicDescription*)streamFormat forSampleRate:(Float64)splRateToBe forMinChannels:(UInt32)minChannels;
{
	BOOL isAvail = FALSE;
	BOOL splRateFound = FALSE;
	UInt32 formatIdx;
	UInt32 bitsPerSample = 0;

	for (formatIdx=0;formatIdx<mCountPhysicalFormats;formatIdx++) {
		if (((mPhysicalFormats[formatIdx].mFormat.mFormatFlags & (kAudioFormatFlagIsNonMixable | kAudioFormatFlagIsFloat))
			== kAudioFormatFlagIsNonMixable)
			&& (mPhysicalFormats[formatIdx].mFormat.mFormatID == kAudioFormatLinearPCM)
			&& (mPhysicalFormats[formatIdx].mFormat.mChannelsPerFrame >= minChannels)) {
			isAvail = TRUE;
			if ((mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel > bitsPerSample)
				&& (mPhysicalFormats[formatIdx].mFormat.mSampleRate == splRateToBe)) {

				bitsPerSample = mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel;
				splRateFound = TRUE;
				memcpy(streamFormat,&mPhysicalFormats[formatIdx].mFormat,sizeof(AudioStreamBasicDescription));
			}
		}
	}

	//Sample rate not found, check if one above exists (case for devices with sample rate ranges)
	if (isAvail & !splRateFound) {
		for (formatIdx=0;formatIdx<mCountPhysicalFormats;formatIdx++) {
			if (((mPhysicalFormats[formatIdx].mFormat.mFormatFlags & (kAudioFormatFlagIsNonMixable | kAudioFormatFlagIsFloat))
				 == kAudioFormatFlagIsNonMixable)
				&& (mPhysicalFormats[formatIdx].mFormat.mFormatID == kAudioFormatLinearPCM)
				&& (mPhysicalFormats[formatIdx].mFormat.mChannelsPerFrame >= minChannels)) {

				if (mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel > bitsPerSample) {
					bitsPerSample = mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel;
					if (mPhysicalFormats[formatIdx].mFormat.mSampleRate >= splRateToBe) {
						memcpy(streamFormat,&mPhysicalFormats[formatIdx].mFormat,sizeof(AudioStreamBasicDescription));
						splRateFound = TRUE;
						break;
					}
				}
				else if ((mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel == bitsPerSample)
						 && (mPhysicalFormats[formatIdx].mFormat.mSampleRate >= splRateToBe)) {
					splRateFound = TRUE;
					memcpy(streamFormat,&mPhysicalFormats[formatIdx].mFormat,sizeof(AudioStreamBasicDescription));
					break;
				}
			}
		}
	}

	return (isAvail & splRateFound);
}

- (BOOL)getPhysicalMixableFormat:(AudioStreamBasicDescription*)streamFormat forSampleRate:(Float64)splRateToBe forMinChannels:(UInt32)minChannels;
{
	BOOL isAvail = FALSE;
	BOOL splRateFound = FALSE;
	UInt32 formatIdx;
	UInt32 bitsPerSample = 0;

	for (formatIdx=0;formatIdx<mCountPhysicalFormats;formatIdx++) {
		if (((mPhysicalFormats[formatIdx].mFormat.mFormatFlags & (kAudioFormatFlagIsNonMixable | kAudioFormatFlagIsFloat)) == 0)
			&& (mPhysicalFormats[formatIdx].mFormat.mFormatID == kAudioFormatLinearPCM)
			&& (mPhysicalFormats[formatIdx].mFormat.mChannelsPerFrame >= minChannels)) {
			isAvail = TRUE;
			if ((mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel > bitsPerSample)
				&& (mPhysicalFormats[formatIdx].mFormat.mSampleRate == splRateToBe)) {

				bitsPerSample = mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel;
				splRateFound = TRUE;
				memcpy(streamFormat,&mPhysicalFormats[formatIdx].mFormat,sizeof(AudioStreamBasicDescription));
			}
		}
	}

	//Sample rate not found, check if one above exists (case for devices with sample rate ranges)
	if (isAvail & !splRateFound) {
		for (formatIdx=0;formatIdx<mCountPhysicalFormats;formatIdx++) {
			if (((mPhysicalFormats[formatIdx].mFormat.mFormatFlags & (kAudioFormatFlagIsNonMixable | kAudioFormatFlagIsFloat)) == 0)
				&& (mPhysicalFormats[formatIdx].mFormat.mFormatID == kAudioFormatLinearPCM)
				&& (mPhysicalFormats[formatIdx].mFormat.mChannelsPerFrame >= minChannels)) {

				if (mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel > bitsPerSample) {
					bitsPerSample = mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel;
					if (mPhysicalFormats[formatIdx].mFormat.mSampleRate >= splRateToBe) {
						memcpy(streamFormat,&mPhysicalFormats[formatIdx].mFormat,sizeof(AudioStreamBasicDescription));
						splRateFound = TRUE;
						break;
					}
				}
				else if ((mPhysicalFormats[formatIdx].mFormat.mBitsPerChannel == bitsPerSample)
						 && (mPhysicalFormats[formatIdx].mFormat.mSampleRate >= splRateToBe)) {
					splRateFound = TRUE;
					memcpy(streamFormat,&mPhysicalFormats[formatIdx].mFormat,sizeof(AudioStreamBasicDescription));
					break;
				}
			}
		}
	}

	return (isAvail & splRateFound);
}

- (BOOL)isSampleRateHandled:(Float64)splRate withSameStreamFormat:(AudioStreamBasicDescription*)streamFormat;
{
    UInt32 formatIdx;
    BOOL isHandled = FALSE;

    for (formatIdx=0;formatIdx<mCountVirtualFormats;formatIdx++) {
        if (((mVirtualFormats[formatIdx].mSampleRateRange.mMaximum == splRate)
            || ((mVirtualFormats[formatIdx].mSampleRateRange.mMinimum <= splRate)
                && (splRate <= mVirtualFormats[formatIdx].mSampleRateRange.mMaximum)))
             && (mVirtualFormats[formatIdx].mFormat.mFormatID == streamFormat->mFormatID)
             && (mVirtualFormats[formatIdx].mFormat.mFormatFlags == streamFormat->mFormatFlags)
             && (mVirtualFormats[formatIdx].mFormat.mChannelsPerFrame == streamFormat->mChannelsPerFrame)
             && (mVirtualFormats[formatIdx].mFormat.mBitsPerChannel == streamFormat->mBitsPerChannel)
             && (mVirtualFormats[formatIdx].mFormat.mBytesPerFrame == streamFormat->mBytesPerFrame)) {

            isHandled = TRUE;
            break;
        }
    }
    return isHandled;
}


- (Float64)maxSampleRateforFormat:(AudioStreamBasicDescription*)streamFormat
{
    Float64 splRateLimit = MAXFLOAT;
    Float64 maxSampleRate = 0.0;

    switch ([[NSUserDefaults standardUserDefaults] integerForKey:AUDMaxSampleRateLimit]) {
        case kAUDSRCMaxSplRate192kHz:
            splRateLimit = 192000.0;
            break;
        case kAUDSRCMaxSplRate96kHz:
            splRateLimit = 96000.0;
            break;
        case kAUDSRCMaxSplRate48kHz:
            splRateLimit = 48000.0;
            break;
        case kAUDSRCMaxSplRate44_1kHz:
            splRateLimit = 44100.0;
            break;

        case kAUDSRCMaxSplRateNoLimit:
        default:
            splRateLimit = MAXFLOAT;
            break;
    }

    UInt32 formatIdx;

    for (formatIdx=0;formatIdx<mCountVirtualFormats;formatIdx++) {
        if ((mVirtualFormats[formatIdx].mFormat.mFormatID == streamFormat->mFormatID)
            && (mVirtualFormats[formatIdx].mFormat.mFormatFlags == streamFormat->mFormatFlags)
            && (mVirtualFormats[formatIdx].mFormat.mChannelsPerFrame == streamFormat->mChannelsPerFrame)
            && (mVirtualFormats[formatIdx].mFormat.mBitsPerChannel == streamFormat->mBitsPerChannel)
            && (mVirtualFormats[formatIdx].mFormat.mBytesPerFrame == streamFormat->mBytesPerFrame)) {

            if (mVirtualFormats[formatIdx].mSampleRateRange.mMaximum > maxSampleRate)
                if (mVirtualFormats[formatIdx].mSampleRateRange.mMaximum <= splRateLimit) {
                    maxSampleRate = mVirtualFormats[formatIdx].mSampleRateRange.mMaximum;
                }
                else if ((mVirtualFormats[formatIdx].mSampleRateRange.mMinimum <= splRateLimit)
                     && (splRateLimit > maxSampleRate)) {
                    maxSampleRate = splRateLimit;
                }
        }
    }

	return maxSampleRate;
}

- (NSString*)description
{
	UInt32 i;
	NSMutableString *dbgStr = [[[NSMutableString alloc] initWithCapacity:200] autorelease];

	[dbgStr appendFormat:@"\nStream ID 0x%x %i channels starting at %i\n%i virtual formats:",streamID,numChannels,startingChannel,mCountVirtualFormats];

	//Virtual formats
	for (i=0;i<mCountVirtualFormats;i++) {
		if (mVirtualFormats[i].mFormat.mFormatID == kAudioFormatLinearPCM) {
			[dbgStr appendFormat:@"\n%@ linear PCM %@ %ibits %@ %@ %@",
			 (mVirtualFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsNonMixable)?@"Non-mixable":@"Mixable",
			 (mVirtualFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved)?@"Non-interleaved":@"Interleaved",
			 mVirtualFormats[i].mFormat.mBitsPerChannel,
			 (mVirtualFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsBigEndian)?@"big endian":@"little endian",
			 (mVirtualFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsSignedInteger)?@"Signed":@"",
			 (mVirtualFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsFloat)?@"Float":@"Integer"];
			if ((mVirtualFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsPacked) == 0) {
				[dbgStr appendFormat:@" %@ in %ibit",
				 (mVirtualFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsAlignedHigh)?@"aligned High":@"aligned low",
				 8*mVirtualFormats[i].mFormat.mBytesPerFrame/((mVirtualFormats[i].mFormat.mChannelsPerFrame ==0)?1:mVirtualFormats[i].mFormat.mChannelsPerFrame)
				 ];
			}
			if (mVirtualFormats[i].mSampleRateRange.mMinimum == mVirtualFormats[i].mSampleRateRange.mMaximum)
				[dbgStr appendFormat:@" @%.1fkHz",mVirtualFormats[i].mSampleRateRange.mMaximum/1000.0f];
			else
				[dbgStr appendFormat:@" @%.1f to %.1fkHz",mVirtualFormats[i].mSampleRateRange.mMinimum/1000.0f,
				 mVirtualFormats[i].mSampleRateRange.mMaximum/1000.0f];
		}
		else {
			[dbgStr appendFormat:@"\nNon-PCM format: %c%c%c%c",
			 (mVirtualFormats[i].mFormat.mFormatID >> 24) & 0xFF,
			 (mVirtualFormats[i].mFormat.mFormatID >> 16) & 0xFF,
			 (mVirtualFormats[i].mFormat.mFormatID >> 8) & 0xFF,
			 mVirtualFormats[i].mFormat.mFormatID & 0xFF];
		}

	}

	//Physical formats
	[dbgStr appendFormat:@"\n\n%i physical formats",mCountPhysicalFormats];
	for (i=0;i<mCountPhysicalFormats;i++) {
		if (mPhysicalFormats[i].mFormat.mFormatID == kAudioFormatLinearPCM) {
			[dbgStr appendFormat:@"\n%@ linear PCM %@ %ibits %@ %@ %@",
			 (mPhysicalFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsNonMixable)?@"Non-mixable":@"Mixable",
			 (mPhysicalFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved)?@"Non-interleaved":@"Interleaved",
			 mPhysicalFormats[i].mFormat.mBitsPerChannel,
			 (mPhysicalFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsBigEndian)?@"big endian":@"little endian",
			 (mPhysicalFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsSignedInteger)?@"Signed":@"",
			 (mPhysicalFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsFloat)?@"Float":@"Integer"];
			if ((mPhysicalFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsPacked) == 0) {
				[dbgStr appendFormat:@" %@ in %ibit",
				 (mPhysicalFormats[i].mFormat.mFormatFlags & kAudioFormatFlagIsAlignedHigh)?@"aligned High":@"aligned low",
				 8*mPhysicalFormats[i].mFormat.mBytesPerFrame/((mPhysicalFormats[i].mFormat.mChannelsPerFrame ==0)?1:mPhysicalFormats[i].mFormat.mChannelsPerFrame)
				 ];
			}
			if (mPhysicalFormats[i].mSampleRateRange.mMinimum == mPhysicalFormats[i].mSampleRateRange.mMaximum)
				[dbgStr appendFormat:@" @%.1fkHz",mPhysicalFormats[i].mSampleRateRange.mMaximum/1000.0f];
			else
				[dbgStr appendFormat:@" @%.1f to %.1fkHz",mPhysicalFormats[i].mSampleRateRange.mMinimum/1000.0f,
				 mPhysicalFormats[i].mSampleRateRange.mMaximum/1000.0f];

		}
		else {
			[dbgStr appendFormat:@"\nNon-PCM format: %c%c%c%c",
			 (mPhysicalFormats[i].mFormat.mFormatID >> 24) & 0xFF,
			 (mPhysicalFormats[i].mFormat.mFormatID >> 16) & 0xFF,
			 (mPhysicalFormats[i].mFormat.mFormatID >> 8) & 0xFF,
			 mPhysicalFormats[i].mFormat.mFormatID & 0xFF];
		}

	}

	return dbgStr;
}
@end


#pragma mark AudioDeviceDescription implementation

@implementation AudioDeviceDescription
@synthesize audioDevID,name,UID,availableVolumeControls,streams;

- (id)init {
	mAvailableSampleRates = NULL;
	mCountAvailableSampleRates = 0;
	mAudioBufferFrameSizeRange.mMinimum = 0;
	mAudioBufferFrameSizeRange.mMaximum = 0;
	name = nil;
	UID = nil;
	streams = nil;
	return [super init];
}

- (void)dealloc
{
	if (mAvailableSampleRates) free(mAvailableSampleRates);
	if (name) [name release];
	if (UID) [UID release];
	if (streams) [streams release];
	[super dealloc];
}

- (void)setBufferFrameSizeRange:(Float64)minSize maxFrameSize:(Float64)maxSize
{
	mAudioBufferFrameSizeRange.mMinimum = minSize;
	mAudioBufferFrameSizeRange.mMaximum = maxSize;
}

- (Float64)maximumBufferFrameSize
{
	UInt32 pwrOf2;
	//Return the highest buffer that is a power of 2
	//Limits clicking with some drivers
	for (pwrOf2=16;pwrOf2>0;pwrOf2--)
		if (((UInt64)mAudioBufferFrameSizeRange.mMaximum & (1 << pwrOf2)) != 0)
			return (1 << pwrOf2);

	return mAudioBufferFrameSizeRange.mMaximum;
}

- (void)setSampleRates:(AudioValueRange*)splRates count:(UInt32)nbSplRates
{
	if (mAvailableSampleRates) free(mAvailableSampleRates);
	mAvailableSampleRates = splRates;
	mCountAvailableSampleRates = nbSplRates;
}

- (Float64)maxSampleRate
{
    Float64 splRateLimit = MAXFLOAT;
    Float64 maxSampleRate = 0.0;

    switch ([[NSUserDefaults standardUserDefaults] integerForKey:AUDMaxSampleRateLimit]) {
        case kAUDSRCMaxSplRate192kHz:
            splRateLimit = 192000.0;
            break;
        case kAUDSRCMaxSplRate96kHz:
            splRateLimit = 96000.0;
            break;
        case kAUDSRCMaxSplRate48kHz:
            splRateLimit = 48000.0;
            break;
        case kAUDSRCMaxSplRate44_1kHz:
            splRateLimit = 44100.0;
            break;

        case kAUDSRCMaxSplRateNoLimit:
        default:
            splRateLimit = MAXFLOAT;
            break;
    }

    UInt32 splRateIdx;
    if (!mAvailableSampleRates) return 0.0;

    for (splRateIdx=0;splRateIdx<mCountAvailableSampleRates;splRateIdx++) {
        if (mAvailableSampleRates[splRateIdx].mMaximum > maxSampleRate)
            if (mAvailableSampleRates[splRateIdx].mMaximum <= splRateLimit) {
                maxSampleRate = mAvailableSampleRates[splRateIdx].mMaximum;
            }
        else if ((mAvailableSampleRates[splRateIdx].mMinimum <= splRateLimit)
                 && (splRateLimit > maxSampleRate)) {
            maxSampleRate = splRateLimit;
        }
    }

	return maxSampleRate;
}

- (Float64)maxSampleRateNotLimited
{
    Float64 maxSampleRate = 0.0;

    UInt32 splRateIdx;
    if (!mAvailableSampleRates) return 0.0;

    for (splRateIdx=0;splRateIdx<mCountAvailableSampleRates;splRateIdx++) {
        if (mAvailableSampleRates[splRateIdx].mMaximum > maxSampleRate)
            maxSampleRate = mAvailableSampleRates[splRateIdx].mMaximum;
    }

	return maxSampleRate;
}

- (BOOL)isSampleRateHandled:(Float64)splRate withLimit:(BOOL)isLimitEnforced
{
	BOOL isHandled = FALSE;
	UInt32 splRateIdx;

    if (isLimitEnforced) {
        switch ([[NSUserDefaults standardUserDefaults] integerForKey:AUDMaxSampleRateLimit]) {
            case kAUDSRCMaxSplRate192kHz:
                if (splRate > 192000.0f) return NO;
                break;
            case kAUDSRCMaxSplRate96kHz:
                if (splRate > 96000.0f) return NO;
                break;
            case kAUDSRCMaxSplRate48kHz:
                if (splRate > 48000.0f) return NO;
                break;
            case kAUDSRCMaxSplRate44_1kHz:
                if (splRate > 44100.0f) return NO;
                break;

            case kAUDSRCMaxSplRateNoLimit:
            default:
                break;
        }
    }

	for (splRateIdx=0;splRateIdx<mCountAvailableSampleRates;splRateIdx++) {
		if ((mAvailableSampleRates[splRateIdx].mMaximum == splRate)
			|| ((mAvailableSampleRates[splRateIdx].mMinimum <= splRate)
				&& (splRate <= mAvailableSampleRates[splRateIdx].mMaximum))) {
			isHandled = TRUE;
			break;
		}
	}

	return isHandled;
}

- (void)setPreferredChannelsStereo:(UInt32)leftChannel right:(UInt32)rightChannel
{
	mPreferredChannelStereo[0] = leftChannel;
	mPreferredChannelStereo[1] = rightChannel;
}

- (UInt32)getPreferredChannel:(UInt32)channel
{
	switch (channel) {
		case 0:
			return mPreferredChannelStereo[0];
			break;
		case 1:
			return mPreferredChannelStereo[1];
			break;
		default:
			return 0;
			break;
	}
}

- (void)getChannelMapping:(AudioChannelMapping*)channelMapping forChannel:(UInt32)channel
{
	UInt32 i;
	AudioStreamDescription *streamDesc;

	for (i=0;i<[streams count];i++) {
		streamDesc = [streams objectAtIndex:i];
		if (([streamDesc startingChannel] <= channel)
			&& (channel < ([streamDesc startingChannel] + [streamDesc numChannels]))) {
			channelMapping->stream = i;
			channelMapping->channel = channel - [streamDesc startingChannel];
			channelMapping->streamID = [streamDesc streamID];
			break;
		}
	}
}

- (NSString*)description
{
	UInt32 i;
	UInt32 audioBufferFrameSize;
	UInt32 propertySize = sizeof(UInt32);
	AudioObjectPropertyAddress propertyAddress;
	NSMutableString *debugStr = [[[NSMutableString alloc] initWithCapacity:200] autorelease];

	[debugStr appendFormat:@"\nID 0x%x %@\tUID:%@\n%i available sample rates up to %.1fHz",audioDevID,name,UID,mCountAvailableSampleRates,[self maxSampleRateNotLimited]];

	for (i=0;i<mCountAvailableSampleRates;i++)
		if (mAvailableSampleRates[i].mMinimum == mAvailableSampleRates[i].mMaximum)
			[debugStr appendFormat:@"\n%.1f",mAvailableSampleRates[i].mMaximum];
		else
			[debugStr appendFormat:@"\n%.1f to %.1f",mAvailableSampleRates[i].mMinimum,mAvailableSampleRates[i].mMaximum];

	[debugStr appendFormat:@"\n\nAudio buffer frame size : %.0f to %.0f frames",mAudioBufferFrameSizeRange.mMinimum,mAudioBufferFrameSizeRange.mMaximum];

	propertyAddress.mSelector = kAudioDevicePropertyBufferFrameSize;
	propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	AudioObjectGetPropertyData(audioDevID, &propertyAddress, 0, NULL, &propertySize, &audioBufferFrameSize);
	[debugStr appendFormat:@"\nCurrent I/O buffer frame size : %i",audioBufferFrameSize];

	[debugStr appendFormat:@"\nPhysical (analog) volume control: %@\nVirtual (digital) volume control: %@",
	 (availableVolumeControls & kAudioVolumePhysicalControl)?@"Yes":@"No",
	 (availableVolumeControls & kAudioVolumeVirtualControl)?@"Yes":@"No"];

	[debugStr appendFormat:@"\nPreferred stereo channels L:%i R:%i",mPreferredChannelStereo[0],mPreferredChannelStereo[1]];

	return debugStr;
}
@end

#pragma mark -
#pragma mark AudioOutput private methods

@interface AudioOutput(deviceInit)
- (BOOL)getIntegerModeFormat:(AudioStreamBasicDescription*)streamFormat forSampleRate:(Float64)splRateToBe;
- (BOOL)getPhysicalMixableFormat:(AudioStreamBasicDescription*)streamFormat forSampleRate:(Float64)splRateToBe;
- (bool)initiatePlaybackAfterHoggingDevice;
- (bool)initiatePlaybackCompletingInit;
- (void)initiatePlaybackTimedOut;
- (void)completeDeviceStop;
- (void)samplerateSwitchIsComplete;
- (void)samplerateSwitchUnPause;
@end



#pragma mark Core Audio callback

/*CoreAudio HAL input callack */
OSStatus coreAudioOutputIOProc(AudioDeviceID  inDevice,
                  const AudioTimeStamp*   inNow,
                  const AudioBufferList*  inInputData,
                  const AudioTimeStamp*   inInputTime,
                  AudioBufferList*        outOutputData,
                  const AudioTimeStamp*   inOutputTime,
                  void*                   inClientData)
{
    UInt32 newCurrentSeconds,playingBuffer;
	UInt32 framesToCopy,framesCopied;
	bool bufferSwap = NO;

	AudioOutputBufferData *bufferData = (AudioOutputBufferData *)inClientData;

	if (bufferData->isIOPaused) return kAudioHardwareNoError;

	playingBuffer = bufferData->playingAudioBuffer; //For thread safety, make a local copy in this thread

	if ((playingBuffer > 1)
		|| (bufferData->buffers[playingBuffer].loadedFrames <= 0)) //Pause (no Sound) if no buffer ready
		return kAudioHardwareNoError;

	//check end of buffer
	framesToCopy = outOutputData->mBuffers[bufferData->channelMap[0].stream].mDataByteSize*2/outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels
		/bufferData->buffers[playingBuffer].bytesPerFrame;

	if ((SInt64)(bufferData->buffers[playingBuffer].currentPlayingFrame + framesToCopy) > bufferData->buffers[playingBuffer].loadedFrames) {
		framesToCopy = (UInt32)(bufferData->buffers[playingBuffer].loadedFrames - bufferData->buffers[playingBuffer].currentPlayingFrame);

		//then check if we are at end of current buffer, or just need to pause waiting for load completeness
		if (bufferData->buffers[playingBuffer].loadedFrames >= bufferData->buffers[playingBuffer].lengthFrames) {
			bufferSwap = YES;
			framesCopied = framesToCopy;
		}
	}

	if (!bufferData->isSimpleStereoDevice)
	{	 //change if more than stereo supported

		if (bufferData->isIntegerModeOn && bufferData->integerModeStreamFormat.mChannelsPerFrame == 1 && bufferData->integerModeStreamFormat.mBytesPerFrame == 4) {
			// handle mono output stream, integer mode case
			SInt32	dstOffset	  = bufferData->channelMap[0].channel;
			SInt32* dstBufferBase = (SInt32*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData + dstOffset;
			SInt32  dstStride	  = outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels;

			SInt32	dstOffset1	  = bufferData->channelMap[1].channel;
			SInt32* dstBufferBase1 = (SInt32*)outOutputData->mBuffers[bufferData->channelMap[1].stream].mData + dstOffset1;
			SInt32  dstStride1	  = outOutputData->mBuffers[bufferData->channelMap[1].stream].mNumberChannels;

			SInt64	srcOffset	  = bufferData->buffers[playingBuffer].currentPlayingFrame * bufferData->buffers[playingBuffer].bytesPerFrame/4;
			SInt32* srcBufferBase = (SInt32*)bufferData->buffers[playingBuffer].data + srcOffset;
			SInt32* srcBufferBase1 = (SInt32*)bufferData->buffers[playingBuffer].data + srcOffset + 1;
			const SInt32  srcStride	  = 2;

			for (unsigned int i=0;i<framesToCopy;i++){
				*(dstBufferBase + dstStride*i) = *(srcBufferBase+srcStride*i);
				*(dstBufferBase1 + dstStride1*i) = *(srcBufferBase1+srcStride*i);
			}
		} else if (!bufferData->isIntegerModeOn || (bufferData->integerModeStreamFormat.mBytesPerFrame == 8)) {
			for (unsigned int i=0;i<framesToCopy;i++){
				*((SInt32*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData
				  +outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels*i+bufferData->channelMap[0].channel)
				=*((SInt32*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
															*bufferData->buffers[playingBuffer].bytesPerFrame/4
															+2*i+0));
				*((SInt32*)outOutputData->mBuffers[bufferData->channelMap[1].stream].mData
				  +outOutputData->mBuffers[bufferData->channelMap[1].stream].mNumberChannels*i+bufferData->channelMap[1].channel)
				=*((SInt32*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
															*bufferData->buffers[playingBuffer].bytesPerFrame/4
															+2*i+1));
			}
		}
		else if (bufferData->integerModeStreamFormat.mBytesPerFrame == 6) {
			//Copy 24bit data as 16bit + 8 bit
			for (UInt32 i=0;i<framesToCopy;i++){
				*(UInt16*)((UInt8*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData
						   +(outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels*i
							 +bufferData->channelMap[0].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2)
				=*(UInt16*)((UInt8*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
																			 +i)*bufferData->buffers[playingBuffer].bytesPerFrame);
				*((UInt8*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData
				  +(outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels*i
					+bufferData->channelMap[0].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2 +2)
				=*((UInt8*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
																	+i)*bufferData->buffers[playingBuffer].bytesPerFrame +2);

				*(UInt16*)((UInt8*)outOutputData->mBuffers[bufferData->channelMap[1].stream].mData
						   +(outOutputData->mBuffers[bufferData->channelMap[1].stream].mNumberChannels*i
							 +bufferData->channelMap[1].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2)
				=*(UInt16*)((UInt8*)bufferData->buffers[playingBuffer].data+(2*bufferData->buffers[playingBuffer].currentPlayingFrame
																			 +2*i+1)*bufferData->buffers[playingBuffer].bytesPerFrame/2);
				*((UInt8*)outOutputData->mBuffers[bufferData->channelMap[1].stream].mData
				  +(outOutputData->mBuffers[bufferData->channelMap[1].stream].mNumberChannels*i
					+bufferData->channelMap[1].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2 +2)
				=*((UInt8*)bufferData->buffers[playingBuffer].data+(2*bufferData->buffers[playingBuffer].currentPlayingFrame
																	+2*i+1)*bufferData->buffers[playingBuffer].bytesPerFrame/2 +2);
			}
		}
		else {
			for (UInt32 i=0;i<framesToCopy;i++){
				bcopy(((UInt8*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
																		+i)*bufferData->buffers[playingBuffer].bytesPerFrame),
					  ((UInt8*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData
					   +(outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels*i
						 +bufferData->channelMap[0].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2),
					  bufferData->integerModeStreamFormat.mBitsPerChannel/8);

				bcopy(((UInt8*)bufferData->buffers[playingBuffer].data+(2*bufferData->buffers[playingBuffer].currentPlayingFrame
																		+2*i+1)*bufferData->buffers[playingBuffer].bytesPerFrame/2),
					  ((UInt8*)outOutputData->mBuffers[bufferData->channelMap[1].stream].mData
					   +(outOutputData->mBuffers[bufferData->channelMap[1].stream].mNumberChannels*i
						 +bufferData->channelMap[1].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2),
					  bufferData->integerModeStreamFormat.mBitsPerChannel/8);
			}
		}

	}
		// Simple stereo device
	else bcopy((char*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
															   *bufferData->buffers[playingBuffer].bytesPerFrame),
		  outOutputData->mBuffers[0].mData,framesToCopy * bufferData->buffers[playingBuffer].bytesPerFrame);

	/* Update displayed current time */
#ifndef __ppc__
	OSAtomicAdd64(framesToCopy, &bufferData->buffers[playingBuffer].currentPlayingFrame);
#else
	//For the sake of building for ppc, but losing some thread safety...
	bufferData->buffers[playingBuffer].currentPlayingFrame += framesToCopy;
#endif
	newCurrentSeconds = (UInt32)(bufferData->buffers[playingBuffer].currentPlayingFrame / bufferData->buffers[playingBuffer].sampleRate);
	if (newCurrentSeconds != bufferData->buffers[playingBuffer].currentPlayingTimeInSeconds) {
		bufferData->buffers[playingBuffer].currentPlayingTimeInSeconds = newCurrentSeconds;
		//Only send a call with no argument, as the arguments when calling performSelectorOnMainThread
		//Must be passed in an object, and this means creating a new NSNumber object each time here
		//Thus making a malloc that could potentially take too much time (e.g. OS performing page swap at this time)
		[bufferData->appController performSelectorOnMainThread:@selector(updateCurrentPlayingTime)
														  withObject:nil waitUntilDone:FALSE];
	}

	//Gapless playback : changing buffer
	if (bufferSwap) {
		UInt32 bufferPlayed = bufferData->playingAudioBuffer;

		playingBuffer ^= 0x1; //Gapless playback : finish output buffer fill from other input buffer
		bufferData->buffers[playingBuffer].currentPlayingFrame = 0;

		//Continue to fill buffer if no need to change sampling rate
		if (bufferData->buffers[0].sampleRate == bufferData->buffers[1].sampleRate) {
			framesToCopy = (UInt32)(outOutputData->mBuffers[bufferData->channelMap[0].stream].mDataByteSize*2
									/outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels/bufferData->buffers[playingBuffer].bytesPerFrame
									- framesCopied);
			if (framesToCopy > bufferData->buffers[playingBuffer].loadedFrames)
				framesToCopy = (UInt32)bufferData->buffers[playingBuffer].loadedFrames;

			if (bufferData->isIntegerModeOn && bufferData->integerModeStreamFormat.mChannelsPerFrame == 1 && bufferData->integerModeStreamFormat.mBytesPerFrame == 4) {
				// handle mono output stream, integer mode case
				SInt32	dstOffset	  = bufferData->channelMap[0].channel;
				SInt32* dstBufferBase = (SInt32*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData + dstOffset;
				SInt32  dstStride	  = outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels;

				SInt32	dstOffset1	  = bufferData->channelMap[1].channel;
				SInt32* dstBufferBase1 = (SInt32*)outOutputData->mBuffers[bufferData->channelMap[1].stream].mData + dstOffset1;
				SInt32  dstStride1	  = outOutputData->mBuffers[bufferData->channelMap[1].stream].mNumberChannels;

				SInt64	srcOffset	  = bufferData->buffers[playingBuffer].currentPlayingFrame * bufferData->buffers[playingBuffer].bytesPerFrame/4;
				SInt32* srcBufferBase = (SInt32*)bufferData->buffers[playingBuffer].data + srcOffset;
				SInt32* srcBufferBase1 = (SInt32*)bufferData->buffers[playingBuffer].data + srcOffset + 1;
				const SInt32  srcStride	  = 2;

				for (unsigned int i=0;i<framesToCopy;i++){
					*(dstBufferBase + dstStride*(i+framesCopied)) = *(srcBufferBase+srcStride*i);
					*(dstBufferBase1 + dstStride1*(i+framesCopied)) = *(srcBufferBase1+srcStride*i);
				}

			} else if (!bufferData->isIntegerModeOn || (bufferData->integerModeStreamFormat.mBytesPerFrame == 8)) {
				for (UInt32 i=0;i<framesToCopy;i++){
					*((SInt32*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData
					  +outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels*(i+framesCopied)+bufferData->channelMap[0].channel)
					=*((SInt32*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
																*bufferData->buffers[playingBuffer].bytesPerFrame/4
																+2*i+0));
					*((SInt32*)outOutputData->mBuffers[bufferData->channelMap[1].stream].mData
					  +outOutputData->mBuffers[bufferData->channelMap[1].stream].mNumberChannels*(i+framesCopied)+bufferData->channelMap[1].channel)
					=*((SInt32*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
																*bufferData->buffers[playingBuffer].bytesPerFrame/4
																+2*i+1));
				}
			}
			else if (bufferData->integerModeStreamFormat.mBytesPerFrame == 6) {
				//Copy 24bit data as 16bit + 8 bit
				for (UInt32 i=0;i<framesToCopy;i++){
					*(UInt16*)((UInt8*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData
							  +(outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels*(i+framesCopied)
								+bufferData->channelMap[0].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2)
					=*(UInt16*)((UInt8*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
																+i)*bufferData->buffers[playingBuffer].bytesPerFrame);
					*((UInt8*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData
							   +(outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels*(i+framesCopied)
								 +bufferData->channelMap[0].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2 +2)
					=*((UInt8*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
																				 +i)*bufferData->buffers[playingBuffer].bytesPerFrame +2);


					*(UInt16*)((UInt8*)outOutputData->mBuffers[bufferData->channelMap[1].stream].mData
					  +(outOutputData->mBuffers[bufferData->channelMap[1].stream].mNumberChannels*(i+framesCopied)
						+bufferData->channelMap[1].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2)
					=*(UInt16*)((UInt8*)bufferData->buffers[playingBuffer].data+(2*bufferData->buffers[playingBuffer].currentPlayingFrame
																+2*i+1)*bufferData->buffers[playingBuffer].bytesPerFrame/2);
					*((UInt8*)outOutputData->mBuffers[bufferData->channelMap[1].stream].mData
					  +(outOutputData->mBuffers[bufferData->channelMap[1].stream].mNumberChannels*(i+framesCopied)
						+bufferData->channelMap[1].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2 +2)
					=*((UInt8*)bufferData->buffers[playingBuffer].data+(2*bufferData->buffers[playingBuffer].currentPlayingFrame
																				 +2*i+1)*bufferData->buffers[playingBuffer].bytesPerFrame/2 +2);
				}
			}
			else {
				for (UInt32 i=0;i<framesToCopy;i++){
					bcopy(((UInt8*)bufferData->buffers[playingBuffer].data+(bufferData->buffers[playingBuffer].currentPlayingFrame
																			+i)*bufferData->buffers[playingBuffer].bytesPerFrame),
						  ((UInt8*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData
						   +(outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels*(i+framesCopied)
							 +bufferData->channelMap[0].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2),
						  bufferData->integerModeStreamFormat.mBitsPerChannel/8);

					bcopy(((UInt8*)bufferData->buffers[playingBuffer].data+(2*bufferData->buffers[playingBuffer].currentPlayingFrame
																			+2*i+1)*bufferData->buffers[playingBuffer].bytesPerFrame/2),
						  ((UInt8*)outOutputData->mBuffers[bufferData->channelMap[0].stream].mData
						   +(outOutputData->mBuffers[bufferData->channelMap[0].stream].mNumberChannels*(i+framesCopied)
							 +bufferData->channelMap[1].channel)*bufferData->buffers[playingBuffer].bytesPerFrame/2),
						  bufferData->integerModeStreamFormat.mBitsPerChannel/8);
				}
			}

			OSAtomicAdd64(framesToCopy, &bufferData->buffers[playingBuffer].currentPlayingFrame);

		} //Otherwise request to change sampling rate
		else bufferData->isIOPaused |= kAudioIOProcSampleRateChanging;

		if ((bufferData->isIOPaused & kAudioIOProcPause) == 0) {
			//Prevent race condition with other playlist change event (e.g. user asked to change playing track)
			//Done by using the flag willChangePlayingBuffer that will be checked by the notifyBufferPlayed method
			//In addition, such change will happen only in pause mode (time to reload track), and this code
			//is not reached in normal (non seeking) pause mode
			//The flag willChangePlayingBuffer is reset upon other playlist playing track change
			bufferData->willChangePlayingBuffer = YES;
			bufferData->playingAudioBuffer = playingBuffer;
			//Notify buffer swapped
			dispatch_async(dispatch_get_main_queue(), ^{[bufferData->appController notifyBufferPlayed:bufferPlayed];});
		}
	}

	return kAudioHardwareNoError;
}

#pragma mark Audio HAL listener functions

OSStatus HALlistenerProc(AudioObjectID inObjectID,
						 UInt32 inNumberAddresses,
						 const AudioObjectPropertyAddress    inAddresses[],
						 void* inClientData)
{
	UInt32 addressIndex;
	AudioObjectPropertyAddress propertyAddress;
	UInt32 propSize;
	UInt32 tmpInt;
	OSStatus err = noErr;
	AudioOutputBufferData *bufferData = (AudioOutputBufferData *)inClientData;

	if (inObjectID == bufferData->selectedAudioDeviceID) {
		for (addressIndex=0; addressIndex<inNumberAddresses; addressIndex++) {
			switch (inAddresses[addressIndex].mSelector) {
				case kAudioDevicePropertyNominalSampleRate: {
						//Tell the I/O proc the sampling rate change is completed and playback can be resumed
                    [bufferData->audioOut performSelectorOnMainThread:@selector(samplerateSwitchIsComplete) withObject:nil waitUntilDone:NO];
                }
					break;
				case kAudioDeviceProcessorOverload:
					//Notify user of this CPU load issue
					[bufferData->appController performSelectorOnMainThread:@selector(notifyProcessorOverload) withObject:nil waitUntilDone:NO];
					break;
				case kAudioDevicePropertyDeviceIsAlive:
					//Check if device is still alive, if not, then stop playback
					propSize=sizeof(UInt32);
					propertyAddress.mSelector = kAudioDevicePropertyDeviceIsAlive;
					propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
					propertyAddress.mElement = kAudioObjectPropertyElementMaster;
					err = AudioObjectGetPropertyData(inObjectID, &propertyAddress, 0, NULL, &propSize, &tmpInt);

					if ((err == kAudioHardwareNoError) && (tmpInt == NO))
						[bufferData->appController performSelectorOnMainThread:@selector(notifyDeviceRemoved) withObject:nil waitUntilDone:NO];
					break;
                case kAudioDevicePropertyMute:
				case kAudioDevicePropertyVolumeScalar:
				case kAudioHardwareServiceDeviceProperty_VirtualMasterVolume:
					[bufferData->appController performSelectorOnMainThread:@selector(notifyDeviceVolumeChanged) withObject:nil waitUntilDone:NO];
					break;
                case kAudioDevicePropertyDataSource: //Build-in output volume selections are different for datasources (e.g. speakers, headphones)
					[bufferData->appController performSelectorOnMainThread:@selector(notifyDeviceDataSourceChanged) withObject:nil waitUntilDone:NO];
       			break;
				case kAudioDevicePropertyBufferFrameSize:
					//Tell the I/O proc the buffer size change is completed and playback can be resumed
					bufferData->isIOPaused &= ~kAudioIOProcAudioBufferSizeChanging;
					break;
				case kAudioDevicePropertyHogMode:
					propSize=sizeof(UInt32);
					propertyAddress.mSelector=kAudioDevicePropertyHogMode;
					propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
					propertyAddress.mElement = kAudioObjectPropertyElementMaster;
					err = AudioObjectGetPropertyData(inObjectID, &propertyAddress, 0, NULL, &propSize, &tmpInt);

					//Advance to next startup phase if device has switched in to Hog Mode
					if ((err == kAudioHardwareNoError)
						&& (bufferData->playbackStartPhase == kAudioPlaybackStartHoggingDevice)
						&& ((pid_t)tmpInt == getpid())) {
						bufferData->playbackStartPhase = kAudioPlaybackStartDeviceHogged;
						bufferData->isHoggingDevice = YES;
						[bufferData->audioOut performSelectorOnMainThread:@selector(initiatePlaybackAfterHoggingDevice) withObject:nil waitUntilDone:NO];
					}
					break;

				default:
					break;
			}
		}
	} else if (inObjectID == kAudioObjectSystemObject) {
		for (addressIndex=0; addressIndex<inNumberAddresses; addressIndex++) {
			switch (inAddresses[addressIndex].mSelector) {
				case kAudioHardwarePropertyDevices:
					//Notify audio devices list has changed
					[bufferData->appController performSelectorOnMainThread:@selector(notifyDevicesListUpdated) withObject:nil waitUntilDone:NO];
					break;
				default:
					break;
			}
		}
	} else if (inObjectID == bufferData->channelMap[0].streamID) { //Both channels will change at same time, so need to listen only to channel 1
		for (addressIndex=0; addressIndex<inNumberAddresses; addressIndex++) {
			switch (inAddresses[addressIndex].mSelector) {
				case kAudioStreamPropertyVirtualFormat: {
					//Audio stream virtual format changed
					propSize=sizeof(AudioStreamBasicDescription);
					propertyAddress.mSelector = kAudioStreamPropertyVirtualFormat;
					propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
					propertyAddress.mElement = kAudioObjectPropertyElementMaster;
					err = AudioObjectGetPropertyData(inObjectID, &propertyAddress, 0, NULL, &propSize, &bufferData->integerModeStreamFormat);

					//Advance to next startup phase is device has switched into Integer Mode
					if ((err == kAudioHardwareNoError)
						&& (bufferData->playbackStartPhase == kAudioPlaybackStartChangingStreamFormat)
						&& (bufferData->integerModeStreamFormat.mFormatID == bufferData->integerModeStreamFormatToBe.mFormatID)
						&& (bufferData->integerModeStreamFormat.mFormatFlags == bufferData->integerModeStreamFormatToBe.mFormatFlags)
						&& (bufferData->integerModeStreamFormat.mChannelsPerFrame == bufferData->integerModeStreamFormatToBe.mChannelsPerFrame)
                        && (bufferData->integerModeStreamFormat.mBitsPerChannel == bufferData->integerModeStreamFormatToBe.mBitsPerChannel)
                        && (bufferData->integerModeStreamFormat.mBytesPerFrame == bufferData->integerModeStreamFormatToBe.mBytesPerFrame)) {
							bufferData->playbackStartPhase = kAudioPlaybackStartFinishingDeviceInitialization;
							[bufferData->audioOut performSelectorOnMainThread:@selector(initiatePlaybackCompletingInit) withObject:nil waitUntilDone:NO];
					}
					else if (bufferData->playbackStartPhase == kAudioPlaybackSwitchingBackToFloatMode) {
						bufferData->playbackStartPhase = kAudioPlaybackNotInStartingPhase;
						[bufferData->audioOut performSelectorOnMainThread:@selector(completeDeviceStop) withObject:nil waitUntilDone:NO];
					}
				}
					break;
				default:
					break;
			}
		}
	}
	return err;
}



#pragma mark -
#pragma mark AudioOutput implementation

@implementation AudioOutput
@synthesize audioDevicesList,selectedAudioDeviceIndex;
@synthesize isPlaying,audioDeviceCurrentNominalSampleRate;
@synthesize audioDeviceCurrentPhysicalBitDepth;

- (id)initWithController:(AppController*)controller {
	AudioObjectPropertyAddress propertyAddress;
	UInt32 isSleepingAllowed;

	isPlaying = false;
	mBufferData.appController = controller;
	mBufferData.audioOut = self;
	mBufferData.playingAudioBuffer = -1;
	mBufferData.selectedAudioDeviceID = 0;
	mBufferData.isSimpleStereoDevice = NO;
	mBufferData.isHoggingDevice = NO;
	mBufferData.playbackStartPhase = kAudioPlaybackNotInStartingPhase;
	selectedAudioDeviceIndex = -1;

	audioDevicesList = [[NSMutableArray alloc] init];
	[self rebuildDevicesList];

	//device connect/disconnect listener
	propertyAddress.mSelector = kAudioHardwarePropertyDevices;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(kAudioObjectSystemObject, &propertyAddress, &HALlistenerProc, &mBufferData);

	//Prevent CPU idle call (avoiding sleep) when audio I/O is in progress
	propertyAddress.mSelector = kAudioHardwarePropertySleepingIsAllowed;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	isSleepingAllowed = 0;
	AudioObjectSetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, sizeof(propertyAddress), &isSleepingAllowed);

    //Use the application main run loop for processing HAL events
	propertyAddress.mSelector = kAudioHardwarePropertyRunLoop;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
    CFRunLoopRef theRunLoop = CFRunLoopGetCurrent();
    AudioObjectSetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, sizeof(CFRunLoopRef), &theRunLoop);


	//Init buffers
	mBufferData.isIOPaused = 0;
	mBufferData.playingAudioBuffer = -1;
	mBufferData.isIntegerModeOn = FALSE;
	for (int i=0;i<2;i++) {
		mBufferData.buffers[i].inputFileLoader = nil;
		mBufferData.buffers[i].lengthFrames = 0;
		mBufferData.buffers[i].loadedFrames = 0;
		mBufferData.buffers[i].data = NULL;
	}

	return [super init];
}

- (void)dealloc
{
	AudioObjectPropertyAddress propertyAddress;

	if (isPlaying) [self stop];
	[self closeBuffers];

	if (mBufferData.selectedAudioDeviceID) {
		//Remove previous listeners
		propertyAddress.mSelector=kAudioDevicePropertyNominalSampleRate;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDeviceProcessorOverload;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyDeviceIsAlive;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyHogMode;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyVolumeScalar;
		propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyMute;
		propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
		propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyDataSource;
		propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyBufferFrameSize;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioStreamPropertyVirtualFormat;
		propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.channelMap[0].streamID, &propertyAddress, &HALlistenerProc, &mBufferData);

	}

	[[NSNotificationCenter defaultCenter] removeObserver:self];

	if (audioDevicesList) [audioDevicesList release];

	[super dealloc];
}

- (void)rebuildDevicesList {
	AudioObjectPropertyAddress propertyAddress;
	OSStatus result = noErr;
	UInt32 propertySize,numStreams;
    AudioDeviceID *systemAudioDevicesList = NULL;
    UInt32 theNumDevices = 0;
	OSErr err;

	//Empty description array
	[audioDevicesList removeAllObjects];

	// get the device list
	propertyAddress.mSelector = kAudioHardwarePropertyDevices;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;

	result = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &propertySize);
	if (result) printf("Error in AudioObjectGetPropertyDataSize: %d\n", (int)result);
	else {

		// Find out how many devices are on the system
		theNumDevices = propertySize / (UInt32)sizeof(AudioDeviceID);
		systemAudioDevicesList = (AudioDeviceID*)calloc(theNumDevices, sizeof(AudioDeviceID));

		result = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &propertySize, systemAudioDevicesList);
		if (result) { printf("Error in AudioObjectGetPropertyData: %d\n", (int)result);}
		else {
			CFStringRef audioDeviceName, audioDeviceUID;
			UInt32 outSize;
			UInt32 startingChannel;
			UInt32 preferredStereoChannels[2];
			AudioValueRange *availSampleRates;
			AudioStreamID *audioStreams;
			AudioDeviceDescription *deviceDesc;
			AudioStreamDescription *streamDesc;

			for (UInt32 deviceIndex=0; deviceIndex < theNumDevices; deviceIndex++)
			{
				//Check if device is of output kind
				propertyAddress.mSelector = kAudioDevicePropertyStreamConfiguration;
				propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
				propertyAddress.mElement = kAudioObjectPropertyElementMaster;
				AudioObjectGetPropertyDataSize(systemAudioDevicesList[deviceIndex], &propertyAddress, 0, NULL, &outSize);

				if (outSize > 0) {
					AudioBufferList *theBufferList = NULL;
					theBufferList = (AudioBufferList*)malloc(outSize);
					if(theBufferList != NULL)
					{
						UInt32      theNumberOutputChannels = 0;

						// get the input stream configuration
						err = AudioObjectGetPropertyData(systemAudioDevicesList[deviceIndex], &propertyAddress, 0, NULL, &outSize, theBufferList);

						if(err == noErr)
						{
							// count the total number of output channels in the stream
							for(UInt32 theIndex = 0; theIndex < theBufferList->mNumberBuffers; ++theIndex)
								theNumberOutputChannels += theBufferList->mBuffers[theIndex].mNumberChannels;
						}


						if (theNumberOutputChannels > 0) {
							//Init array element
							deviceDesc = [[AudioDeviceDescription alloc] init];
							deviceDesc.audioDevID = systemAudioDevicesList[deviceIndex];

							//Set the selected device index to the new value
							if (systemAudioDevicesList[deviceIndex] == mBufferData.selectedAudioDeviceID) {
								selectedAudioDeviceIndex = (SInt32)[audioDevicesList count];
							}

							// get the device name
							propertySize = sizeof(CFStringRef);
							propertyAddress.mSelector = kAudioObjectPropertyName;
							propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
							propertyAddress.mElement = kAudioObjectPropertyElementMaster;

							result = AudioObjectGetPropertyData(systemAudioDevicesList[deviceIndex], &propertyAddress, 0, NULL, &propertySize, &audioDeviceName);
							if (result) printf("Error in AudioObjectGetPropertyData getting device name: %d\n", (int)result);
							else
								[deviceDesc setName:(NSString*)audioDeviceName];

							// get the device UID
							propertySize = sizeof(CFStringRef);
							propertyAddress.mSelector = kAudioDevicePropertyDeviceUID;
							propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
							propertyAddress.mElement = kAudioObjectPropertyElementMaster;

							result = AudioObjectGetPropertyData(systemAudioDevicesList[deviceIndex], &propertyAddress, 0, NULL, &propertySize, &audioDeviceUID);
							if (result) {
								printf("Error in AudioObjectGetPropertyData getting device UID string: %d\n", (int)result);
								[deviceDesc release];
								continue;
							}
							else
								[deviceDesc setUID:(NSString*)audioDeviceUID];



							//Get the avail sample rates
							propertyAddress.mSelector=kAudioDevicePropertyAvailableNominalSampleRates;
							propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
							propertyAddress.mElement=kAudioObjectPropertyElementMaster;
							AudioObjectGetPropertyDataSize(systemAudioDevicesList[deviceIndex], &propertyAddress, 0, NULL, &propertySize);

							availSampleRates = (AudioValueRange*)malloc(propertySize);
							AudioObjectGetPropertyData(systemAudioDevicesList[deviceIndex], &propertyAddress, 0, NULL, &propertySize, availSampleRates);
							[deviceDesc setSampleRates:availSampleRates
												 count:(UInt32)propertySize/(UInt32)sizeof(AudioValueRange)];

							//Get audio I/O buffer size range
							[self loadDeviceBufferFrameSizeRange:deviceDesc];

							//Get physical volume capability
							deviceDesc.availableVolumeControls = 0;

							propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
							propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
							propertyAddress.mElement = kAudioObjectPropertyElementMaster;
							if (AudioObjectHasProperty(systemAudioDevicesList[deviceIndex], &propertyAddress))
								deviceDesc.availableVolumeControls |= kAudioVolumePhysicalControl;

							//Get virtual volume capability
							propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
							propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
							propertyAddress.mElement = kAudioObjectPropertyElementMaster;
							if (AudioObjectHasProperty(systemAudioDevicesList[deviceIndex], &propertyAddress)) {
								//Perform second check as some drivers anwser yes, while not handling the property
								Float32 deviceVolume;

								propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
								propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
								propertyAddress.mElement = kAudioObjectPropertyElementMaster;
								propertySize = sizeof(Float32);
								if (AudioObjectGetPropertyData(systemAudioDevicesList[deviceIndex],
															   &propertyAddress, 0, NULL,
															   &propertySize, &deviceVolume) == noErr)
									deviceDesc.availableVolumeControls |= kAudioVolumeVirtualControl;
							}

							//Get stereo preferred channels
							propertyAddress.mSelector = kAudioDevicePropertyPreferredChannelsForStereo;
							propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
							propertyAddress.mElement = kAudioObjectPropertyElementMaster;
							propertySize = 2*sizeof(UInt32);
							AudioObjectGetPropertyData(systemAudioDevicesList[deviceIndex],
													   &propertyAddress, 0, NULL,
													   &propertySize, &preferredStereoChannels);
							[deviceDesc setPreferredChannelsStereo:preferredStereoChannels[0]
															 right:preferredStereoChannels[1] ];

							//Get number of output streams
							propertyAddress.mSelector=kAudioDevicePropertyStreams;
							propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
							propertyAddress.mElement=kAudioObjectPropertyElementMaster;
							AudioObjectGetPropertyDataSize(systemAudioDevicesList[deviceIndex], &propertyAddress, 0, NULL, &propertySize);

							if(propertySize>0) {
								numStreams = propertySize/(UInt32)sizeof(AudioStreamID);
								audioStreams = (AudioStreamID*)malloc(propertySize);
								AudioObjectGetPropertyData(systemAudioDevicesList[deviceIndex], &propertyAddress, 0, NULL, &propertySize, audioStreams);

								//Fill audioStreams info structures
								deviceDesc.streams = [[NSMutableArray alloc] init];
								for (UInt32 strIndex=0; strIndex<numStreams; strIndex++) {
									streamDesc = [[AudioStreamDescription alloc] init];

									streamDesc.streamID = audioStreams[strIndex];

									//Get available physical formats
									[self loadStreamPhysicalFormat:streamDesc];

									//Get available virtual formats
									[self loadStreamVirtualFormat:streamDesc];

									//Get channels info
									streamDesc.numChannels = theBufferList->mBuffers[strIndex].mNumberChannels;
									propertyAddress.mSelector=kAudioStreamPropertyStartingChannel;
									propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
									propertyAddress.mElement=kAudioObjectPropertyElementMaster;
									propertySize=sizeof(UInt32);
									AudioObjectGetPropertyData(audioStreams[strIndex], &propertyAddress, 0, NULL, &propertySize, &startingChannel);
									[streamDesc setStartingChannel:startingChannel];

									[deviceDesc.streams addObject:streamDesc];
									[streamDesc release];
								}
								free(audioStreams);
							}

							// add in list
							[audioDevicesList addObject:deviceDesc];
							[deviceDesc release];
						}
					}
					free(theBufferList);
				}
			}
		}
		free(systemAudioDevicesList);
	}
}

- (void)loadDeviceBufferFrameSizeRange:(AudioDeviceDescription*)deviceDesc
{
	AudioValueRange ioBufferFrameSizeRange;
	AudioObjectPropertyAddress propertyAddress;
	UInt32 propertySize;

	propertyAddress.mSelector = kAudioDevicePropertyBufferFrameSizeRange;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	propertySize = sizeof(AudioValueRange);
	AudioObjectGetPropertyData([deviceDesc audioDevID], &propertyAddress, 0, NULL, &propertySize, &ioBufferFrameSizeRange);
	[deviceDesc setBufferFrameSizeRange:ioBufferFrameSizeRange.mMinimum maxFrameSize:ioBufferFrameSizeRange.mMaximum];
}

- (void)loadStreamPhysicalFormat:(AudioStreamDescription*)audioStream
{
	AudioObjectPropertyAddress propertyAddress;
	AudioStreamRangedDescription *audioStreamPhysicalFormats;
	UInt32 propertySize;

	propertyAddress.mSelector=kAudioStreamPropertyAvailablePhysicalFormats;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectGetPropertyDataSize([audioStream streamID], &propertyAddress, 0, NULL, &propertySize);

	audioStreamPhysicalFormats = (AudioStreamRangedDescription*)malloc(propertySize);
	AudioObjectGetPropertyData([audioStream streamID], &propertyAddress, 0, NULL, &propertySize, audioStreamPhysicalFormats);
	[audioStream setPhysicalFormats:audioStreamPhysicalFormats
							 count:propertySize/(UInt32)sizeof(AudioStreamRangedDescription)];

}

- (void)loadStreamVirtualFormat:(AudioStreamDescription*)audioStream
{
	AudioObjectPropertyAddress propertyAddress;
	AudioStreamRangedDescription *audioStreamVirtualFormats;
	UInt32 propertySize;

	propertyAddress.mSelector=kAudioStreamPropertyAvailableVirtualFormats;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectGetPropertyDataSize([audioStream streamID], &propertyAddress, 0, NULL, &propertySize);

	audioStreamVirtualFormats = (AudioStreamRangedDescription*)malloc(propertySize);
	AudioObjectGetPropertyData([audioStream streamID], &propertyAddress, 0, NULL, &propertySize, audioStreamVirtualFormats);
	[audioStream setVirtualFormats:audioStreamVirtualFormats
							count:propertySize/(UInt32)sizeof(AudioStreamRangedDescription)];
}

- (void)handleDeviceChange:(NSNotification*)notification
{
	[self selectDevice:[[NSUserDefaults standardUserDefaults] stringForKey:AUDPreferredAudioDeviceUID]];
}

- (void)selectDevice:(NSString*)deviceUID
{
	AudioObjectPropertyAddress propertyAddress;
	AudioDeviceDescription *audioDevDesc;
	AudioStreamBasicDescription audioFormat;
	UInt32 propertySize;
	int newIndex;

	bool wasPlaying = isPlaying;

	if (wasPlaying) {
		[mBufferData.appController stop:nil];
    }

	NSEnumerator *enumerator = [audioDevicesList objectEnumerator];

	newIndex = 0; //Default to standard output if unable to find new preferred device

	while ((audioDevDesc = [enumerator nextObject]) != nil) {
		if ([[audioDevDesc UID] compare:deviceUID] == NSOrderedSame) {
			newIndex = (UInt32)[audioDevicesList indexOfObject:audioDevDesc];
			break;
		}
	}

	if (mBufferData.selectedAudioDeviceID) {
		//Remove previous listeners
		propertyAddress.mSelector=kAudioDevicePropertyNominalSampleRate;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDeviceProcessorOverload;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyDeviceIsAlive;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyHogMode;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyVolumeScalar;
		propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyMute;
		propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
		propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyDataSource;
		propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioDevicePropertyBufferFrameSize;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

		propertyAddress.mSelector=kAudioStreamPropertyVirtualFormat;
		propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement=kAudioObjectPropertyElementMaster;
		AudioObjectRemovePropertyListener(mBufferData.channelMap[0].streamID, &propertyAddress, &HALlistenerProc, &mBufferData);
	}

	selectedAudioDeviceIndex = newIndex;
	mBufferData.selectedAudioDeviceID = [[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] audioDevID];

	//Get the channels map
	[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] getChannelMapping:&mBufferData.channelMap[0]
																	  forChannel:[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] getPreferredChannel:0]];
	[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] getChannelMapping:&mBufferData.channelMap[1]
																	  forChannel:[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] getPreferredChannel:1]];

	//Check in memcopy optimization is possible for simple stereo interleaved devices
	if ((mBufferData.channelMap[0].stream == 0) && (mBufferData.channelMap[1].stream == 0)
		&& ([[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream] numChannels] == 2)
		&& (mBufferData.channelMap[0].channel == 0) && (mBufferData.channelMap[1].channel == 1))
		mBufferData.isSimpleStereoDevice = YES;
	else
		mBufferData.isSimpleStereoDevice = NO;


	//Get the current nominal sample rate
	propertySize=sizeof(Float64);
	propertyAddress.mSelector=kAudioDevicePropertyNominalSampleRate;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectGetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, &propertySize, &audioDeviceCurrentNominalSampleRate);

	//Get the current physical format bit depth
	propertySize=sizeof(AudioStreamBasicDescription);
	propertyAddress.mSelector = kAudioStreamPropertyPhysicalFormat;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = 0;
	AudioObjectGetPropertyData([[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream] streamID],
							   &propertyAddress, 0, NULL, &propertySize, &audioFormat);
	audioDeviceCurrentPhysicalBitDepth = audioFormat.mBitsPerChannel;


	//Add property listeners
	propertyAddress.mSelector=kAudioDevicePropertyNominalSampleRate;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

	propertyAddress.mSelector=kAudioDeviceProcessorOverload;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

	propertyAddress.mSelector=kAudioDevicePropertyDeviceIsAlive;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

	propertyAddress.mSelector=kAudioDevicePropertyHogMode;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

	propertyAddress.mSelector=kAudioDevicePropertyVolumeScalar;
	propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

	propertyAddress.mSelector=kAudioDevicePropertyMute;
	propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

	propertyAddress.mSelector=kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
	propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

	propertyAddress.mSelector=kAudioDevicePropertyDataSource;
	propertyAddress.mScope=kAudioDevicePropertyScopeOutput;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

	propertyAddress.mSelector=kAudioDevicePropertyBufferFrameSize;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.selectedAudioDeviceID, &propertyAddress, &HALlistenerProc, &mBufferData);

	propertyAddress.mSelector=kAudioStreamPropertyVirtualFormat;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectAddPropertyListener(mBufferData.channelMap[0].streamID, &propertyAddress, &HALlistenerProc, &mBufferData);

	//Notify UI of device change
	//Currently used for volume control slider
	[mBufferData.appController setVolumeControl:[self availableVolumeControls]];

	/*if (wasPlaying) {
		if ([self initiatePlayback:NULL])
			[self startPlayback:NULL];
	}*/
}

- (BOOL)getIntegerModeFormat:(AudioStreamBasicDescription*)streamFormat forSampleRate:(Float64)splRateToBe
{
    //First check for stereo channels
    if (mBufferData.channelMap[0].stream == mBufferData.channelMap[1].stream)
        return [[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream]
                getIntegerModeFormat:streamFormat forSampleRate:splRateToBe forMinChannels:2];
    //Handle case of 1 channel multi streams devices
    else
        return [[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream]
                getIntegerModeFormat:streamFormat forSampleRate:splRateToBe forMinChannels:1];
}

- (BOOL)getPhysicalMixableFormat:(AudioStreamBasicDescription*)streamFormat forSampleRate:(Float64)splRateToBe
{
    //First check for stereo channels
    if (mBufferData.channelMap[0].stream == mBufferData.channelMap[1].stream)
        return [[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream]
                getPhysicalMixableFormat:streamFormat forSampleRate:splRateToBe forMinChannels:2];
    //Handle case of 1 channel multi streams devices
    else
        return [[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream]
                getPhysicalMixableFormat:streamFormat forSampleRate:splRateToBe forMinChannels:1];
}

#pragma mark -
#pragma mark Playback buffers control functions

- (bool)loadFile:(NSURL *)fileURL toBuffer:(int)bufferToFill
{
	//Read file to fill buffer
	mBufferData.buffers[bufferToFill].inputFileLoader = [[AudioFileLoader createWithURL:fileURL] retain];

	if (mBufferData.buffers[bufferToFill].inputFileLoader == nil) {
		return FALSE;
	}

	[mBufferData.buffers[bufferToFill].inputFileLoader enableBackgroundReporting:mBufferData.appController];

	//Integer Mode
	if (mBufferData.isIntegerModeOn)
		[mBufferData.buffers[bufferToFill].inputFileLoader setIntegerMode:YES
															 streamFormat:&mBufferData.buffersStreamFormat];
	//Sample rate handling
	mBufferData.buffers[bufferToFill].sampleRate = [mBufferData.buffers[bufferToFill].inputFileLoader nativeSampleRate];

	if (![[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] isSampleRateHandled:mBufferData.buffers[bufferToFill].sampleRate
                                                                              withLimit:YES]
        || (mBufferData.isIntegerModeOn
            && ![[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream]
                isSampleRateHandled:mBufferData.buffers[bufferToFill].sampleRate withSameStreamFormat:&mBufferData.integerModeStreamFormat])) {
		//Need to convert the file sample rate ?
                mBufferData.buffers[bufferToFill].sampleRate = [[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams]
                                                                 objectAtIndex:mBufferData.channelMap[0].stream]
                                                                maxSampleRateforFormat:&mBufferData.integerModeStreamFormat];
		[mBufferData.buffers[bufferToFill].inputFileLoader setSampleRateConversion:mBufferData.buffers[bufferToFill].sampleRate];
	} else if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDForceUpsamlingType] == kAUDSRCForcedOversamplingOnly) {
		//Forced upsampling
		//4x or 2x oversampling only
		if ([[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] isSampleRateHandled:4*mBufferData.buffers[bufferToFill].sampleRate
                                                                                 withLimit:YES]
            && (!mBufferData.isIntegerModeOn
                || [[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream]
                    isSampleRateHandled:4*mBufferData.buffers[bufferToFill].sampleRate withSameStreamFormat:&mBufferData.integerModeStreamFormat])) {
			mBufferData.buffers[bufferToFill].sampleRate = 4*mBufferData.buffers[bufferToFill].sampleRate;
			[mBufferData.buffers[bufferToFill].inputFileLoader setSampleRateConversion:mBufferData.buffers[bufferToFill].sampleRate];
		} else if ([[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] isSampleRateHandled:2*mBufferData.buffers[bufferToFill].sampleRate
                                                                                        withLimit:YES]
                   && (!mBufferData.isIntegerModeOn
                       || [[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream]
                           isSampleRateHandled:2*mBufferData.buffers[bufferToFill].sampleRate withSameStreamFormat:&mBufferData.integerModeStreamFormat])){
			mBufferData.buffers[bufferToFill].sampleRate = 2*mBufferData.buffers[bufferToFill].sampleRate;
			[mBufferData.buffers[bufferToFill].inputFileLoader setSampleRateConversion:mBufferData.buffers[bufferToFill].sampleRate];
		}
	} else if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDForceUpsamlingType] == kAUDSRCForcedMaxUpsampling) {
		//Forced upsampling to max device samplerate
		mBufferData.buffers[bufferToFill].sampleRate = [[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams]
                                                         objectAtIndex:mBufferData.channelMap[0].stream]
                                                        maxSampleRateforFormat:&mBufferData.integerModeStreamFormat];
		[mBufferData.buffers[bufferToFill].inputFileLoader setSampleRateConversion:mBufferData.buffers[bufferToFill].sampleRate];
	}

	mBufferData.buffers[bufferToFill].firstFrameOffset = 0;

	mBufferData.bufferIndexForNextChunkToLoad = -1;
	[mBufferData.appController resetLoadStatus:NO];

	if ([mBufferData.buffers[bufferToFill].inputFileLoader loadInitialBuffer:&mBufferData.buffers[bufferToFill].data
															AllocatedBufSize:&mBufferData.buffers[bufferToFill].dataSizeInBytes
															MaxBufferSize:[[NSUserDefaults standardUserDefaults] integerForKey:AUDMaxAudioBufferSize]*1024*1024
															  NumTotalFrames:&mBufferData.buffers[bufferToFill].lengthFrames
															NumLoadedFrames:&mBufferData.buffers[bufferToFill].loadedFrames
																   Status:&mBufferData.buffers[bufferToFill].inputFileLoadStatus
														NextInputPosition:&mBufferData.buffers[bufferToFill].inputFileNextPosition
																   ForBuffer:bufferToFill] != 0) {
		[mBufferData.buffers[bufferToFill].inputFileLoader release];
		mBufferData.buffers[bufferToFill].inputFileLoader = nil;
		return FALSE;
	}

    mBufferData.buffers[bufferToFill].bytesPerFrame = mBufferData.buffersStreamFormat.mBytesPerFrame;

	mBufferData.buffers[bufferToFill].currentPlayingFrame = 0;

	return TRUE;
}

- (bool)loadNextChunk:(int)bufferToFill
{
	int previousBuffer = (bufferToFill == 0)?1:0;

	//First check if any data still needs to be loaded from the same file
	if (((mBufferData.buffers[previousBuffer].inputFileLoadStatus & kAudioFileLoaderStatusEOF)
		== kAudioFileLoaderStatusEOF)
		|| (mBufferData.buffers[previousBuffer].inputFileLoader == NULL))
		return FALSE;

	return [self loadNextChunk:bufferToFill at:mBufferData.buffers[previousBuffer].inputFileNextPosition];
}

- (bool)loadNextChunk:(int)bufferToFill at:(SInt64)startingPosition
{
	int previousBuffer = (bufferToFill == 0)?1:0;

	//Replicate loader data
	mBufferData.buffers[bufferToFill].inputFileLoader = mBufferData.buffers[previousBuffer].inputFileLoader;
	[mBufferData.buffers[bufferToFill].inputFileLoader retain];

	mBufferData.buffers[bufferToFill].sampleRate = mBufferData.buffers[previousBuffer].sampleRate;
	mBufferData.buffers[bufferToFill].bytesPerFrame = mBufferData.buffers[previousBuffer].bytesPerFrame;
	mBufferData.buffers[bufferToFill].loadedFrames = 0;
	mBufferData.buffers[bufferToFill].lengthFrames = 0;

	//Check if previous chunk is still loading => queue this chunk load
	if ((mBufferData.buffers[previousBuffer].inputFileLoadStatus & kAudioFileLoaderStatusLoading)
		== kAudioFileLoaderStatusLoading) {
			mBufferData.bufferIndexForNextChunkToLoad = bufferToFill;
	}
	else {
		mBufferData.bufferIndexForNextChunkToLoad = -1;
		mBufferData.buffers[bufferToFill].firstFrameOffset = startingPosition;

		if ([mBufferData.buffers[bufferToFill].inputFileLoader loadChunk:startingPosition
														   OutBufferData:&mBufferData.buffers[bufferToFill].data
														AllocatedBufSize:&mBufferData.buffers[bufferToFill].dataSizeInBytes
														   MaxBufferSize:[[NSUserDefaults standardUserDefaults] integerForKey:AUDMaxAudioBufferSize]*1024*1024
														  NumTotalFrames:&mBufferData.buffers[bufferToFill].lengthFrames
														 NumLoadedFrames:&mBufferData.buffers[bufferToFill].loadedFrames
																  Status:&mBufferData.buffers[bufferToFill].inputFileLoadStatus
													   NextInputPosition:&mBufferData.buffers[bufferToFill].inputFileNextPosition
															   ForBuffer:bufferToFill] != 0) {
			[mBufferData.buffers[bufferToFill].inputFileLoader release];
			mBufferData.buffers[bufferToFill].inputFileLoader = nil;
			return FALSE;
		}
	}

	mBufferData.buffers[bufferToFill].currentPlayingFrame = 0;

	return TRUE;
}

-(bool)closeBuffers
{
	//Ensure both buffers are cleared
	bool result = [self closeBuffer:0];

	if ([self closeBuffer:1])
		return result;
	else
		return false;
}

- (bool)closeBuffer:(int)bufferToClose
{
	bool result = false;

    mBufferData.buffers[bufferToClose].lengthFrames = 0;
	mBufferData.buffers[bufferToClose].loadedFrames = 0;

    if (mBufferData.buffers[bufferToClose].inputFileLoader) {
		[mBufferData.buffers[bufferToClose].inputFileLoader abortLoading];
		[mBufferData.buffers[bufferToClose].inputFileLoader release];
		mBufferData.buffers[bufferToClose].inputFileLoader = nil;
		result = true;
	}

	if (mBufferData.buffers[bufferToClose].data) {
		vm_deallocate(mach_task_self(),
					  (vm_address_t)mBufferData.buffers[bufferToClose].data,
					  (vm_size_t)mBufferData.buffers[bufferToClose].dataSizeInBytes);
		mBufferData.buffers[bufferToClose].dataSizeInBytes = 0;
		mBufferData.buffers[bufferToClose].data = NULL;
	}
	return result;
}

- (bool)areBothBuffersFromSameFile
{
	return (mBufferData.buffers[0].inputFileLoader == mBufferData.buffers[1].inputFileLoader);
}

- (bool)isAudioBuffersEmpty:(int)bufferIndex
{
	if ((bufferIndex <0) || (bufferIndex > 1)) return YES;

	return (!mBufferData.buffers[bufferIndex].inputFileLoader);
}

- (SInt32)bufferIndexForNextChunkToLoad
{
	return mBufferData.bufferIndexForNextChunkToLoad;
}

- (bool)bufferContainsWholeTrack:(int)bufferIndex
{
	return (mBufferData.buffers[bufferIndex].firstFrameOffset == 0)
	&& ((mBufferData.buffers[bufferIndex].inputFileLoadStatus & kAudioFileLoaderStatusEOF) == kAudioFileLoaderStatusEOF);
}

- (int)playingBuffer
{
	return mBufferData.playingAudioBuffer;
}

- (void)setPlayingBuffer:(int)playingBuffer
{
	if (![self areBothBuffersFromSameFile]) {
		//Update interface
		NSString *title = [mBufferData.buffers[playingBuffer].inputFileLoader title];
		if (title == nil) title = [[mBufferData.buffers[playingBuffer].inputFileLoader inputFileURL] lastPathComponent];

		[mBufferData.appController updateMetadataDisplay:title
												   album:[mBufferData.buffers[playingBuffer].inputFileLoader album]
												  artist:[mBufferData.buffers[playingBuffer].inputFileLoader artist]
												composer:[mBufferData.buffers[playingBuffer].inputFileLoader composer]
											  coverImage:[mBufferData.buffers[playingBuffer].inputFileLoader coverImage]
												duration:((Float64)[mBufferData.buffers[playingBuffer].inputFileLoader lengthFrames] /
														  [mBufferData.buffers[playingBuffer].inputFileLoader nativeSampleRate])
											 integerMode:mBufferData.isIntegerModeOn
												bitDepth:[mBufferData.buffers[playingBuffer].inputFileLoader bitDepth]
										  fileSampleRate:[mBufferData.buffers[playingBuffer].inputFileLoader nativeSampleRate]
									   playingSampleRate:[mBufferData.buffers[playingBuffer].inputFileLoader targetSampleRate]];

		if ((mBufferData.buffers[playingBuffer].sampleRate != audioDeviceCurrentNominalSampleRate) & isPlaying) {
			mBufferData.isIOPaused |= kAudioIOProcSampleRateChanging;
			[self setSamplingRate:mBufferData.buffers[playingBuffer].sampleRate];
		}
	}

	mBufferData.playingAudioBuffer = playingBuffer;
}

- (void)unswapPlayingBuffer
{
	[mBufferData.buffers[mBufferData.playingAudioBuffer].inputFileLoader unswapBuffer:mBufferData.buffers[mBufferData.playingAudioBuffer].data
														  bufferSize:mBufferData.buffers[mBufferData.playingAudioBuffer].lengthFrames
																from:mBufferData.buffers[mBufferData.playingAudioBuffer].currentPlayingFrame];
}

#pragma mark -
#pragma mark Device Control fonctions

- (void)setSamplingRate:(Float64)newSamplingRate
{
	OSStatus err;
	AudioObjectPropertyAddress propertyAddress;

	//Change sampling rate of device and/or set up sampling rate converter
	if (newSamplingRate != audioDeviceCurrentNominalSampleRate) {
		if ([[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] isSampleRateHandled:newSamplingRate
                                                                                 withLimit:YES]) {
			//Switch device sample rate
			propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
			propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
			propertyAddress.mElement = kAudioObjectPropertyElementMaster;

			err = AudioObjectSetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, sizeof(Float64), &newSamplingRate);

			if (err == kAudioHardwareNoError) audioDeviceCurrentNominalSampleRate = newSamplingRate;
			else mBufferData.isIOPaused &= ~kAudioIOProcSampleRateChanging;
		}
	}
	else mBufferData.isIOPaused &= ~kAudioIOProcSampleRateChanging;
	// mBufferData.isChangingSamplingRate will be set to NO by the listener function when device notifies it is done
}

- (bool)isChangingSamplingRate
{
	return (mBufferData.isIOPaused & kAudioIOProcSampleRateChanging) != 0;
}

- (void)samplerateSwitchIsComplete
{
    NSTimeInterval notificationLatency = 0.0;

    switch ([[NSUserDefaults standardUserDefaults] integerForKey:AUDSampleRateSwitchingLatency]) {
        case kAUDSRCSplRateSwitchingLatency0_5s:
            notificationLatency = 0.5;
            break;
        case kAUDSRCSplRateSwitchingLatency1s:
            notificationLatency = 1.0;
            break;
        case kAUDSRCSplRateSwitchingLatency1_5s:
            notificationLatency = 1.5;
            break;
        case kAUDSRCSplRateSwitchingLatency2s:
            notificationLatency = 2.0;
            break;
        case kAUDSRCSplRateSwitchingLatency3s:
            notificationLatency = 3.0;
            break;
        case kAUDSRCSplRateSwitchingLatency4s:
            notificationLatency = 4.0;
            break;
        case kAUDSRCSplRateSwitchingLatency5s:
            notificationLatency = 5.0;
            break;

        case kAUDSRCSplRateSwitchingLatencyNone:
        default:
            notificationLatency = 0.0;
            break;
    }

    [self performSelector:@selector(samplerateSwitchUnPause) withObject:nil afterDelay:notificationLatency];
}

- (void)samplerateSwitchUnPause
{
    mBufferData.isIOPaused &= ~kAudioIOProcSampleRateChanging;
}

- (bool)isIntegerModeOn
{
	return mBufferData.isIntegerModeOn;
}

- (UInt32)availableVolumeControls
{
	return [[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] availableVolumeControls];
}

- (Float32)masterVolumeScalar:(UInt32)typeOfVolume
{
	AudioObjectPropertyAddress propertyAddress;
	UInt32 propertySize;
	Float32 currentVolume=(Float32)0.0;

	switch (typeOfVolume) {
		case kAudioVolumePhysicalControl:
			if ([[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] availableVolumeControls] & kAudioVolumePhysicalControl) {
				propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
				propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
				propertyAddress.mElement = kAudioObjectPropertyElementMaster;
				propertySize = sizeof(currentVolume);
				AudioObjectGetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, &propertySize, &currentVolume);
			}
			break;
		case kAudioVolumeVirtualControl:
			if ([[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] availableVolumeControls] & kAudioVolumeVirtualControl) {
				propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
				propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
				propertyAddress.mElement = kAudioObjectPropertyElementMaster;
				propertySize = sizeof(currentVolume);
				AudioObjectGetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, &propertySize, &currentVolume);
			}
			break;
		default:
			return (Float32)0.0;
			break;
	}
	return currentVolume;
}

- (void)setMasterVolumeScalar:(Float32)newVolume forType:(UInt32)typeOfVolume
{
	AudioObjectPropertyAddress propertyAddress;
	UInt32 propertySize;

	if (newVolume < 0.0) newVolume = (Float32)0.0;
	else if (newVolume > 1.0) newVolume = (Float32)1.0;

	switch (typeOfVolume) {
		case kAudioVolumePhysicalControl:
			if ([[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] availableVolumeControls] & kAudioVolumePhysicalControl) {
				propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
				propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
				propertyAddress.mElement = kAudioObjectPropertyElementMaster;
				propertySize = sizeof(newVolume);
				AudioObjectSetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, propertySize, &newVolume);
			}
			break;
		case kAudioVolumeVirtualControl:
			if ([[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] availableVolumeControls] & kAudioVolumeVirtualControl) {
				propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume;
				propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
				propertyAddress.mElement = kAudioObjectPropertyElementMaster;
				propertySize = sizeof(newVolume);
				AudioObjectSetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, propertySize, &newVolume);
			}
			break;
		default:
			break;
	}
}

- (Float32)masterVolumeDecibel:(UInt32)typeOfVolume
{
	AudioObjectPropertyAddress propertyAddress;
	UInt32 propertySize;
	Float32 currentVolume=(Float32)0.0;

	switch (typeOfVolume) {
		case kAudioVolumePhysicalControl:
			if ([[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] availableVolumeControls] & kAudioVolumePhysicalControl) {
				propertyAddress.mSelector = kAudioDevicePropertyVolumeDecibels;
				propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
				propertyAddress.mElement = kAudioObjectPropertyElementMaster;
				propertySize = sizeof(currentVolume);
				AudioObjectGetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, &propertySize, &currentVolume);
			}
			break;
		case kAudioVolumeVirtualControl:
			if ([[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] availableVolumeControls] & kAudioVolumeVirtualControl) {
				currentVolume = [self masterVolumeScalar:typeOfVolume];
				if (currentVolume <=0) currentVolume = -INFINITY;
				else currentVolume = (Float32)(20.0*log(currentVolume));
			}
			break;
		default:
			return (Float32)0.0;
			break;
	}
	return currentVolume;
}

- (void)setMute:(BOOL)isToMute
{
  	AudioObjectPropertyAddress propertyAddress;
	UInt32 propertySize;
    UInt32 mutingProperty = isToMute?1:0;

    propertyAddress.mSelector = kAudioDevicePropertyMute;
    propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
    propertyAddress.mElement = kAudioObjectPropertyElementMaster;
    propertySize = sizeof(mutingProperty);
    AudioObjectSetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, propertySize, &mutingProperty);
}

- (bool)isMute
{
    AudioObjectPropertyAddress propertyAddress;
	UInt32 propertySize;
    UInt32 mutingProperty;

    propertyAddress.mSelector = kAudioDevicePropertyMute;
    propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
    propertyAddress.mElement = kAudioObjectPropertyElementMaster;
    propertySize = sizeof(mutingProperty);
    AudioObjectGetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, &propertySize, &mutingProperty);

    return mutingProperty!=0;
}

#pragma mark -
#pragma mark Playback control functions

- (bool)initiatePlayback:(NSError**)outError
{
	AudioObjectPropertyAddress propertyAddress;
	UInt32 propertySize;
	UInt32 tmpInt;
	OSStatus err;
	pid_t hoggingProcess;

	//Ensure playback is stopped
	if (isPlaying) return false;

	//Init shared structure values
	mBufferData.isIOPaused = 0;
	mBufferData.willChangePlayingBuffer = NO;

	//Check device is alive
	propertyAddress.mSelector = kAudioDevicePropertyDeviceIsAlive;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	propertySize = sizeof(UInt32);

	AudioObjectGetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, &propertySize, &tmpInt);
	if (tmpInt == 0) return false;

	//Check if device is hogged by another process
	propertyAddress.mSelector = kAudioDevicePropertyHogMode;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	propertySize = sizeof(pid_t);

	AudioObjectGetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, &propertySize, &hoggingProcess);
	if ((hoggingProcess != -1) && (hoggingProcess != getpid())) {
		NSRunAlertPanel(NSLocalizedString(@"Error initializing sound device",@"Hogged by other alert panel"),
                        NSLocalizedString(@"The sound device is already hogged by another application\nUnable to start playing",@"Hogged by other alert panel"),
						NSLocalizedString(@"Cancel",@"Cancel button title"), nil, nil);
		if (outError) {
			NSDictionary *errDict=[NSDictionary dictionaryWithObject:NSLocalizedString(@"Error: unable to grab exclusive access",@"Error message for exclusive access")
															  forKey:NSLocalizedDescriptionKey];
			*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:0 userInfo:errDict];
		}
		return false;
	}

	//Take exclusive access to the device (hog mode)
	if ([[NSUserDefaults standardUserDefaults] boolForKey:AUDHogMode]) {
		mBufferData.playbackStartPhase = kAudioPlaybackStartHoggingDevice;
		hoggingProcess = getpid();
		err = AudioObjectSetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, sizeof(pid_t), &hoggingProcess);

		if (err != kAudioHardwareNoError) {
			mBufferData.isHoggingDevice = NO; //Fallback nicely if unable to hog device that was already tested to be available
			mBufferData.playbackStartPhase = kAudioPlaybackStartDeviceHogged;
			return [self initiatePlaybackAfterHoggingDevice];
		}
		else {
			//Hogging success will be notified asynchronously, so set up timeout to cope with failure
			[self performSelector:@selector(initiatePlaybackTimedOut) withObject:nil afterDelay:2.0];
		}
	}
	else {
		mBufferData.isHoggingDevice = NO;
		mBufferData.playbackStartPhase = kAudioPlaybackStartDeviceHogged;
		return [self initiatePlaybackAfterHoggingDevice];
	}

	if ((err != kAudioHardwareNoError) && outError)
		*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];

	return (err == kAudioHardwareNoError);
}

- (bool)initiatePlaybackAfterHoggingDevice
{
	AudioObjectPropertyAddress propertyAddress;
	UInt32 propertySize;
	OSStatus err = kAudioHardwareNoError;

	//Cancel timeout
	[[self class] cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(initiatePlaybackTimedOut) object:nil];

	//Reload stream format that may have changed after hogging device
	[self loadStreamVirtualFormat:[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:0]];
	[self loadStreamPhysicalFormat:[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:0]];

	//Save the current stream format that'll be restored when stopping
	propertySize=sizeof(AudioStreamBasicDescription);
	propertyAddress.mSelector = kAudioStreamPropertyPhysicalFormat;
	propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	AudioObjectGetPropertyData([[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream] streamID],
							   &propertyAddress, 0, NULL, &propertySize, &originalStreamFormat);


	if ([[NSUserDefaults standardUserDefaults] boolForKey:AUDIntegerMode]
		&& [self getIntegerModeFormat:&mBufferData.integerModeStreamFormatToBe
                        forSampleRate:audioDeviceCurrentNominalSampleRate]) {

		//Set Integer Mode if an integer stream has been detected
		mBufferData.playbackStartPhase = kAudioPlaybackStartChangingStreamFormat;

		//First check if device is not already in int mode
		propertySize=sizeof(AudioStreamBasicDescription);
		propertyAddress.mSelector = kAudioStreamPropertyVirtualFormat;
		propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement = kAudioObjectPropertyElementMaster;
		err = AudioObjectGetPropertyData([[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream] streamID],
										 &propertyAddress, 0, NULL, &propertySize, &mBufferData.integerModeStreamFormat);

		if ((mBufferData.integerModeStreamFormat.mFormatID == mBufferData.integerModeStreamFormatToBe.mFormatID)
			&& (mBufferData.integerModeStreamFormat.mFormatFlags == mBufferData.integerModeStreamFormatToBe.mFormatFlags)
			&& (mBufferData.integerModeStreamFormat.mBitsPerChannel == mBufferData.integerModeStreamFormatToBe.mBitsPerChannel)
			&& (mBufferData.integerModeStreamFormat.mChannelsPerFrame == mBufferData.integerModeStreamFormatToBe.mChannelsPerFrame)
            && (mBufferData.integerModeStreamFormat.mBytesPerFrame == mBufferData.integerModeStreamFormatToBe.mBytesPerFrame)) {

			mBufferData.playbackStartPhase = kAudioPlaybackStartFinishingDeviceInitialization;
			mBufferData.isIntegerModeOn = TRUE;
			[self initiatePlaybackCompletingInit];
			return true;
		}
		else {
			propertyAddress.mSelector = kAudioStreamPropertyPhysicalFormat;
			propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
			propertyAddress.mElement = kAudioObjectPropertyElementMaster;
			propertySize = sizeof(AudioStreamBasicDescription);
			err = AudioObjectSetPropertyData([[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream] streamID],
											 &propertyAddress, 0, NULL, propertySize, &mBufferData.integerModeStreamFormatToBe);
			if ((err == kAudioHardwareNoError) && (mBufferData.channelMap[0].stream != mBufferData.channelMap[1].stream))
				err = AudioObjectSetPropertyData([[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[1].stream] streamID],
												 &propertyAddress, 0, NULL, propertySize, &mBufferData.integerModeStreamFormatToBe);

			mBufferData.isIntegerModeOn = TRUE;
			audioDeviceCurrentPhysicalBitDepth = mBufferData.integerModeStreamFormatToBe.mBitsPerChannel;

			//Delay playback start until getting confirmation of virtual format change
			//As success will be notified asynchronously, set up timeout to cope with failure
			[self performSelector:@selector(initiatePlaybackTimedOut) withObject:nil afterDelay:2.0];
		}
	}
	else {
		//Set format to physical format when not in Integer Mode
		AudioStreamBasicDescription audioFormat;

		mBufferData.isIntegerModeOn = FALSE;

		if ([self getPhysicalMixableFormat:&audioFormat forSampleRate:audioDeviceCurrentNominalSampleRate]
			&& (audioFormat.mSampleRate == audioDeviceCurrentNominalSampleRate)
			&& (audioFormat.mBitsPerChannel >= 24)) {

			propertyAddress.mSelector = kAudioStreamPropertyPhysicalFormat;
			propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
			propertyAddress.mElement = kAudioObjectPropertyElementMaster;
			propertySize = sizeof(audioFormat);

			err = AudioObjectSetPropertyData([[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream] streamID],
			 &propertyAddress, 0, NULL, propertySize, &audioFormat);
        }

        propertyAddress.mSelector = kAudioStreamPropertyVirtualFormat;
        propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
        propertyAddress.mElement = kAudioObjectPropertyElementMaster;
        propertySize = sizeof(mBufferData.integerModeStreamFormat);
        err = AudioObjectGetPropertyData([[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream] streamID],
                                         &propertyAddress, 0, NULL, &propertySize, &mBufferData.integerModeStreamFormat);

        audioDeviceCurrentPhysicalBitDepth = audioFormat.mBitsPerChannel;
        if (audioDeviceCurrentPhysicalBitDepth > 24) audioDeviceCurrentPhysicalBitDepth = 24; //32bit float can't convey more than 24bits

		//Continues playback
		if (err == kAudioHardwareNoError) {
			[self initiatePlaybackCompletingInit];
			return true;
		}
		else return false;
	}
	return (err == kAudioHardwareNoError);
}

- (bool)initiatePlaybackCompletingInit
{
	AudioObjectPropertyAddress propertyAddress;
	AudioHardwareIOProcStreamUsage *streamsUsage;
	UInt32 propertySize;
	UInt32 tmpInt;
	OSStatus err;

	//Cancel timeout
	[[self class] cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(initiatePlaybackTimedOut) object:nil];

	//Force the decoded audio stream to be stereo (can be set to more for multichannel devices)
    memcpy(&mBufferData.buffersStreamFormat, &mBufferData.integerModeStreamFormat, sizeof(AudioStreamBasicDescription));
	mBufferData.buffersStreamFormat.mBytesPerFrame = (mBufferData.buffersStreamFormat.mBytesPerFrame * 2) / mBufferData.buffersStreamFormat.mChannelsPerFrame;
	mBufferData.buffersStreamFormat.mBytesPerPacket = mBufferData.buffersStreamFormat.mBytesPerFrame;
   	mBufferData.buffersStreamFormat.mChannelsPerFrame = 2;
	mBufferData.buffersStreamFormat.mFramesPerPacket = 1;

	//Enable only the used output streams, optimization needed only on multi-channel devices
	tmpInt = (UInt32)[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] count];
    if (tmpInt > 2) {
        propertySize = (UInt32)(offsetof(AudioHardwareIOProcStreamUsage, mStreamIsOn) + (sizeof(UInt32) * tmpInt));
        streamsUsage = (AudioHardwareIOProcStreamUsage*)malloc(propertySize);
        streamsUsage->mIOProc = &audioOutIOProcID;
        streamsUsage->mNumberStreams = tmpInt;
        for (tmpInt=0;tmpInt<streamsUsage->mNumberStreams;tmpInt++)
            streamsUsage->mStreamIsOn[tmpInt] = false;

        streamsUsage->mStreamIsOn[mBufferData.channelMap[0].stream] = true;
        streamsUsage->mStreamIsOn[mBufferData.channelMap[1].stream] = true;

        propertyAddress.mSelector = kAudioDevicePropertyIOProcStreamUsage;
        propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
        propertyAddress.mElement = kAudioObjectPropertyElementMaster;
        AudioObjectSetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL,
                                         propertySize, streamsUsage);
        free(streamsUsage);
    }


	//Set maximum buffer size if wished
	//Refresh available size range, as it may be different in Integer Mode
	[self loadDeviceBufferFrameSizeRange:[audioDevicesList objectAtIndex:selectedAudioDeviceIndex]];

	//First save initial size
	propertyAddress.mSelector = kAudioDevicePropertyBufferFrameSize;
	propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;
	propertySize = sizeof(UInt32);

	AudioObjectGetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, &propertySize, &audioDeviceInitialIOBufferFrameSize);

	if ([[NSUserDefaults standardUserDefaults] boolForKey:AUDForceMaxIOBufferSize]
		&& (audioDeviceInitialIOBufferFrameSize != [[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] maximumBufferFrameSize])) {
		UInt32 audioBufferFrameSize;
		//Boolean isSettable;

		propertyAddress.mSelector = kAudioDevicePropertyBufferFrameSize;
		propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement = kAudioObjectPropertyElementMaster;

		//err = AudioObjectIsPropertySettable(mBufferData.selectedAudioDeviceID, &propertyAddress, &isSettable);

		audioBufferFrameSize = (UInt32)[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] maximumBufferFrameSize];
		AudioObjectSetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, sizeof(UInt32), &audioBufferFrameSize);

		/* Do not force pause until buffer change size, because some drivers don't send this notification
		 In addition, this has no audible impact
		 if (err == kAudioHardwareNoError)
		 mBufferData.isIOPaused |= kAudioIOProcAudioBufferSizeChanging;*/
	}

	//Set sampling rate
	//Get the current nominal sample rate
	propertySize=sizeof(Float64);
	propertyAddress.mSelector=kAudioDevicePropertyNominalSampleRate;
	propertyAddress.mScope=kAudioObjectPropertyScopeGlobal;
	propertyAddress.mElement=kAudioObjectPropertyElementMaster;
	AudioObjectGetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, &propertySize, &audioDeviceCurrentNominalSampleRate);

	//Set up callback connection
	err = AudioDeviceCreateIOProcID(mBufferData.selectedAudioDeviceID, coreAudioOutputIOProc, &mBufferData, &audioOutIOProcID);

	if (err == kAudioHardwareNoError) {
		[mBufferData.appController startPlayingPhase2];
		return true;
	}
	else return false;
}

- (void)initiatePlaybackTimedOut
{
	[self stop];

	NSDictionary *errDict;
	NSError *error;

	switch (mBufferData.playbackStartPhase) {
		case kAudioPlaybackStartHoggingDevice:
			errDict = [NSDictionary dictionaryWithObject:NSLocalizedString(@"Error: unable to grab exclusive access",@"Error message for exclusive access")
												  forKey:NSLocalizedDescriptionKey];
			error = [NSError errorWithDomain:NSOSStatusErrorDomain code:'hog!' userInfo:errDict];
			[mBufferData.appController abortPlayingStart:error];
			break;
		case kAudioPlaybackStartChangingStreamFormat:
			errDict = [NSDictionary dictionaryWithObject:NSLocalizedString(@"Error: unable to change to Integer Mode",@"Error message for Integer Mode")
												  forKey:NSLocalizedDescriptionKey];
			error = [NSError errorWithDomain:NSOSStatusErrorDomain code:'sfmt' userInfo:errDict];
			[mBufferData.appController abortPlayingStart:error];
			break;

		default:
			errDict = [NSDictionary dictionaryWithObject:NSLocalizedString(@"Error initializing audio device",@"Error message for device init")
												  forKey:NSLocalizedDescriptionKey];
			error = [NSError errorWithDomain:NSOSStatusErrorDomain code:'adev' userInfo:errDict];
			[mBufferData.appController abortPlayingStart:error];
			break;
	}
}

- (UInt32)deviceInitializationStatus
{
	return mBufferData.playbackStartPhase;
}

- (BOOL)startPlayback:(NSError**)outError
{
	OSStatus err = noErr;

	//Ensure playback is stopped
	if (isPlaying) return -1;

    //Start paused to allow for sample rate conversion
    mBufferData.isIOPaused |= kAudioIOProcPause;

	//Start device I/O
	err = AudioDeviceStart(mBufferData.selectedAudioDeviceID, audioOutIOProcID);

	if (err == noErr) isPlaying = true;
	else
		if (outError) {
			NSDictionary *errDict=[NSDictionary dictionaryWithObject:NSLocalizedString(@"Error starting device playback",@"Generic error message for device start")
															  forKey:NSLocalizedDescriptionKey];
			*outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:errDict];
		}

    if (mBufferData.buffers[mBufferData.playingAudioBuffer].inputFileLoader
        && (mBufferData.buffers[mBufferData.playingAudioBuffer].sampleRate != audioDeviceCurrentNominalSampleRate)) {
        mBufferData.isIOPaused |= kAudioIOProcSampleRateChanging;
		[self setSamplingRate:mBufferData.buffers[0].sampleRate];
    }
    else {
        //Allow remote DAC to synchronize, even if no sample rate change has occured
        mBufferData.isIOPaused |= kAudioIOProcSampleRateChanging;
        [self samplerateSwitchIsComplete];
    }

    //Unpause
    mBufferData.isIOPaused &= ~kAudioIOProcPause;

	return (err == noErr);
}

- (bool)stop
{
	Float64 deviceMaxSplRate;
	OSStatus err;
	AudioObjectPropertyAddress propertyAddress;
	UInt32 propertySize;

	//Ensure playback is running, and file is open
	if (!isPlaying) return false;

	//Stop device I/O
	err = AudioDeviceStop(mBufferData.selectedAudioDeviceID, audioOutIOProcID);

	//Tell the user audio device is stopping
	deviceMaxSplRate = [[audioDevicesList objectAtIndex:selectedAudioDeviceIndex]	maxSampleRate];
	[mBufferData.appController updateMetadataDisplay:NSLocalizedString(@"Stopping audio device...",@"Info line stopping device") album:@"" artist:@"" composer:@""
										  coverImage:nil duration:0.0
										 integerMode:mBufferData.isIntegerModeOn
											bitDepth:audioDeviceCurrentPhysicalBitDepth
									  fileSampleRate:deviceMaxSplRate
								   playingSampleRate:deviceMaxSplRate];

	//Disconnect I/O callback
	err = AudioDeviceDestroyIOProcID(mBufferData.selectedAudioDeviceID, audioOutIOProcID);
	audioOutIOProcID = 0;

	//TODO: Switch back device sampling rate to previous one (if needed)

	//Switch back to initial buffer size
	propertyAddress.mSelector = kAudioDevicePropertyBufferFrameSize;
	propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
	propertyAddress.mElement = kAudioObjectPropertyElementMaster;

	err = AudioObjectSetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, sizeof(UInt32), &audioDeviceInitialIOBufferFrameSize);

	//Switch back to mixable format
	if (mBufferData.isIntegerModeOn) {

		mBufferData.playbackStartPhase = kAudioPlaybackSwitchingBackToFloatMode;

		propertyAddress.mSelector = kAudioStreamPropertyPhysicalFormat;
		propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement = kAudioObjectPropertyElementMaster;
		propertySize = sizeof(originalStreamFormat);
		err = AudioObjectSetPropertyData([[[[audioDevicesList objectAtIndex:selectedAudioDeviceIndex] streams] objectAtIndex:mBufferData.channelMap[0].stream] streamID],
										 &propertyAddress, 0, NULL, propertySize, &originalStreamFormat);
		mBufferData.isIntegerModeOn = NO;

		//perform device complete stop anyway
		[self performSelector:@selector(completeDeviceStop) withObject:nil afterDelay:2.0];
	}
	else {
		mBufferData.playbackStartPhase = kAudioPlaybackNotInStartingPhase;
		[self completeDeviceStop];
	}

	isPlaying = false;
	return true;
}

- (void)completeDeviceStop
{
	Float64 deviceMaxSplRate;
	AudioObjectPropertyAddress propertyAddress;
	pid_t	hogMode;

	//Cancel timeout
	[[self class] cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(completeDeviceStop) object:nil];

	//release device access
	if (mBufferData.isHoggingDevice) {
		propertyAddress.mSelector = kAudioDevicePropertyHogMode;
		propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
		propertyAddress.mElement = kAudioObjectPropertyElementMaster;
		hogMode = -1;
		AudioObjectSetPropertyData(mBufferData.selectedAudioDeviceID, &propertyAddress, 0, NULL, sizeof(pid_t), &hogMode);
	}
	mBufferData.isHoggingDevice = NO;

	deviceMaxSplRate = [[audioDevicesList objectAtIndex:selectedAudioDeviceIndex]	maxSampleRate];
	[mBufferData.appController updateMetadataDisplay:@"" album:@"" artist:@"" composer:@""
										  coverImage:nil duration:0.0
										 integerMode:mBufferData.isIntegerModeOn
											bitDepth:audioDeviceCurrentPhysicalBitDepth
									  fileSampleRate:deviceMaxSplRate
								   playingSampleRate:deviceMaxSplRate];

}

- (bool)pause:(bool)isPaused
{
	if (isPaused)
		mBufferData.isIOPaused |= kAudioIOProcPause;
	else
		mBufferData.isIOPaused &= ~kAudioIOProcPause;

	return TRUE;
}

- (bool)isPaused
{
	return (mBufferData.isIOPaused & kAudioIOProcPause) != 0;
}

- (bool)willChangePlayingBuffer
{
	return mBufferData.willChangePlayingBuffer;
}

- (void)resetWillChangePlayingBuffer
{
	mBufferData.willChangePlayingBuffer = NO;
}

- (bool)seek:(UInt64)seekPosition
{
	/* Inter-threads sync notes:
	 First make a copy of the buffers pointers in this thread.
	 Then, the playing tape position is linked to the specific buffer,
	 thus the main risk of making it to point outside the buffer in case
	 of a buffer swap requested by the playing thread is prevented */
	SInt32 playingBuffer = mBufferData.playingAudioBuffer;

	/* First check if current is "split loaded" : either current buffer load is incomplete
	 or it doesn't start at 0 (check needed in case of last load)*/
	if (((mBufferData.buffers[playingBuffer].inputFileLoadStatus & kAudioFileLoaderStatusEOF) == 0)
		|| (mBufferData.buffers[playingBuffer].firstFrameOffset>0))
	{
		SInt64 inBufferSeek = (SInt64)seekPosition - mBufferData.buffers[playingBuffer].firstFrameOffset;

		if ((inBufferSeek>=0) && (inBufferSeek <= mBufferData.buffers[playingBuffer].loadedFrames)) {
			//ok to seek in current buffer
			mBufferData.buffers[playingBuffer].currentPlayingFrame = inBufferSeek;
		}
		else {
			int otherBuffer = playingBuffer==0?1:0;
			inBufferSeek = (SInt64)seekPosition - mBufferData.buffers[otherBuffer].firstFrameOffset;
			if ([self areBothBuffersFromSameFile]
                && (inBufferSeek>=0) && (inBufferSeek <= mBufferData.buffers[otherBuffer].loadedFrames)) {
				//position is in other buffer => swap buffers
				[self pause:YES];
				mBufferData.buffers[otherBuffer].currentPlayingFrame = inBufferSeek;
				mBufferData.playingAudioBuffer = otherBuffer;

				//And load next chunk for the old buffer
				usleep(50000); //Wait to be sure the I/O proc will not read from the to be freed buffer
				//Perform buffer close without aborting load as it is performed on the other buffer
				if (mBufferData.buffers[playingBuffer].inputFileLoader) {
					[mBufferData.buffers[playingBuffer].inputFileLoader release];
					mBufferData.buffers[playingBuffer].inputFileLoader = nil;
					mBufferData.buffers[playingBuffer].lengthFrames = 0;
					mBufferData.buffers[playingBuffer].loadedFrames = 0;
				}
				if (mBufferData.buffers[playingBuffer].data) {
					vm_deallocate(mach_task_self(),
								  (vm_address_t)mBufferData.buffers[playingBuffer].data,
								  (vm_size_t)mBufferData.buffers[playingBuffer].dataSizeInBytes);
					mBufferData.buffers[playingBuffer].dataSizeInBytes = 0;
					mBufferData.buffers[playingBuffer].data = NULL;
				}

				if (![mBufferData.appController fillBufferWithNext:playingBuffer]) {
                    //Also remove this buffer from the loading progress bar if no other track after
                    //Is needed as there is no chunk load calling load progress bar update method
                    [mBufferData.appController resetLoadStatus:YES];
                }
				[self pause:NO];
			}
			else {
				//Need to reload both buffers
				[self pause:YES];
				[self closeBuffer:otherBuffer];
				[mBufferData.appController resetLoadStatus:NO];
				[self loadNextChunk:otherBuffer at:seekPosition];
				mBufferData.playingAudioBuffer = otherBuffer;

				//And load next chunk for the old playing buffer
				usleep(50000); //Wait to be sure the I/O proc will not read from the to be freed buffer
				//Perform buffer close without aborting load as it is performed on the other buffer
				if (mBufferData.buffers[playingBuffer].inputFileLoader) {
					[mBufferData.buffers[playingBuffer].inputFileLoader release];
					mBufferData.buffers[playingBuffer].inputFileLoader = nil;
					mBufferData.buffers[playingBuffer].lengthFrames = 0;
					mBufferData.buffers[playingBuffer].loadedFrames = 0;
				}
				if (mBufferData.buffers[playingBuffer].data) {
					vm_deallocate(mach_task_self(),
								  (vm_address_t)mBufferData.buffers[playingBuffer].data,
								  (vm_size_t)mBufferData.buffers[playingBuffer].dataSizeInBytes);
					mBufferData.buffers[playingBuffer].dataSizeInBytes = 0;
					mBufferData.buffers[playingBuffer].data = NULL;
				}

				[mBufferData.appController fillBufferWithNext:playingBuffer];
				[self pause:NO];
			}
		}

	}
	else {
		if ((SInt64)seekPosition >= mBufferData.buffers[playingBuffer].loadedFrames)
			seekPosition = mBufferData.buffers[playingBuffer].loadedFrames;
		/*else if (seekPosition <0)
			seekPosition = 0;*/

		mBufferData.buffers[playingBuffer].currentPlayingFrame = seekPosition;
	}

	return true;
}

- (UInt64)currentPlayingPosition
{
	/*Potentially not coherent value due to race condition
	But not a real issue (unwanted event of low severity)
	and low occurence*/
	return (mBufferData.buffers[mBufferData.playingAudioBuffer].currentPlayingFrame
			+ mBufferData.buffers[mBufferData.playingAudioBuffer].firstFrameOffset);
}

#pragma mark Debug information helper
- (NSString*)description
{
	UInt32 i;
	AudioDeviceDescription *deviceDesc;
	NSMutableString *debugStr = [[[NSMutableString alloc] initWithCapacity:1000] autorelease];

	[debugStr appendFormat:@"\nAudirvana rev. %@ debug information:\n", [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey]];

	if (isPlaying) {
		[debugStr appendFormat:@"\nCurrently playing %@\n",mBufferData.isIntegerModeOn?@"in Integer Mode:":@"in standard 32bit float mode"];

		[debugStr appendFormat:@"%@ linear PCM %@ %ibits %@ %@ %@",
		 (mBufferData.buffersStreamFormat.mFormatFlags & kAudioFormatFlagIsNonMixable)?@"Non-mixable":@"Mixable",
		 (mBufferData.buffersStreamFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved)?@"Non-interleaved":@"Interleaved",
		 mBufferData.buffersStreamFormat.mBitsPerChannel,
		 (mBufferData.buffersStreamFormat.mFormatFlags & kAudioFormatFlagIsBigEndian)?@"big endian":@"little endian",
		 (mBufferData.buffersStreamFormat.mFormatFlags & kAudioFormatFlagIsSignedInteger)?@"Signed":@"",
		 (mBufferData.buffersStreamFormat.mFormatFlags & kAudioFormatFlagIsFloat)?@"Float":@"Integer"];
		if ((mBufferData.buffersStreamFormat.mFormatFlags & kAudioFormatFlagIsPacked) == 0) {
			[debugStr appendFormat:@" %@ in %ibit",
			 (mBufferData.buffersStreamFormat.mFormatFlags & kAudioFormatFlagIsAlignedHigh)?@"aligned High":@"aligned low",
			 8*mBufferData.buffersStreamFormat.mBytesPerFrame/((mBufferData.buffersStreamFormat.mChannelsPerFrame ==0)?1:mBufferData.buffersStreamFormat.mChannelsPerFrame)
			 ];
		}
		[debugStr appendFormat:@", %i bytes per frame @%.1fkHz\n",mBufferData.buffersStreamFormat.mBytesPerFrame,
		 mBufferData.buffersStreamFormat.mSampleRate/1000.0f];
	}

	[debugStr appendFormat:@"\nHog Mode is %@\nDevices found : %i\n\nList of devices:\n",mBufferData.isHoggingDevice?@"on":@"off",[audioDevicesList count]];

	for (i=0;i<[audioDevicesList count];i++) {
		deviceDesc= [audioDevicesList objectAtIndex:i];
		[debugStr appendFormat:@"Device #%i: ID 0x%x %@\tUID:%@\n",i,[deviceDesc audioDevID],[deviceDesc name],[deviceDesc UID]];
	}

    [debugStr appendFormat:@"\nPreferred device: %@\tUID:%@\n", [[NSUserDefaults standardUserDefaults] stringForKey:AUDPreferredAudioDeviceName],
     [[NSUserDefaults standardUserDefaults] stringForKey:AUDPreferredAudioDeviceUID]];

	deviceDesc = [audioDevicesList objectAtIndex:selectedAudioDeviceIndex];
	[debugStr appendFormat:@"\nSelected device:"];

	[debugStr appendString:[deviceDesc description]];

	[debugStr appendFormat:@"\nSimple stereo device: %@",mBufferData.isSimpleStereoDevice?@"yes":@"no"];
	[debugStr appendFormat:@"\nChannel mapping: L:Stream %i channel %i R:Stream %i channel %i\n\n%i output streams:",mBufferData.channelMap[0].stream,mBufferData.channelMap[0].channel,
	 mBufferData.channelMap[1].stream,mBufferData.channelMap[1].channel,[[deviceDesc streams] count]];

	//Streams information
	for (i=0;i<[[deviceDesc streams] count];i++) {
		[debugStr appendString:[[[deviceDesc streams] objectAtIndex:mBufferData.channelMap[0].stream] description]];
	}

	return debugStr;
}
@end