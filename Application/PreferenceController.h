/*
 PreferenceController.h

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

#import <Cocoa/Cocoa.h>

//User preference keys
extern NSString * const AUDUISkinTheme;
extern NSString * const AUDUseAppleRemote;
extern NSString * const AUDUseMediaKeys;
extern NSString * const AUDUseMediaKeysForVolumeControl;
extern NSString * const AUDHogMode;
extern NSString * const AUDIntegerMode;
extern NSString * const AUDPreferredAudioDeviceUID;
extern NSString * const AUDPreferredAudioDeviceName;
extern NSString * const AUDSampleRateSwitchingLatency;
extern NSString * const AUDMaxSampleRateLimit;
extern NSString * const AUDMaxAudioBufferSize;
extern NSString * const AUDForceMaxIOBufferSize;
extern NSString * const AUDForceUpsamlingType;
extern NSString * const AUDSampleRateConverterModel;
extern NSString * const AUDSampleRateConverterQuality;
extern NSString * const AUDUseUTF8forM3U;
extern NSString * const AUDOutsideOpenedPlaylistPlaybackAutoStart;
extern NSString * const AUDAutosavePlaylist;

//UI elements remembrance
extern NSString * const AUDLoopModeActive;
extern NSString * const AUDShuffleModeActive;

//User default changes
extern NSString * const AUDPreferredDeviceChangeNotification;
extern NSString * const AUDAppleRemoteUseChangeNotification;
extern NSString * const AUDMediaKeysUseChangeNotification;


/*
 Max sample rate limit settings
 */
enum {
    kAUDSRCMaxSplRateNoLimit = 0,
    kAUDSRCMaxSplRate192kHz,
    kAUDSRCMaxSplRate96kHz,
    kAUDSRCMaxSplRate48kHz,
    kAUDSRCMaxSplRate44_1kHz
};

/*
 Sample Rate switching additional latency
 */
enum {
    kAUDSRCSplRateSwitchingLatencyNone = 0,
    kAUDSRCSplRateSwitchingLatency0_5s,
    kAUDSRCSplRateSwitchingLatency1s,
    kAUDSRCSplRateSwitchingLatency1_5s,
    kAUDSRCSplRateSwitchingLatency2s,
    kAUDSRCSplRateSwitchingLatency3s,
    kAUDSRCSplRateSwitchingLatency4s,
    kAUDSRCSplRateSwitchingLatency5s
};

/*
 UI Skin Themes
 */
enum {
	kAUDUISilverTheme = 0,
	kAUDUIBlackTheme = 1
};

/*
 Sample rate converter models
 */
enum {
    kAUDSRCModelAppleCoreAudio = 0,
    kAUDSRCModelSRClibSampleRate
};

/*
 Sample rate converter quality
 */
enum {
	kAUDSRCQualityLowest = 0,
	kAUDSRCQualityLow = 1,
	kAUDSRCQualityMedium = 2,
	kAUDSRCQualityHigh = 3,
	kAUDSRCQualityMax = 4
};

/*
 Sample Rate converter: force upsampling types
 */
enum {
	kAUDSRCNoForcedUpsampling = 0,
	kAUDSRCForcedOversamplingOnly = 1,
	kAUDSRCForcedMaxUpsampling = 2
};

@class AudioDeviceDescription;

@interface PreferenceController : NSWindowController {
	IBOutlet NSToolbar *preferenceTabsToolbar;
	IBOutlet NSTabView *preferenceTabs;

	IBOutlet NSTextField *preferredAudioDevice;
	IBOutlet NSTextField *activeAudioDevice;
	IBOutlet NSTextField *splRate44_1kHz;
	IBOutlet NSTextField *splRate48kHz;
	IBOutlet NSTextField *splRate88_2kHz;
	IBOutlet NSTextField *splRate96kHz;
	IBOutlet NSTextField *splRate176_4kHz;
	IBOutlet NSTextField *splRate192kHz;
	IBOutlet NSTextField *splRateHigherThan192kHz;

	IBOutlet NSWindow *preferenceChangeSheet;
	IBOutlet NSPopUpButton *audioCardsList;

	IBOutlet NSButton *hogMode;
	IBOutlet NSButton *integerMode;

	IBOutlet NSSlider *maxAudioBufferSizeSlider;
	IBOutlet NSTextField *maxAudioBufferSizeValue;
	IBOutlet NSTextField *maxTrackLengthAt44_1;
	IBOutlet NSTextField *maxTrackLengthAt192;

	IBOutlet NSMatrix *uiSkinTheme;
	IBOutlet NSButton *useAppleRemote;
    IBOutlet NSButton *useKbdMediaKeys;
	IBOutlet NSButton *useKbdMediaKeysForVolumeControl;

	NSMutableArray *audioDevicesUIDs;
	NSUInteger activeDeviceMaxSplRate;
}

- (IBAction)selectGeneralTab:(id)sender;
- (IBAction)selectAudioDeviceTab:(id)sender;
- (IBAction)selectAudioFiltersTab:(id)sender;

- (IBAction)raisePreferredDeviceChangeSheet:(id)sender;
- (IBAction)cancelPreferredDeviceChange:(id)sender;
- (IBAction)changePreferredDevice:(id)sender;

- (IBAction)changeIntegerMode:(id)sender;
- (IBAction)changeHogMode:(id)sender;
- (IBAction)changeMaxAudioBufferSize:(id)sender;
- (IBAction)changeUISkinTheme:(id)sender;
- (IBAction)changeUseAppleRemote:(id)sender;
- (IBAction)changeUseKbdMediaKeys:(id)sender;
- (IBAction)changeUseKbdMediaKeysForVolumeControl:(id)sender;

- (void)setAvailableDevicesList:(NSArray*)devicesList;
- (void)setActiveDeviceDesc:(AudioDeviceDescription*)audioDevDesc;

@end