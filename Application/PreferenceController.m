/*
 PreferenceController.m

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

 Original code written by Damien Plisson 10/2010
 */

#include <sys/types.h>
#include <sys/sysctl.h>

#import "PreferenceController.h"
#import "AudioOutput.h"


#pragma mark User preference keys & notifications

NSString * const AUDUISkinTheme = @"UISkinTheme";
NSString * const AUDUseAppleRemote = @"UseAppleRemote";
NSString * const AUDUseMediaKeys = @"UseMediaKeys";
NSString * const AUDUseMediaKeysForVolumeControl = @"UseMediaKeysForVolumeControl";
NSString * const AUDHogMode = @"HogMode";
NSString * const AUDIntegerMode = @"IntegerMode";
NSString * const AUDPreferredAudioDeviceUID = @"PreferredAudioDeviceUID";
NSString * const AUDPreferredAudioDeviceName = @"PreferredAudioDeviceName";
NSString * const AUDSampleRateSwitchingLatency = @"SampleRateSwitchingLatencyIndex";
NSString * const AUDMaxSampleRateLimit = @"MaxSampleRateLimitIndex";
NSString * const AUDMaxAudioBufferSize = @"MaxAudioBufferSize";
NSString * const AUDForceUpsamlingType = @"ForceUpsamplingType";
NSString * const AUDSampleRateConverterModel = @"SampleRateConverterModelIndex";
NSString * const AUDSampleRateConverterQuality = @"SampleRateConverterQuality";
NSString * const AUDForceMaxIOBufferSize = @"UseMaximumIOBufferSize";
NSString * const AUDUseUTF8forM3U = @"UseUTF8forM3U";
NSString * const AUDOutsideOpenedPlaylistPlaybackAutoStart = @"OutsideOpenedPlaylistPlaybackAutoStart";
NSString * const AUDAutosavePlaylist = @"AutosavePlaylist";

NSString * const AUDLoopModeActive = @"LoopModeActive";
NSString * const AUDShuffleModeActive = @"ShuffleModeActive";


NSString * const AUDPreferredDeviceChangeNotification =  @"AUDPreferredDeviceChanged";
NSString * const AUDAppleRemoteUseChangeNotification = @"AUDAppleRemoteUseChangeNotification";
NSString * const AUDMediaKeysUseChangeNotification = @"AUDMediaKeysUseChangeNotification";

#pragma mark PreferenceController implementation

@implementation PreferenceController

- (id)init
{
	audioDevicesUIDs = nil;

	if (![super initWithWindowNibName:@"Preferences"])
		return nil;
	return self;
}

- (void)dealloc
{
	if (audioDevicesUIDs) [audioDevicesUIDs release];
	[super dealloc];
}

- (void)windowDidLoad
{
	int maxAllowedAudioBufSize;
	int mib[] = {CTL_HW, HW_MEMSIZE};
    SInt64 ramSize;
    size_t propSize = sizeof(UInt64);

	sysctl(mib, 2, &ramSize, &propSize, NULL, 0);
    ramSize = (ramSize >> 20) - 1024; //Leave 1GB to OSX to run
	maxAllowedAudioBufSize = ((int)ramSize >> 10) << 10;
	if (maxAllowedAudioBufSize < 512) maxAllowedAudioBufSize = 512;

	[maxAudioBufferSizeSlider setMaxValue:maxAllowedAudioBufSize];
	[maxAudioBufferSizeSlider setNumberOfTickMarks:(maxAllowedAudioBufSize - 256)/128+1];
	[maxAudioBufferSizeSlider setIntValue:(int)(2*[[NSUserDefaults standardUserDefaults] integerForKey:AUDMaxAudioBufferSize])];
	[maxAudioBufferSizeValue setIntValue:[maxAudioBufferSizeSlider intValue]];

	[useAppleRemote setState:[[NSUserDefaults standardUserDefaults] boolForKey:AUDUseAppleRemote]];

	[preferredAudioDevice setStringValue:[[NSUserDefaults standardUserDefaults] stringForKey:AUDPreferredAudioDeviceName]];

	[hogMode setState:[[NSUserDefaults standardUserDefaults] boolForKey:AUDHogMode]];
	if ([[NSUserDefaults standardUserDefaults] boolForKey:AUDHogMode]) {
		[integerMode setState:[[NSUserDefaults standardUserDefaults] boolForKey:AUDIntegerMode]];
		[integerMode setEnabled:YES];
	}
	else {
		[integerMode setState:NO];
		[integerMode setEnabled:NO];
	}

    [useKbdMediaKeys setState:[[NSUserDefaults standardUserDefaults] boolForKey:AUDUseMediaKeys]];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:AUDUseMediaKeys]) {
        [useKbdMediaKeysForVolumeControl setEnabled:YES];
        [useKbdMediaKeysForVolumeControl setState:[[NSUserDefaults standardUserDefaults] boolForKey:AUDUseMediaKeysForVolumeControl]];
    }
    else {
        [useKbdMediaKeysForVolumeControl setEnabled:NO];
        [useKbdMediaKeysForVolumeControl setState:NO];
    }

	[[[self window] toolbar] setSelectedItemIdentifier:@"General"];
	[preferenceTabs selectTabViewItemAtIndex:0];

	activeDeviceMaxSplRate = 192000; //Default that should be overriden by the setActiveDeviceDesc call
}


#pragma mark User preferences external updates

- (void)setAvailableDevicesList:(NSArray*)devicesList
{
	AudioDeviceDescription *audioDevDesc;
	NSString *preferredDevUID = [[NSUserDefaults standardUserDefaults] stringForKey:AUDPreferredAudioDeviceUID];

	[audioCardsList removeAllItems];

	if (audioDevicesUIDs) [audioDevicesUIDs release];
	audioDevicesUIDs = [[NSMutableArray alloc] initWithCapacity:[devicesList count]];

	NSEnumerator *enumerator = [devicesList objectEnumerator];

   //Directly populate the undelying menu to bypass the duplicate removal feature
    NSMenu *popupMenu = [audioCardsList menu];

	while ((audioDevDesc = [enumerator nextObject]) != nil) {
        [popupMenu addItemWithTitle:audioDevDesc.name action:nil keyEquivalent:@""];
		[audioDevicesUIDs addObject:audioDevDesc.UID];
		if ([audioDevDesc.UID compare:preferredDevUID] == NSOrderedSame)
			[preferredAudioDevice setStringValue:audioDevDesc.name];
	}
}

- (void)setActiveDeviceDesc:(AudioDeviceDescription*)audioDevDesc
{
	NSColor *darkGreen = [NSColor colorWithCalibratedRed:0.0f green:0.4f blue:0.0f alpha:1.0f];
	[splRate44_1kHz setTextColor:([audioDevDesc isSampleRateHandled:44100.0 withLimit:NO]?darkGreen:[NSColor lightGrayColor])];
	[splRate48kHz setTextColor:([audioDevDesc isSampleRateHandled:48000.0 withLimit:NO]?darkGreen:[NSColor lightGrayColor])];
	[splRate88_2kHz setTextColor:([audioDevDesc isSampleRateHandled:88200.0 withLimit:NO]?darkGreen:[NSColor lightGrayColor])];
	[splRate96kHz setTextColor:([audioDevDesc isSampleRateHandled:96000.0 withLimit:NO]?darkGreen:[NSColor lightGrayColor])];
	[splRate176_4kHz setTextColor:([audioDevDesc isSampleRateHandled:176400.0 withLimit:NO]?darkGreen:[NSColor lightGrayColor])];
	[splRate192kHz setTextColor:([audioDevDesc isSampleRateHandled:192000.0 withLimit:NO]?darkGreen:[NSColor lightGrayColor])];

	[activeAudioDevice setStringValue:audioDevDesc.name];

	activeDeviceMaxSplRate = (NSUInteger)[audioDevDesc maxSampleRate];

	if (activeDeviceMaxSplRate > 192000) {
		[splRateHigherThan192kHz setTextColor:darkGreen];
		if ((activeDeviceMaxSplRate%1000) != 0)
			[splRateHigherThan192kHz setStringValue:[NSString stringWithFormat:@"%.0f",(float)activeDeviceMaxSplRate/1000]];
		else
			[splRateHigherThan192kHz setStringValue:[NSString stringWithFormat:@"%.1f",(float)activeDeviceMaxSplRate/1000]];
		[splRateHigherThan192kHz setHidden:NO];
	}
	else
		[splRateHigherThan192kHz setHidden:YES];

	UInt64 maxSeconds = (UInt64)[maxAudioBufferSizeSlider intValue]*1024*1024/2/(44100*8);
	[maxTrackLengthAt44_1 setStringValue:[NSString stringWithFormat:@"%imn @44.1kHz",maxSeconds/60]];
	if (activeDeviceMaxSplRate > 0.0) {
        maxSeconds = (UInt64)[maxAudioBufferSizeSlider intValue]*1024*1024/2/(activeDeviceMaxSplRate*8);
        if ((activeDeviceMaxSplRate%1000) != 0)
            [maxTrackLengthAt192 setStringValue:[NSString stringWithFormat:@"%imn @%.1fkHz",maxSeconds/60,(float)activeDeviceMaxSplRate/1000]];
        else
            [maxTrackLengthAt192 setStringValue:[NSString stringWithFormat:@"%imn @%.0fkHz",maxSeconds/60,(float)activeDeviceMaxSplRate/1000]];
    }
}


#pragma mark Tabs selection

- (IBAction)selectGeneralTab:(id)sender
{
	[preferenceTabs selectTabViewItemAtIndex:0];
}

- (IBAction)selectAudioDeviceTab:(id)sender
{
	[preferenceTabs selectTabViewItemAtIndex:1];
}

- (IBAction)selectAudioFiltersTab:(id)sender
{
	[preferenceTabs selectTabViewItemAtIndex:2];
}


#pragma mark Preferred device change

- (IBAction)raisePreferredDeviceChangeSheet:(id)sender
{
	[NSApp beginSheet:preferenceChangeSheet modalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}

- (IBAction)cancelPreferredDeviceChange:(id)sender
{
	[NSApp endSheet:preferenceChangeSheet];
	[preferenceChangeSheet orderOut:nil];
}

- (IBAction)changePreferredDevice:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setObject:[audioCardsList titleOfSelectedItem] forKey:AUDPreferredAudioDeviceName];
	[[NSUserDefaults standardUserDefaults] setObject:[audioDevicesUIDs objectAtIndex:[audioCardsList indexOfSelectedItem]] forKey:AUDPreferredAudioDeviceUID];
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDPreferredDeviceChangeNotification object:self];
	[preferredAudioDevice setStringValue:[audioCardsList titleOfSelectedItem]];
	[NSApp endSheet:preferenceChangeSheet];
	[preferenceChangeSheet orderOut:nil];
}

- (IBAction)changeMaxAudioBufferSize:(id)sender
{
	UInt64 maxSeconds = (UInt64)[maxAudioBufferSizeSlider intValue]*1024*1024/2/(44100*8);
	[maxTrackLengthAt44_1 setStringValue:[NSString stringWithFormat:@"%imn @44.1kHz",maxSeconds/60]];
	maxSeconds = (UInt64)[maxAudioBufferSizeSlider intValue]*1024*1024/2/(activeDeviceMaxSplRate*8);
	if ((activeDeviceMaxSplRate%1000) != 0)
		[maxTrackLengthAt192 setStringValue:[NSString stringWithFormat:@"%imn @%.1fkHz",maxSeconds/60,(float)activeDeviceMaxSplRate/1000]];
	else
		[maxTrackLengthAt192 setStringValue:[NSString stringWithFormat:@"%imn @%.0fkHz",maxSeconds/60,(float)activeDeviceMaxSplRate/1000]];

	[maxAudioBufferSizeValue setIntValue:[maxAudioBufferSizeSlider intValue]];

	[[NSUserDefaults standardUserDefaults] setInteger:[maxAudioBufferSizeSlider intValue]/2 forKey:AUDMaxAudioBufferSize];
}

- (IBAction)changeHogMode:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setBool:[hogMode state] forKey:AUDHogMode];

	//Disable and show as unselected the Integer Mode as it can happen only in hog mode
	if ([hogMode state]) {
		[integerMode setState:[[NSUserDefaults standardUserDefaults] boolForKey:AUDIntegerMode]];
		[integerMode setEnabled:YES];
	}
	else {
		[integerMode setState:NO];
		[integerMode setEnabled:NO];
	}
}

- (IBAction)changeIntegerMode:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setBool:[integerMode state] forKey:AUDIntegerMode];
}

#pragma mark General tab settings

- (IBAction)changeUISkinTheme:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:[uiSkinTheme selectedRow] forKey:AUDUISkinTheme];
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDUISkinTheme object:self];
}

- (IBAction)changeUseAppleRemote:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setBool:[useAppleRemote state] forKey:AUDUseAppleRemote];
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDAppleRemoteUseChangeNotification object:self];
}

- (IBAction)changeUseKbdMediaKeys:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:[useKbdMediaKeys state] forKey:AUDUseMediaKeys];

    if ([useKbdMediaKeys state]) {
        [useKbdMediaKeysForVolumeControl setEnabled:YES];
        [useKbdMediaKeysForVolumeControl setState:[[NSUserDefaults standardUserDefaults] boolForKey:AUDUseMediaKeysForVolumeControl]];
    }
    else {
        [useKbdMediaKeysForVolumeControl setEnabled:NO];
        [useKbdMediaKeysForVolumeControl setState:NO];
    }

	[[NSNotificationCenter defaultCenter] postNotificationName:AUDMediaKeysUseChangeNotification object:self];
}

- (IBAction)changeUseKbdMediaKeysForVolumeControl:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:[useKbdMediaKeysForVolumeControl state] forKey:AUDUseMediaKeysForVolumeControl];
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDMediaKeysUseChangeNotification object:self];
}


@end