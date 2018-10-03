/*
 AppController.m

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

#include <sys/sysctl.h>
#include <sys/types.h>
#include <CoreAudio/CoreAudio.h>

#import "Audirvana_AppDelegate.h"
#import "AppController.h"
#import "PreferenceController.h"
#import "DebugController.h"
#import "PlaylistDocument.h"
#import "CustomSliderCell.h"

@interface AppController (Notifications)
- (void)handlePlaylistTrackAppended:(NSNotification*)notification;
- (void)handlePlaylistReplacedLoadedBuffer:(NSNotification*)notification;
- (void)handleNewPlayingTrackSelected:(NSNotification*)notification;
- (void)handlePlaylistSelectionCursorChanged:(NSNotification*)notification;
- (void)handleMovePlayingTrackSelected:(NSNotification*)notification;
- (void)handleStartPlaybackNotification:(NSNotification*)notification;
- (void)handleUpdateRepeatStatus:(NSNotification*)notification;
- (void)handleUpdateShuffleStatus:(NSNotification*)notification;
- (void)handleUpdateUISkinTheme:(NSNotification*)notification;
- (void)handleUpdateAppleRemoteUse:(NSNotification*)notification;
- (void)handleUpdateMediaKeysUse:(NSNotification*)notification;
- (void)handleDeviceChange:(NSNotification*)notification;
@end

@interface AppController (OtherPrivate)
- (BOOL)startStopAppleRemoteUse:(BOOL)isToStart;
@end


@implementation AppController

+ (void)initialize
{
	int mib[] = {CTL_HW, HW_MEMSIZE};
    UInt64 ramSize;
    size_t propSize = sizeof(UInt64);
	NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];

	//Register default values for user preferences
	[defaultValues setObject:[NSNumber numberWithInt:kAUDUISilverTheme] forKey:AUDUISkinTheme];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:AUDHogMode];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:AUDIntegerMode];
	[defaultValues setObject:@"Built-in Output" forKey:AUDPreferredAudioDeviceName];
    [defaultValues setObject:[NSNumber numberWithInt:kAUDSRCMaxSplRateNoLimit] forKey:AUDMaxSampleRateLimit];
    [defaultValues setObject:[NSNumber numberWithInt:kAUDSRCSplRateSwitchingLatencyNone] forKey:AUDSampleRateSwitchingLatency];
	[defaultValues setObject:[NSNumber numberWithInt:kAUDSRCModelAppleCoreAudio] forKey:AUDSampleRateConverterModel];
	[defaultValues setObject:[NSNumber numberWithInt:kAUDSRCQualityMax] forKey:AUDSampleRateConverterQuality];
	[defaultValues setObject:[NSNumber numberWithInt:kAUDSRCNoForcedUpsampling] forKey:AUDForceUpsamlingType];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:AUDForceMaxIOBufferSize];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:AUDUseAppleRemote];
    [defaultValues setObject:[NSNumber numberWithBool:YES] forKey:AUDUseMediaKeys];
    [defaultValues setObject:[NSNumber numberWithBool:YES] forKey:AUDUseMediaKeysForVolumeControl];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:AUDUseUTF8forM3U];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:AUDOutsideOpenedPlaylistPlaybackAutoStart];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:AUDAutosavePlaylist];

    [defaultValues setObject:[NSNumber numberWithBool:NO] forKey:AUDLoopModeActive];
    [defaultValues setObject:[NSNumber numberWithBool:NO] forKey:AUDShuffleModeActive];

    //Audio Buffers should reside in RAM, thus limit buffer size to reasonable amount (Total RAM - 2.5GB)
	sysctl(mib, 2, &ramSize, &propSize, NULL, 0);

	ramSize = (ramSize >> 20) - 2560; //Leave 2.5GB to OSX to run

	//Cap default audio buffers size to 2GB
	if (ramSize < 2048) {
		//Allocate 512MB as a minimum anyway
		if (ramSize < 512) [defaultValues setObject:[NSNumber numberWithLong:256] forKey:AUDMaxAudioBufferSize];
		else [defaultValues setObject:[NSNumber numberWithLong:(NSUInteger)(ramSize/2)] forKey:AUDMaxAudioBufferSize];
	} else [defaultValues setObject:[NSNumber numberWithLong:1024] forKey:AUDMaxAudioBufferSize];

    // Register defaults for the Media Keys whitelist of apps that want to use media keys
    [defaultValues setObject:[SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers] forKey:kMediaKeyUsingBundleIdentifiersDefaultsKey];

	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
}

- (void)awakeFromNib
{
	NSAttributedString *strSplRate;
	Float64 deviceMaxSplRate;

	int uiSkinTheme = (int)[[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme];

	mSongSliderPositionGrabbed = FALSE;
    mPlaybackStarting = NO;
    mPlaybackInitiating = NO;

	[parentWindow setStyleMask:NSBorderlessWindowMask|NSMiniaturizableWindowMask];
	[parentWindow setOpaque:NO];
	if (uiSkinTheme == kAUDUISilverTheme)
		[parentWindow setBackgroundColor:[NSColor colorWithPatternImage:[NSImage imageNamed:@"Silver_PlayerWin_mainWindowBackground.png"]]];
	else
		[parentWindow setBackgroundColor:[NSColor colorWithPatternImage:[NSImage imageNamed:@"Black_PlayerWin_mainWindowBackground.png"]]];

	audioOut = [[AudioOutput alloc] initWithController:self];

	[audioOut selectDevice:[[NSUserDefaults standardUserDefaults]
										   stringForKey:AUDPreferredAudioDeviceUID]];

	//Create playlist document
	mPlaylistDoc = [[PlaylistDocument alloc] init];
	[mPlaylistDoc showWindow:nil];
	[togglePlaylistButton setState:YES];
	[(Audirvana_AppDelegate*)[[NSApplication sharedApplication] delegate] setPlaylistDocument:mPlaylistDoc];

    [(Audirvana_AppDelegate*)[[NSApplication sharedApplication] delegate] setAppController:self];

	//Display DAC info string
	NSMutableParagraphStyle* styledParagraphStyle= [[NSMutableParagraphStyle alloc] init];
    [styledParagraphStyle setAlignment:NSCenterTextAlignment];
	NSFont *greyscaleFont = [NSFont fontWithName:@"GreyscaleBasic" size:11.0f];
	if (!greyscaleFont)
		greyscaleFont = [NSFont labelFontOfSize:11.0f];
	NSShadow* shadow = [[NSShadow alloc] init];
	if (uiSkinTheme == kAUDUISilverTheme) {
		[shadow setShadowOffset:NSMakeSize(1.0f, -1.0f)];
		[shadow setShadowColor:[NSColor whiteColor]];
	}
	mSRCStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:greyscaleFont,
																	 styledParagraphStyle,
																	 [NSColor colorWithCalibratedRed:100.0f/255.0f green:100.0f/255.0f blue:100.0f/255.0f alpha:1.0f],
																  shadow
																  ,nil]
															forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																	 NSParagraphStyleAttributeName,
																	 NSForegroundColorAttributeName,
																	 NSShadowAttributeName, nil]];
	[styledParagraphStyle release];
	[shadow release];

	deviceMaxSplRate = [[[audioOut audioDevicesList] objectAtIndex:[audioOut selectedAudioDeviceIndex]]	maxSampleRate];
	if ((int)deviceMaxSplRate % 1000)
		strSplRate = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%i/%.1f D/A converter",
																 [audioOut audioDeviceCurrentPhysicalBitDepth],deviceMaxSplRate/1000]
													 attributes:mSRCStringAttributes];
	else
		strSplRate = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%i/%.0f D/A converter",
																 [audioOut audioDeviceCurrentPhysicalBitDepth],deviceMaxSplRate/1000]
													 attributes:mSRCStringAttributes];

	[currentDACSampleRate setAttributedStringValue:strSplRate];
	[strSplRate release];

	//LCD numbers font
	NSColor *lcdColor = [NSColor colorWithCalibratedRed:29.0f/350.0f green:81.0f/350.0f blue:118.0f/350.0f alpha:1.0f];
	NSFont *lcdFont = [NSFont fontWithName:@"Digital-7" size:14.0f];
	if (!lcdFont)
		lcdFont = [NSFont labelFontOfSize:12.0f];
	styledParagraphStyle = [[NSMutableParagraphStyle alloc] init];
	[styledParagraphStyle setAlignment:NSRightTextAlignment];
	mLCDStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:lcdFont,
																  lcdColor,
                                                                  [NSNumber numberWithFloat:1.0f],
																  [NSNumber numberWithFloat:0.1f],
																  [NSNumber numberWithFloat:0.1f],
																  styledParagraphStyle,
																				   nil]
														 forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																  NSForegroundColorAttributeName,
                                                                  NSKernAttributeName,
																  NSExpansionAttributeName,
																  NSObliquenessAttributeName,
																  NSParagraphStyleAttributeName, nil]];

	mLCDSelectedStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:lcdFont,
																  [NSColor colorWithCalibratedRed:29.0f/350.0f green:0.4f blue:118.0f/350.0f alpha:1.0f],
																  [NSNumber numberWithFloat:1.0f],
                                                                  [NSNumber numberWithFloat:0.1f],
																  [NSNumber numberWithFloat:0.1f],
																  styledParagraphStyle,
																  nil]
														 forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																  NSForegroundColorAttributeName,
																  NSKernAttributeName,
                                                                  NSExpansionAttributeName,
																  NSObliquenessAttributeName,
																  NSParagraphStyleAttributeName, nil]];
	[styledParagraphStyle release];
	NSAttributedString *playingTime =[[NSAttributedString alloc] initWithString:@"00:00" attributes:mLCDStringAttributes];
	[songCurrentPlayingTime setAttributedStringValue:playingTime];
	[playingTime release];

	playingTime =[[NSAttributedString alloc] initWithString:@"..:.." attributes:mLCDStringAttributes];
	[songDuration setAttributedStringValue:playingTime];
	[playingTime release];

	[songSampleRate setHidden:YES];
	[songBitDepth setHidden:YES];

	//Song position slider
	[(CustomSliderCell*)[songCurrentPlayingPosition cell] setKnobImage:[NSImage imageNamed:@"Silver_PlayerWin_timeline_dot.png"]];
	[(CustomSliderCell*)[songCurrentPlayingPosition cell] setBackgroundImage:[NSImage imageNamed:@"Silver_PlayerWin_timeline.png"]];
	[songCurrentPlayingPosition setNeedsDisplayInRect:[songCurrentPlayingPosition bounds]];

	//Song title string attribute
	NSFont *songTitleFont = [NSFont fontWithName:@"Lucida Grande Bold" size:14.0f];
	if (!songTitleFont) {
		songTitleFont = [NSFont labelFontOfSize:14.0f];
	}
	mSongTitleStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:songTitleFont,
																		lcdColor,
																		nil]
															   forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																		NSForegroundColorAttributeName, nil]];

	//Song info string attribute
	NSFont *songInfoFont = [NSFont fontWithName:@"Lucida Grande" size:12.0f];
	if (!songInfoFont) {
		songInfoFont = [NSFont labelFontOfSize:12.0f];
	}
	mSongInfoStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:songInfoFont,
																		lcdColor,
																		nil]
															   forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																		NSForegroundColorAttributeName, nil]];

	//Integer Mode is disabled at start
	[integerModeStatus setToolTip:NSLocalizedString(@"Integer Mode is OFF",@"IntegerOFF tooltip for LCD info")];
	[integerModeStatus setImage:[NSImage imageNamed:@"Silver_PlayerWin_integermode_off.png"]];

	//Handle volume control display
	[self setVolumeControl:[audioOut availableVolumeControls]];
	if (uiSkinTheme == kAUDUISilverTheme) {
		[(CustomSliderCell*)[masterDeviceVolume cell] setKnobImage:[NSImage imageNamed:@"Silver_PlayerWin_volume_knob.png"]];
		[(CustomSliderCell*)[masterDeviceVolume cell] setBackgroundImage:[NSImage imageNamed:@"Silver_PlayerWin_volume_slider.png"]];
	}
	else {
		[(CustomSliderCell*)[masterDeviceVolume cell] setKnobImage:[NSImage imageNamed:@"Black_PlayerWin_volume_knob.png"]];
		[(CustomSliderCell*)[masterDeviceVolume cell] setBackgroundImage:[NSImage imageNamed:@"Black_PlayerWin_volume_slider.png"]];
	}
	[masterDeviceVolume setNeedsDisplayInRect:[masterDeviceVolume bounds]];

	if ([audioOut availableVolumeControls])
		[self notifyDeviceVolumeChanged];

    mIsAudioMute = [audioOut isMute];

	//Dock icon display string attributes
	NSMutableParagraphStyle* dockParagraphStyle = [[NSMutableParagraphStyle alloc] init];
	[dockParagraphStyle setAlignment:NSCenterTextAlignment];
	[dockParagraphStyle setParagraphSpacingBefore:0.0f];
	[dockParagraphStyle setMinimumLineHeight:32.0f];
	[dockParagraphStyle setMaximumLineHeight:32.0f];
	NSFont *futuraFont = [NSFont fontWithName:@"Futura" size:30.0f];
	if (!futuraFont)
		futuraFont = [NSFont labelFontOfSize:30.0f];
	mDockStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:futuraFont,
																   dockParagraphStyle,
																   [NSColor lightGrayColor], nil]
														  forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																   NSParagraphStyleAttributeName,
																   NSForegroundColorAttributeName,nil]];
	[dockParagraphStyle release];


	//Start Apple remote handling
	[[HIDRemote sharedHIDRemote] setUnusedButtonCodes:[NSArray arrayWithObjects:
													   [NSNumber numberWithInt:(int)kHIDRemoteButtonCodeUpHold],
													   [NSNumber numberWithInt:(int)kHIDRemoteButtonCodeDownHold],
													   [NSNumber numberWithInt:(int)kHIDRemoteButtonCodeCenterHold],
													   [NSNumber numberWithInt:(int)kHIDRemoteButtonCodeMenu],
													   [NSNumber numberWithInt:(int)kHIDRemoteButtonCodeMenuHold],
													   [NSNumber numberWithInt:(int)kHIDRemoteButtonCodePlayHold],
													   nil]];
	if ([[NSUserDefaults standardUserDefaults] boolForKey:AUDUseAppleRemote])
		[self startStopAppleRemoteUse:YES];

    //Start media keys handling
    if ([[NSUserDefaults standardUserDefaults] boolForKey:AUDUseMediaKeys]) {
        mKeyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];
        if([SPMediaKeyTap usesGlobalMediaKeyTap]) {
            [mKeyTap startWatchingMediaKeys];
            [mKeyTap setInterceptVolumeControl:([[NSUserDefaults standardUserDefaults] boolForKey:AUDUseMediaKeysForVolumeControl]
                                                && [audioOut availableVolumeControls])];
        }
    }
    else mKeyTap = nil;

	//Add playlist changes listeners
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
   	[nc addObserver:self selector:@selector(handlePlaylistTrackAppended:)
			   name:AUDPlaylistItemAppendedtoPlaylistNotification object:nil];
	[nc addObserver:self selector:@selector(handlePlaylistReplacedLoadedBuffer:)
			   name:AUDPlaylistItemInsertedAtLoadedPositionNotification object:nil];
	[nc addObserver:self selector:@selector(handleNewPlayingTrackSelected:)
			   name:AUDPlaylistSelectPlayingTrackNotification object:nil];
	[nc addObserver:self selector:@selector(handlePlaylistSelectionCursorChanged:)
			   name:AUDPlaylistSelectionCursorChangedNotification object:nil];
	[nc addObserver:self selector:@selector(handleMovePlayingTrackSelected:)
			   name:AUDPlaylistMovePlayingTrackNotification object:nil];
	[nc addObserver:self selector:@selector(handleStartPlaybackNotification:)
			   name:AUDStartPlaybackNotification object:nil];
	[nc addObserver:self selector:@selector(handleUpdateRepeatStatus:)
			   name:AUDTogglePlaylistRepeat object:nil];
	[nc addObserver:self selector:@selector(handleUpdateShuffleStatus:)
			   name:AUDTogglePlaylistShuffle object:nil];
	//And UI pref changes
	[nc addObserver:self selector:@selector(handleDeviceChange:)
			   name:AUDPreferredDeviceChangeNotification object:nil];
	[nc addObserver:self selector:@selector(handleUpdateUISkinTheme:)
			   name:AUDUISkinTheme object:nil];
	[nc addObserver:self selector:@selector(handleUpdateAppleRemoteUse:)
			   name:AUDAppleRemoteUseChangeNotification object:nil];
	[nc addObserver:self selector:@selector(handleUpdateMediaKeysUse:)
			   name:AUDMediaKeysUseChangeNotification object:nil];

	if (uiSkinTheme != kAUDUISilverTheme)
		[self handleUpdateUISkinTheme:nil];
}

- (void)dealloc
{
	[mSRCStringAttributes release];
	[mDockStringAttributes release];
	[mLCDStringAttributes release];
	[mLCDSelectedStringAttributes release];
	[mSongTitleStringAttributes release];
	[mSongInfoStringAttributes release];
	[self startStopAppleRemoteUse:NO];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (preferenceController) [preferenceController release];
	if (debugController) [debugController release];
	if (mPlaylistDoc) [mPlaylistDoc release];
	[super dealloc];
}

#pragma mark Panel show functions

- (IBAction)showPreferencePanel:(id)sender
{
	if (!preferenceController) {
		preferenceController = [[PreferenceController alloc] init];
	}
	[preferenceController showWindow:sender];
	[preferenceController setAvailableDevicesList:audioOut.audioDevicesList];
	[preferenceController setActiveDeviceDesc:[[audioOut audioDevicesList] objectAtIndex:audioOut.selectedAudioDeviceIndex]];
}

- (IBAction)showDebugPanel:(id)sender
{
	if (!debugController) {
		debugController = [[DebugController alloc] init];
	}
	if (![debugController window]) {
		[debugController release];
		debugController = [[DebugController alloc] init];
	}
	[debugController showWindow:sender];
	[debugController setInfoText:[audioOut description]];
}

- (IBAction)openDonationPage:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=6PZANKDHSN358"]];
}

- (IBAction)togglePlaylistDrawer: (id)sender
{
	NSWindow *docWindow = [mPlaylistDoc window];

	if ([docWindow isVisible]) {
		[docWindow setIsVisible:FALSE];
		[togglePlaylistButton setState:NO];
	}
	else {
		[docWindow setIsVisible:TRUE];
		[togglePlaylistButton setState:YES];
	}
}

#pragma mark User actions handlers

- (void)startPlaying
{
	NSError *err;

	if ([audioOut isPlaying]) return;

	if ([mPlaylistDoc playlistCount] <= 0) return;

	NSAttributedString *initString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Initializing audio device...",@"Initializing Audio Device info in LCD title line")
                                                                     attributes:mSongInfoStringAttributes];
	[songTitle setAttributedStringValue:initString];
	[initString release];

	//Attempt to select the preferred audio device
	//Repeat this attempt each time playback is initiated to cope with hot plugging
	[audioOut selectDevice:[[NSUserDefaults standardUserDefaults]
							stringForKey:AUDPreferredAudioDeviceUID]];

	//Set loadedTrackindex to previous position, as [mPlaylistDoc nextFile]
	//will try to load the next one
	//[mPlaylistDoc setLoadedTrackIndex:[mPlaylistDoc loadedTrackIndex]-1];

	mFirstFileToPlay = [mPlaylistDoc firstFileWhenStartingPlayback];//[mPlaylistDoc nextFile];
	if (mFirstFileToPlay == nil) {
        NSDictionary *errDict;
        errDict = [NSDictionary dictionaryWithObject:NSLocalizedString(@"Error: unable to load first track",@"Unable to load first track error message")
                                              forKey:NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:NSOSStatusErrorDomain code:'erld' userInfo:errDict];

        [self abortPlayingStart:err];
        return;
    }

	if (![audioOut initiatePlayback:&err]) {
		[self abortPlayingStart:err];
		 return;
	}

    mPlaybackInitiating = YES;
}

- (void)startPlayingPhase2
{
	[audioOut loadFile:mFirstFileToPlay toBuffer:0];
	[audioOut setPlayingBuffer:0];

    mPlaybackStarting = YES;

	//Also load second buffer
	//First check if a next chunk from the file shall be loaded
	if (![audioOut loadNextChunk:1]) {
		NSURL *fileToPlay = [mPlaylistDoc nextFile];
		if (fileToPlay) {
			[audioOut loadFile:fileToPlay toBuffer:1];
		}
	}
}

-(void)startPlayingPhase3
{
    NSError *err;

    if (![audioOut startPlayback:&err]) {
		[self abortPlayingStart:err];
		return;
	}

    [self updateCurrentPlayingTime];
	if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme] == kAUDUISilverTheme) {
		[playPauseButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_pause_on.png"]];
		[playPauseButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_pause_pressed.png"]];
	}
	else {
		[playPauseButton setImage:[NSImage imageNamed:@"Black_PlayerWin_pause_on.png"]];
		[playPauseButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_pause_pressed.png"]];
	}
	[songCurrentPlayingPosition setEnabled:TRUE];
	[songDuration setEnabled:TRUE];
	[songCurrentPlayingTime setEnabled:TRUE];

    mPlaybackInitiating = NO;
}

- (void)abortPlayingStart:(NSError*)error
{
	Float64 deviceMaxSplRate;
	NSAttributedString *errorString;


    mPlaybackInitiating = NO;

	[audioOut closeBuffers];
	if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme] == kAUDUISilverTheme) {
		[playPauseButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_play_on.png"]];
		[playPauseButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_play_pressed.png"]];
	}
	else {
		[playPauseButton setImage:[NSImage imageNamed:@"Black_PlayerWin_play_on.png"]];
		[playPauseButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_play_pressed.png"]];
	}

	deviceMaxSplRate = [[[audioOut audioDevicesList] objectAtIndex:[audioOut selectedAudioDeviceIndex]]	maxSampleRate];
	[self updateMetadataDisplay:@"" album:@"" artist:@"" composer:@""
					 coverImage:nil duration:0.0
					integerMode:[audioOut isIntegerModeOn]
					   bitDepth:[audioOut audioDeviceCurrentPhysicalBitDepth]
				 fileSampleRate:deviceMaxSplRate
			  playingSampleRate:deviceMaxSplRate];

	[songCurrentPlayingPosition setEnabled:FALSE];
	[songDuration setEnabled:FALSE];
	NSAttributedString *playingTime =[[NSAttributedString alloc] initWithString:@"..:.." attributes:mLCDStringAttributes];
	[songDuration setAttributedStringValue:playingTime];
	[playingTime release];
	[songCurrentPlayingTime setEnabled:FALSE];

	playingTime =[[NSAttributedString alloc] initWithString:@"00:00" attributes:mLCDStringAttributes];
	[songCurrentPlayingTime setAttributedStringValue:playingTime];
	[playingTime release];

	[songSampleRate setHidden:YES];
	[songBitDepth setHidden:YES];

	[mPlaylistDoc resetPlayingPosToStart];

	UInt32 errCode= (UInt32)[error code];
    if (errCode) {
        errorString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ OSError=%.4s",[error localizedDescription],&errCode]
                                                      attributes:mSongInfoStringAttributes];
    } else {
        errorString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@",[error localizedDescription]]
                                                      attributes:mSongInfoStringAttributes];
    }
	[songTitle setAttributedStringValue:errorString];
	[errorString release];
}

-(IBAction)playPause: (id)sender
{
	if (![audioOut isPlaying]) {
		if ([audioOut deviceInitializationStatus] == kAudioPlaybackNotInStartingPhase)
			[self startPlaying];
	}
	else {
			if ([audioOut isPaused]) {
				//Un-Pause
				[audioOut pause:NO];
				if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme] == kAUDUISilverTheme) {
					[playPauseButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_pause_on.png"]];
					[playPauseButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_pause_pressed.png"]];
				}
				else {
					[playPauseButton setImage:[NSImage imageNamed:@"Black_PlayerWin_pause_on.png"]];
					[playPauseButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_pause_pressed.png"]];
				}
			} else {
				//Pause
				[audioOut pause:YES];
				if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme] == kAUDUISilverTheme) {
					[playPauseButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_play_on.png"]];
					[playPauseButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_play_pressed.png"]];
				}
				else {
					[playPauseButton setImage:[NSImage imageNamed:@"Black_PlayerWin_play_on.png"]];
					[playPauseButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_play_pressed.png"]];
				}
			}
	}
}

- (IBAction)stop: (id)sender
{
	if ([audioOut isPlaying]) {
		[audioOut stop];
		[audioOut closeBuffers];
		if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme] == kAUDUISilverTheme) {
			[playPauseButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_play_on.png"]];
			[playPauseButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_play_pressed.png"]];
		}
		else {
			[playPauseButton setImage:[NSImage imageNamed:@"Black_PlayerWin_play_on.png"]];
			[playPauseButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_play_pressed.png"]];
		}

		[songCurrentPlayingPosition setEnabled:FALSE];
		[songDuration setEnabled:FALSE];
		NSAttributedString *playingTime =[[NSAttributedString alloc] initWithString:@"..:.." attributes:mLCDStringAttributes];
		[songDuration setAttributedStringValue:playingTime];
		[playingTime release];
		[songCurrentPlayingTime setEnabled:FALSE];
		playingTime =[[NSAttributedString alloc] initWithString:@"00:00" attributes:mLCDStringAttributes];
		[songCurrentPlayingTime setAttributedStringValue:playingTime];
		[playingTime release];
		[self resetLoadStatus:NO];

		[songSampleRate setHidden:YES];
		[songBitDepth setHidden:YES];

		NSImage* dockIcon = [[NSImage alloc] initWithSize:NSMakeSize(128,128)];
		[dockIcon lockFocus];
		if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme] == kAUDUISilverTheme)
			[[NSImage imageNamed:@"NSApplicationIcon"] dissolveToPoint:NSZeroPoint fraction:1.0f];
		else
			[[NSImage imageNamed:@"AudirvanaBlackAppIcon"] dissolveToPoint:NSZeroPoint fraction:1.0f];
		[dockIcon unlockFocus];
		[NSApp setApplicationIconImage:dockIcon];
		[dockIcon release];

		[mPlaylistDoc resetPlayingPosToStart];
	}
}

- (IBAction)positionSliderMoved: (id)sender
{
	NSAttributedString *playingTime =[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%02i:%02i",
																				 (int)(((long long)[songCurrentPlayingPosition doubleValue])/[audioOut audioDeviceCurrentNominalSampleRate])/60,
																				 (int)(((long long)[songCurrentPlayingPosition doubleValue])/[audioOut audioDeviceCurrentNominalSampleRate])%60]
																	 attributes:mLCDSelectedStringAttributes];
	[songCurrentPlayingTime setAttributedStringValue:playingTime];
	[playingTime release];

	if (!mSongSliderPositionGrabbed) {
		mSongSliderPositionGrabbed = TRUE;
		[songCurrentPlayingTime setTextColor:[NSColor blueColor]];
	}

	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(seekPosition:) object:sender];
	[self performSelector:@selector(seekPosition:)
			   withObject:sender afterDelay:0];
}

- (void)seekPosition: (id)sender
{
	//Switch back to normal display color
	NSAttributedString *playingTime =[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%02i:%02i",
																				 (int)(((long long)[songCurrentPlayingPosition doubleValue])/[audioOut audioDeviceCurrentNominalSampleRate])/60,
																				 (int)(((long long)[songCurrentPlayingPosition doubleValue])/[audioOut audioDeviceCurrentNominalSampleRate])%60]
																	 attributes:mLCDStringAttributes];
	[songCurrentPlayingTime setAttributedStringValue:playingTime];
	[playingTime release];

	mSongSliderPositionGrabbed = FALSE;
	//[songCurrentPlayingTime setTextColor:[NSColor colorWithCalibratedRed:29.0f/255.0f green:81.0f/255.0f blue:118.0f/255.0f alpha:1.0f]];

	if([audioOut isPlaying]) {
		[audioOut seek:(UInt64)[songCurrentPlayingPosition doubleValue]];
	}
}

- (IBAction)seekPrevious: (id)sender
{
	if ([audioOut isPlaying]) {
		int oldPlayingBuffer = [audioOut playingBuffer];
		int nonPlayingBuffer = oldPlayingBuffer==0?1:0;
		NSInteger currentPlaylistPlayingPos = [mPlaylistDoc playingTrackIndex];
        NSInteger previousPlaylistPlayingPos = [mPlaylistDoc shuffledIndexFromNonShuffled:
                                                [mPlaylistDoc nonShuffledIndexFromShuffled:
                                                 currentPlaylistPlayingPos] -1];
		bool isPaused = [audioOut isPaused];

		//After trask first 2s => go back to track beginning
		//Except if resulted from user selecting directly track in playlist (case where sender is nil)
		if (sender && ([songCurrentPlayingPosition doubleValue] > 2*[audioOut audioDeviceCurrentNominalSampleRate])) {
			[audioOut seek:0];
            [self updateCurrentPlayingTime];
			return;
		}

		//In first track ?
		if ([mPlaylistDoc nonShuffledIndexFromShuffled:currentPlaylistPlayingPos] == 0)
			return;

		if (!isPaused) [audioOut pause:YES];
		[audioOut resetWillChangePlayingBuffer];
		[mPlaylistDoc setPlayingTrackIndex:previousPlaylistPlayingPos];
		[audioOut closeBuffer:nonPlayingBuffer];
		[audioOut loadFile:[mPlaylistDoc fileAtIndex:previousPlaylistPlayingPos] toBuffer:nonPlayingBuffer];
		[audioOut setPlayingBuffer:nonPlayingBuffer];
		[audioOut seek:0];
		[self updateCurrentPlayingTime];

		if (![audioOut bufferContainsWholeTrack:oldPlayingBuffer] || ![audioOut bufferContainsWholeTrack:nonPlayingBuffer]) {
			//Previous track is not loaded completely or the old playing buffer was only a portion of the next track
			//Reload both buffers
			[mPlaylistDoc setLoadedTrackIndex:previousPlaylistPlayingPos];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:previousPlaylistPlayingPos]];
			[audioOut closeBuffer:oldPlayingBuffer];
			[self fillBufferWithNext:oldPlayingBuffer];
		}
		else {
			[mPlaylistDoc setLoadedTrackIndex:currentPlaylistPlayingPos];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:currentPlaylistPlayingPos]];
		}
		[mPlaylistDoc refreshTableDisplay];
		if (!isPaused) [audioOut pause:NO];
	} else {
		if ([mPlaylistDoc nonShuffledIndexFromShuffled:[mPlaylistDoc playingTrackIndex]] > 0)
        {
            NSInteger previousPlaylistPlayingPos = [mPlaylistDoc shuffledIndexFromNonShuffled:
                                                    [mPlaylistDoc nonShuffledIndexFromShuffled:
                                                     [mPlaylistDoc playingTrackIndex]] -1];
            [mPlaylistDoc setPlayingTrackIndex:previousPlaylistPlayingPos];
            [mPlaylistDoc setLoadedTrackIndex:previousPlaylistPlayingPos];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:previousPlaylistPlayingPos]];
            [mPlaylistDoc refreshTableDisplay];
        }
    }
}

- (IBAction)seekNext: (id)sender
{
	if ([audioOut isPlaying]) {
		NSURL *fileToPlay;
		BOOL fileLoadSuccess;
		int oldPlayingBuffer = [audioOut playingBuffer];
		bool isPaused = [audioOut isPaused];

		if ([audioOut areBothBuffersFromSameFile]) {
			//Inside split loaded file
			int oldLoadedBuffer = oldPlayingBuffer==0?1:0;
			NSInteger currentPlaylistPlayingPos = [mPlaylistDoc playingTrackIndex];

			[mPlaylistDoc setLoadedTrackIndex:currentPlaylistPlayingPos];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:currentPlaylistPlayingPos]];
			fileToPlay = [mPlaylistDoc nextFile];
			if (!fileToPlay) return;

			if (!isPaused) [audioOut pause:YES];
			[audioOut resetWillChangePlayingBuffer];

			//Load non playing buffer
			[audioOut closeBuffer:oldLoadedBuffer];
			fileLoadSuccess = [audioOut loadFile:fileToPlay toBuffer:oldLoadedBuffer];
			while (!fileLoadSuccess && (fileToPlay = [mPlaylistDoc nextFile])) {
				fileLoadSuccess = [audioOut loadFile:fileToPlay toBuffer:oldLoadedBuffer];
			}

			[audioOut setPlayingBuffer:oldLoadedBuffer];
			[mPlaylistDoc setPlayingTrackIndex:[mPlaylistDoc shuffledIndexFromNonShuffled:
                                                ([mPlaylistDoc nonShuffledIndexFromShuffled:currentPlaylistPlayingPos]+1)]];
			[audioOut seek:0];
			[self updateCurrentPlayingTime];
			if (!isPaused) [audioOut pause:NO];

			//Load old playing buffer
			[audioOut closeBuffer:oldPlayingBuffer];
			if (![self fillBufferWithNext:oldPlayingBuffer]) {
                //Also remove this buffer from the loading progress bar if no other track after
                [self resetLoadStatus:YES];
            }
		}
		else {
			//In last track ?
			if ([audioOut isAudioBuffersEmpty:oldPlayingBuffer==0?1:0])
				return;

			if (!isPaused) [audioOut pause:YES];
			[audioOut resetWillChangePlayingBuffer];
			[mPlaylistDoc setPlayingTrackIndex:[mPlaylistDoc loadedTrackIndex]];
			[audioOut setPlayingBuffer:oldPlayingBuffer==0?1:0];
			[audioOut seek:0];
			[self updateCurrentPlayingTime];
			[mPlaylistDoc refreshTableDisplay];
			if (!isPaused) [audioOut pause:NO];

			//Then load next track to play
			[audioOut closeBuffer:oldPlayingBuffer];
			if (![self fillBufferWithNext:oldPlayingBuffer]) {
                //Also remove this buffer from the loading progress bar if no other track after
                [self resetLoadStatus:YES];
            }
		}
	} else {
		if ([mPlaylistDoc nonShuffledIndexFromShuffled:[mPlaylistDoc playingTrackIndex]]
            < ((NSInteger)[mPlaylistDoc playlistCount]-1))
        {
            NSInteger nextPlaylistPlayingPos = [mPlaylistDoc shuffledIndexFromNonShuffled:
                                                    [mPlaylistDoc nonShuffledIndexFromShuffled:
                                                     [mPlaylistDoc playingTrackIndex]] +1];
            [mPlaylistDoc setPlayingTrackIndex:nextPlaylistPlayingPos];
            [mPlaylistDoc setLoadedTrackIndex:nextPlaylistPlayingPos];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:nextPlaylistPlayingPos]];
            [mPlaylistDoc refreshTableDisplay];
        }
    }
}

- (IBAction)toggleRepeat:(id)sender
{
	[mPlaylistDoc setIsRepeating:![mPlaylistDoc isRepeating]];
}

- (IBAction)toggleShuffle:(id)sender
{
    [mPlaylistDoc setIsShuffling:![mPlaylistDoc isShuffling]];
}

- (IBAction)setMasterVolume:(id)sender
{
	[audioOut setMasterVolumeScalar:[masterDeviceVolume floatValue] forType:[audioOut availableVolumeControls]&kAudioVolumePhysicalControl
	? kAudioVolumePhysicalControl:kAudioVolumeVirtualControl];
}

#pragma mark Menu Items

- (IBAction)prunePlaylist:(id)sender
{
	[mPlaylistDoc prunePlaylistItems:NO];
}

- (IBAction)deletePlaylistItem:(id)sender
{
	[mPlaylistDoc deleteSelectedPlaylistItems];
}


- (IBAction)performLoadPlaylist:(id)sender
{
	NSOpenPanel *openPlaylistPanel = [NSOpenPanel openPanel];

	[openPlaylistPanel setCanChooseDirectories:NO];
	[openPlaylistPanel setAllowsMultipleSelection:NO];
	if ([openPlaylistPanel runModalForTypes:[NSArray arrayWithObjects:@"m3u",@"m3u8",nil]] == NSOKButton) {
		[mPlaylistDoc loadPlaylist:[openPlaylistPanel URL] appendToExisting:NO];
	}
}

- (IBAction)performSavePlaylistAs:(id)sender
{
	NSSavePanel *savePlaylistPanel = [NSSavePanel savePanel];

	[savePlaylistPanel setCanCreateDirectories:YES];
	[savePlaylistPanel setAllowedFileTypes:[NSArray arrayWithObjects:@"m3u",@"m3u8",nil]];
	[savePlaylistPanel setAllowsOtherFileTypes:NO];
	if ([savePlaylistPanel runModal] == NSOKButton) {
		NSURL *savedFile = [savePlaylistPanel URL];
		if ([[savedFile pathExtension] caseInsensitiveCompare:@"m3u8"] == NSOrderedSame)
			 [mPlaylistDoc savePlaylist:[savePlaylistPanel URL] format:kAudioPlaylistM3U8];
		else
			 [mPlaylistDoc savePlaylist:[savePlaylistPanel URL] format:kAudioPlaylistM3U];
	}
}

- (IBAction)performSavePlaylist:(id)sender
{
	NSURL *currentPlaylistFile = [[mPlaylistDoc window] representedURL];
	if (currentPlaylistFile) {
		if ([[currentPlaylistFile pathExtension] caseInsensitiveCompare:@"m3u8"] == NSOrderedSame)
			[mPlaylistDoc savePlaylist:currentPlaylistFile format:kAudioPlaylistM3U8];
		else
			[mPlaylistDoc savePlaylist:currentPlaylistFile format:kAudioPlaylistM3U];
	}
}

/*Validation of menu items */
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	SEL theAction = [anItem action];

	if (theAction == @selector(performSavePlaylist:))
		return ([[mPlaylistDoc window] representedURL] && [[mPlaylistDoc window] isDocumentEdited]);
	else if (theAction == @selector(performSavePlaylistAs:))
		return ([mPlaylistDoc playlistCount] > 0);
	else
		return YES;
}

#pragma mark AppleRemote handler

- (BOOL)startStopAppleRemoteUse:(BOOL)isToStart
{
	if (![HIDRemote isCandelairInstallationRequiredForRemoteMode:kHIDRemoteModeExclusiveAuto]) {
		if (isToStart) {
			[[HIDRemote sharedHIDRemote] setDelegate:self];
			return [[HIDRemote sharedHIDRemote] startRemoteControl:kHIDRemoteModeExclusive];
		} else {
			[[HIDRemote sharedHIDRemote] stopRemoteControl];
			[[HIDRemote sharedHIDRemote] setDelegate:nil];
			return TRUE;
		}
	}

	return FALSE;
}

- (void)hidRemote:(HIDRemote *)hidRemote eventWithButton:(HIDRemoteButtonCode)buttonCode isPressed:(BOOL)isPressed fromHardwareWithAttributes:(NSMutableDictionary *)attributes
{
	if (isPressed) {
		switch (buttonCode)
		{
			case kHIDRemoteButtonCodeLeftHold:
				//Seek backward by 10s
				if([audioOut isPlaying]) {
					[audioOut seek:(UInt64)[songCurrentPlayingPosition doubleValue]
					 - [audioOut audioDeviceCurrentNominalSampleRate]*10];
				}
				break;
			case kHIDRemoteButtonCodeRightHold:
				//Seek forward by 10s
				if([audioOut isPlaying]) {
					[audioOut seek:(UInt64)[songCurrentPlayingPosition doubleValue]
					 + [audioOut audioDeviceCurrentNominalSampleRate]*10];
				}
				break;
			default:
				break;
		}
	}
	else {
		//Upon button release
		switch (buttonCode)
		{
			case kHIDRemoteButtonCodeLeft:
				[self seekPrevious:self];
				break;
			case kHIDRemoteButtonCodeRight:
				[self seekNext:self];
				break;
			case kHIDRemoteButtonCodeCenter:
			case kHIDRemoteButtonCodePlay:
				[self playPause:self];
				break;
			case kHIDRemoteButtonCodeUp:
            {
                bool availVolCtrl = [audioOut availableVolumeControls];
                if (availVolCtrl) {
                    [audioOut setMasterVolumeScalar:[masterDeviceVolume floatValue]+(Float32)0.1 forType:availVolCtrl&kAudioVolumePhysicalControl
                     ? kAudioVolumePhysicalControl:kAudioVolumeVirtualControl];
                }
            }
				break;
			case kHIDRemoteButtonCodeDown:
            {
                bool availVolCtrl = [audioOut availableVolumeControls];
                if (availVolCtrl) {
                    [audioOut setMasterVolumeScalar:[masterDeviceVolume floatValue]-(Float32)0.1 forType:[audioOut availableVolumeControls]&kAudioVolumePhysicalControl
                     ? kAudioVolumePhysicalControl:kAudioVolumeVirtualControl];
                }
            }
				break;
			case kHIDRemoteButtonCodeMenu:
				[self togglePlaylistDrawer:nil];
				break;

			default:
				break;
		}
	}

}

-(void)mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event;
{
	NSAssert([event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");

	int keyCode = (([event data1] & 0xFFFF0000) >> 16);
	int keyFlags = ([event data1] & 0x0000FFFF);
	BOOL keyIsPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;

	if (keyIsPressed) {
		switch (keyCode) {
			case NX_KEYTYPE_PLAY:
                [self playPause:self];
				break;

			case NX_KEYTYPE_FAST:
                [self seekNext:self];
				break;

			case NX_KEYTYPE_REWIND:
                [self seekPrevious:self];
				break;

            case NX_KEYTYPE_SOUND_UP:
            {
                bool availVolCtrl = [audioOut availableVolumeControls];
                if (mIsAudioMute) {
                    [audioOut setMute:NO];
                    mIsAudioMute = NO;
                }
                if (availVolCtrl) {
                    [audioOut setMasterVolumeScalar:[masterDeviceVolume floatValue]+(Float32)0.1 forType:[audioOut availableVolumeControls]&kAudioVolumePhysicalControl
                     ? kAudioVolumePhysicalControl:kAudioVolumeVirtualControl];
                }
            }
                break;

            case NX_KEYTYPE_SOUND_DOWN:
            {
                bool availVolCtrl = [audioOut availableVolumeControls];
                if (mIsAudioMute) {
                    [audioOut setMute:NO];
                    mIsAudioMute = NO;
                }
                if (availVolCtrl) {
                    [audioOut setMasterVolumeScalar:[masterDeviceVolume floatValue]-(Float32)0.1 forType:[audioOut availableVolumeControls]&kAudioVolumePhysicalControl
                     ? kAudioVolumePhysicalControl:kAudioVolumeVirtualControl];
                }
            }
                break;

            case NX_KEYTYPE_MUTE:
                if ([audioOut availableVolumeControls]) {
                    [audioOut setMute:!mIsAudioMute];
                    mIsAudioMute = !mIsAudioMute;
                }
                break;

			default:
				break;
                // More cases defined in hidsystem/ev_keymap.h
		}
	}
}

#pragma mark Display update functions

- (void)setVolumeControl:(UInt32)availVolumeControls
{
	NSAttributedString *volumeControlText;
	NSMutableParagraphStyle* styledParagraphStyle= [[NSMutableParagraphStyle alloc] init];
    [styledParagraphStyle setAlignment:NSCenterTextAlignment];
	NSFont *greyscaleFont = [NSFont fontWithName:@"GreyscaleBasic" size:8.5f];
	if (!greyscaleFont)
		greyscaleFont = [NSFont labelFontOfSize:8.5f];
	NSColor *textColor;
	if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme] == kAUDUISilverTheme)
		textColor = [NSColor colorWithCalibratedRed:100.0f/255.0f green:100.0f/255.0f blue:100.0f/255.0f alpha:1.0f];
	else
		textColor = [NSColor colorWithCalibratedRed:86.0f/255.0f green:97.0f/255.0f blue:105.0f/255.0f alpha:1.0f];
	NSDictionary *volumeStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:greyscaleFont,
																  styledParagraphStyle,
																  textColor
																  ,nil]
														 forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																  NSParagraphStyleAttributeName,
																  NSForegroundColorAttributeName, nil]];
	[styledParagraphStyle release];

	styledParagraphStyle= [[NSMutableParagraphStyle alloc] init];
    [styledParagraphStyle setAlignment:NSLeftTextAlignment];
	greyscaleFont = [NSFont fontWithName:@"GreyscaleBasic" size:14.0f];
	if (!greyscaleFont)
		greyscaleFont = [NSFont labelFontOfSize:14.0f];
	NSDictionary *plusMinusStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:greyscaleFont,
																				  styledParagraphStyle,
																				  textColor
																				  ,nil]
																		 forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																				  NSParagraphStyleAttributeName,
																				  NSForegroundColorAttributeName, nil]];
	[styledParagraphStyle release];


	if (availVolumeControls & kAudioVolumePhysicalControl) {
		[masterDeviceVolume setHidden:NO];
		[masterDeviceVolumeText setHidden:NO];
		[masterDeviceVolumeValue setHidden:NO];
		[masterDeviceVolumePlus setHidden:NO];
		[masterDeviceVolumeMinus setHidden:NO];
		volumeControlText = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"MASTER\nVOLUME",@"Master Volume info under volume slider")
                                                            attributes:volumeStringAttributes];
		[masterDeviceVolumeText setAttributedStringValue:volumeControlText];
		[volumeControlText release];
		volumeControlText = [[NSAttributedString alloc] initWithString:@"+" attributes:plusMinusStringAttributes];
		[masterDeviceVolumePlus setAttributedStringValue:volumeControlText];
		[volumeControlText release];
		volumeControlText = [[NSAttributedString alloc] initWithString:@"-" attributes:plusMinusStringAttributes];
		[masterDeviceVolumeMinus setAttributedStringValue:volumeControlText];
		[volumeControlText release];

		[self notifyDeviceVolumeChanged];
	} else if (availVolumeControls & kAudioVolumeVirtualControl) {
		[masterDeviceVolume setHidden:NO];
		[masterDeviceVolumeText setHidden:NO];
		[masterDeviceVolumeValue setHidden:NO];
		[masterDeviceVolumePlus setHidden:NO];
		[masterDeviceVolumeMinus setHidden:NO];
		volumeControlText = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"DIGITAL\nVOLUME",@"Digital Volume info under volume slider")
                                                            attributes:volumeStringAttributes];
		[masterDeviceVolumeText setAttributedStringValue:volumeControlText];
		[volumeControlText release];
		volumeControlText = [[NSAttributedString alloc] initWithString:@"+" attributes:plusMinusStringAttributes];
		[masterDeviceVolumePlus setAttributedStringValue:volumeControlText];
		[volumeControlText release];
		volumeControlText = [[NSAttributedString alloc] initWithString:@"-" attributes:plusMinusStringAttributes];
		[masterDeviceVolumeMinus setAttributedStringValue:volumeControlText];
		[volumeControlText release];

		[self notifyDeviceVolumeChanged];
	} else {
		[masterDeviceVolumeText setHidden:YES];
		[masterDeviceVolume setHidden:YES];
		[masterDeviceVolumeValue setHidden:YES];
		[masterDeviceVolumePlus setHidden:YES];
		[masterDeviceVolumeMinus setHidden:YES];
	}

	[volumeStringAttributes release];
	[plusMinusStringAttributes release];
}

- (void)updateMetadataDisplay:(NSString*)title album:(NSString*)album_name
					   artist:(NSString*)artist_name
					 composer:(NSString*)composer_name
				   coverImage:(NSImage*)cover_image
					 duration:(Float64)duration_seconds
				  integerMode:(BOOL)isIntegerModeOn
					 bitDepth:(UInt32)bitsPerFrame
			   fileSampleRate:(Float64)fileSampleRateInHz
			playingSampleRate:(Float64)playingSampleRateInHz
{
	NSAttributedString* strSplRate, *songInfoStr;
	NSString *overWord;

	songInfoStr = [[NSAttributedString alloc] initWithString:title?title:@"" attributes:mSongTitleStringAttributes];
	[songTitle setAttributedStringValue:songInfoStr];
	[songInfoStr release];

	songInfoStr = [[NSAttributedString alloc] initWithString:album_name?album_name:@"" attributes:mSongInfoStringAttributes];
	[songAlbum setAttributedStringValue:songInfoStr];
	[songInfoStr release];

	songInfoStr = [[NSAttributedString alloc] initWithString:artist_name?artist_name:@"" attributes:mSongInfoStringAttributes];
	[songArtist setAttributedStringValue:songInfoStr];
	[songInfoStr release];

	songInfoStr = [[NSAttributedString alloc] initWithString:composer_name?composer_name:@"" attributes:mSongInfoStringAttributes];
	[songComposer setAttributedStringValue:songInfoStr];
	[songInfoStr release];

	[songCoverImage setImage:cover_image];
	NSAttributedString *lcdString =[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%02i:%02i",(int)duration_seconds/60,
																				 (int)duration_seconds%60]
																	 attributes:mLCDStringAttributes];
	[songDuration setAttributedStringValue:lcdString];
	[lcdString release];

	if (isIntegerModeOn) {
		[integerModeStatus setToolTip:NSLocalizedString(@"Integer Mode is ON",@"IntegerON tooltip for LCD info")];
		[integerModeStatus setImage:[NSImage imageNamed:@"Silver_PlayerWin_integermode_on"]];
	}
	else {
		[integerModeStatus setToolTip:NSLocalizedString(@"Integer Mode is OFF",@"IntegerOFF tooltip for LCD info")];
		[integerModeStatus setImage:[NSImage imageNamed:@"Silver_PlayerWin_integermode_off"]];
	}


	if ((int)fileSampleRateInHz % 1000)
		lcdString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%.1f kHz",fileSampleRateInHz/1000]
													attributes:mLCDStringAttributes];
	else
		lcdString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%.0f kHz",fileSampleRateInHz/1000]
													attributes:mLCDStringAttributes];
	[songSampleRate setAttributedStringValue:lcdString];
	[lcdString release];
	[songSampleRate setHidden:NO];

	lcdString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%i bit",bitsPerFrame]
												attributes:mLCDStringAttributes];
	[songBitDepth setAttributedStringValue:lcdString];
	[lcdString release];
	[songBitDepth setHidden:NO];


	if (playingSampleRateInHz != fileSampleRateInHz) {
		if (((int)playingSampleRateInHz % (int)fileSampleRateInHz) == 0)
			overWord = NSLocalizedString(@"oversampling ",@"DAC settings info line: oversampling word");
		else if (playingSampleRateInHz > fileSampleRateInHz)
			overWord = NSLocalizedString(@"upsampling ",@"DAC settings info line: upsampling word");
		else
			overWord = NSLocalizedString(@"downsampling ",@"DAC settings info line: downsampling word");
	}
	else {
		overWord = @"";
	}

	if ((int)playingSampleRateInHz % 1000)
		strSplRate = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:NSLocalizedString(@"%i/%.1f D/A %@converter",@"DAC settings info line format for decimal spl rates"),
																 [audioOut audioDeviceCurrentPhysicalBitDepth],
																 playingSampleRateInHz/1000,overWord]
													 attributes:mSRCStringAttributes];
	else
		strSplRate = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:NSLocalizedString(@"%i/%.0f D/A %@converter",@"DAC settings info line format for integer spl rates"),
																 [audioOut audioDeviceCurrentPhysicalBitDepth],
																 playingSampleRateInHz/1000,overWord]
													 attributes:mSRCStringAttributes];

	[currentDACSampleRate setAttributedStringValue:strSplRate];
	[strSplRate release];

	[songCurrentPlayingPosition setMinValue:0.0];
	[songCurrentPlayingPosition setMaxValue:duration_seconds*playingSampleRateInHz];
	[songCurrentPlayingPosition setDoubleValue:0.0];

	//Adjust text display space depending on cover image availability
	if (cover_image) {
		[songCoverImage setHidden:NO];
		[songTextView setFrame:NSMakeRect(342, 82, 296, 115)];
	} else {
		[songCoverImage setHidden:YES];
		[songTextView setFrame:NSMakeRect(204, 82, 431, 115)];
	}
}

- (void)updateCurrentTrackTotalLength:(UInt64)totalFrames duration:(Float64)duration_seconds forBuffer:(int)bufferIdx
{
	if (bufferIdx == [audioOut playingBuffer]) {
		[songCurrentPlayingPosition setMaxValue:totalFrames];
		NSAttributedString *playingTime =[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%02i:%02i",(int)duration_seconds/60,
																					 (int)duration_seconds%60]
																		 attributes:mLCDStringAttributes];
		[songDuration setAttributedStringValue:playingTime];
		[playingTime release];

	}
	mAudioBuffersLoadStatus[bufferIdx].trackTotalLengthinFrames = totalFrames;
}

- (void)updateCurrentPlayingTime
{
	UInt64 currentFrame = [audioOut currentPlayingPosition];
	//Update dockicon display
	NSString *dockIconString = [NSString stringWithFormat:@"Tr.%02i\n%02i:%02i",
								[mPlaylistDoc playingTrackIndex]+1,
								(int)(currentFrame/[audioOut audioDeviceCurrentNominalSampleRate])/60,
								(int)(currentFrame/[audioOut audioDeviceCurrentNominalSampleRate])%60];
	NSImage* dockIcon = [[NSImage alloc] initWithSize:NSMakeSize(128,128)];

	[dockIcon lockFocus];
	NSRect timeBox = {{4, 64}, {120, 64}};
	NSRect textBox = {{4, 60}, {120, 64}};

	if ([[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme] == kAUDUISilverTheme)
		[[NSImage imageNamed:@"NSApplicationIcon"] dissolveToPoint:NSZeroPoint fraction:1.0f];
	else
		[[NSImage imageNamed:@"AudirvanaBlackAppIcon"] dissolveToPoint:NSZeroPoint fraction:1.0f];


	// Background
	[[NSColor colorWithCalibratedHue:0.0f saturation:0.0f brightness:0.1f alpha:0.7f] setFill];
	NSRectFill(timeBox);
	[[NSColor whiteColor] set];
	NSFrameRect(timeBox);

	// Write text
	[dockIconString drawInRect:textBox withAttributes:mDockStringAttributes];

	[dockIcon unlockFocus];

	[NSApp setApplicationIconImage:dockIcon];
	[dockIcon release];

	//Then update main window display
	if (mSongSliderPositionGrabbed) return;

	NSAttributedString *playingTime =[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%02i:%02i",
											(int)(currentFrame/[audioOut audioDeviceCurrentNominalSampleRate])/60,
											(int)(currentFrame/[audioOut audioDeviceCurrentNominalSampleRate])%60]
																	 attributes:mLCDStringAttributes];
	[songCurrentPlayingTime setAttributedStringValue:playingTime];
	[playingTime release];
	[songCurrentPlayingPosition setDoubleValue:currentFrame];
}

- (void)updateLoadStatus:(UInt64)firstLoadedFrame
                      to:(UInt64)lastLoadedFrame
                    upTo:(UInt64)lastFrameToLoad
               forBuffer:(int)bufferLoading
               completed:(BOOL)isComplete
                   reset:(BOOL)isReset
{
	//Update buffers value, even for the non playing buffer, as this may be the first one of a multi-chunk split load of next track
	mAudioBuffersLoadStatus[bufferLoading].firstLoadedFrame = firstLoadedFrame;
	mAudioBuffersLoadStatus[bufferLoading].lastLoadedFrame = lastLoadedFrame;
	mAudioBuffersLoadStatus[bufferLoading].lastFrameToLoad = lastFrameToLoad;
	mAudioBuffersLoadStatus[bufferLoading].loadCompleted = isComplete;

	if ((bufferLoading != [audioOut playingBuffer])
		&& ![audioOut areBothBuffersFromSameFile]) return;

	bool displayBothBuffersStatus = [audioOut areBothBuffersFromSameFile];
	int otherBuffer = (bufferLoading == 0)?1:0;

	//Start synchronous next chunk load
	if (!isReset && isComplete && ([audioOut bufferIndexForNextChunkToLoad] != -1))
		[audioOut loadNextChunk:[audioOut bufferIndexForNextChunkToLoad]];

	UInt64 songTotalFrameLength = [songCurrentPlayingPosition maxValue];
	if (mAudioBuffersLoadStatus[bufferLoading].trackTotalLengthinFrames > 0)
		songTotalFrameLength = mAudioBuffersLoadStatus[bufferLoading].trackTotalLengthinFrames;

	if ((songTotalFrameLength >0) && (((lastLoadedFrame+firstLoadedFrame) < songTotalFrameLength)
									  || ((firstLoadedFrame  > 0)
										  && (!displayBothBuffersStatus || (mAudioBuffersLoadStatus[otherBuffer].firstLoadedFrame > 0)))))
	{
		NSImage *loadStatusImg = [[NSImage alloc] initWithSize:NSMakeSize(256, 10)];
		NSRect fullLoadImgLength = {{0, 0}, {256, 10}};

		[loadStatusImg lockFocus];

		// Background
		[[NSColor colorWithCalibratedHue:0.0f saturation:0.0f brightness:0.1f alpha:0.7f] setFill];
		NSRectFill(fullLoadImgLength);
		[[NSColor darkGrayColor] set];
		NSFrameRect(fullLoadImgLength);

		//Current loading bar
		if (lastFrameToLoad != 0) {
			NSRect currentLoadingBar = {{firstLoadedFrame==0?0:(CGFloat)(8+(firstLoadedFrame * 240)/songTotalFrameLength),0},
				{(CGFloat)(8+(lastLoadedFrame  * 240)/songTotalFrameLength),10}};

			if (isComplete) [[NSColor colorWithCalibratedRed:0.0f green:0.15f blue:0.0f alpha:1.0f] set];
			else [[NSColor darkGrayColor] set];
			NSRectFill(currentLoadingBar);
		}

		if (displayBothBuffersStatus) {
			if (mAudioBuffersLoadStatus[otherBuffer].lastFrameToLoad !=0) {
				NSRect otherBufferLoadingBar = {{mAudioBuffersLoadStatus[otherBuffer].firstLoadedFrame==0?0:(CGFloat)(8+(mAudioBuffersLoadStatus[otherBuffer].firstLoadedFrame * 240)/songTotalFrameLength),0},
					{(CGFloat)(8+(mAudioBuffersLoadStatus[otherBuffer].lastLoadedFrame  * 240)/songTotalFrameLength),10}};

				if (mAudioBuffersLoadStatus[otherBuffer].loadCompleted) [[NSColor colorWithCalibratedRed:0.0f green:0.15f blue:0.0f alpha:1.0f] set];
				else [[NSColor darkGrayColor] set];
				NSRectFill(otherBufferLoadingBar);
			}
		}

		[loadStatusImg unlockFocus];
		[songLoadStatus setImage:loadStatusImg];
		[loadStatusImg release];
	}
	else {
		//End of load : clear display
		[songLoadStatus setImage:nil];
	}

    //Kick off audio device playback ?
    if (mPlaybackStarting) {
        mPlaybackStarting = NO;
        [self startPlayingPhase3];
    }
}

- (void)resetLoadStatus:(BOOL)onlyForNonPlaying
{
	int i = [audioOut playingBuffer];

	if ([audioOut isPlaying]
        && ((mAudioBuffersLoadStatus[i].firstLoadedFrame > 0)
            || ((mAudioBuffersLoadStatus[i].lastLoadedFrame < [songCurrentPlayingPosition maxValue])
                && (mAudioBuffersLoadStatus[i].lastLoadedFrame > 0))))
	{
		//Last chunk of currently playing song is still loaded : redraw only this one
		[self updateLoadStatus:mAudioBuffersLoadStatus[i].firstLoadedFrame
							to:mAudioBuffersLoadStatus[i].lastLoadedFrame
						  upTo:mAudioBuffersLoadStatus[i].lastFrameToLoad
					 forBuffer:i
					 completed:YES
                         reset:YES];
	}
	else [songLoadStatus setImage:nil];

    for(i=0;i<2;i++) {
        if (!onlyForNonPlaying || (i != [audioOut playingBuffer])) {
            mAudioBuffersLoadStatus[i].firstLoadedFrame = 0;
            mAudioBuffersLoadStatus[i].lastFrameToLoad = 0;
            mAudioBuffersLoadStatus[i].lastLoadedFrame = 0;
            mAudioBuffersLoadStatus[i].trackTotalLengthinFrames = 0;
            mAudioBuffersLoadStatus[i].loadCompleted = NO;
        }
	}
}

#pragma mark Loader function

- (bool)fillBufferWithNext:(int)bufferToFill
{
	bool result = YES;

	//First check if a next chunk from the file needs to be loaded
	if (![audioOut loadNextChunk:bufferToFill]) {
		NSURL *fileToPlay;
		result = FALSE;
		while (!result && (fileToPlay = [mPlaylistDoc nextFile])) {
			result = [audioOut loadFile:fileToPlay toBuffer:bufferToFill];
		}
	}
	return result;
}

#pragma mark Notifications handlers

- (void)notifyBufferPlayed:(UInt32)bufferDirty
{
	//First check if the event has not been cleared by track seeking
	if ([audioOut willChangePlayingBuffer]) {


		//Update track position display only if changing track
		if (![audioOut areBothBuffersFromSameFile])
			[mPlaylistDoc setPlayingTrackIndex:[mPlaylistDoc loadedTrackIndex]];

		//Update display for new track
		[audioOut setPlayingBuffer:bufferDirty==0?1:0];

		//Properly empty played buffer
		[audioOut closeBuffer:bufferDirty];

		//Then attempt to refill it
		if (![self fillBufferWithNext:bufferDirty]) {
            //Remove this buffer from the loading progress bar if no other track after
            [self resetLoadStatus:YES];
			//Finally stop if no unplayed audio data is available
			if ([audioOut isAudioBuffersEmpty:0] && [audioOut isAudioBuffersEmpty:1])
				[self stop:nil];
		}
		else [mPlaylistDoc refreshTableDisplay];

		[audioOut resetWillChangePlayingBuffer];
	}
}

- (void)handlePlaylistTrackAppended:(NSNotification*)notification
{
    NSURL *fileToPlay;
    NSUInteger newLoadedPosition = [mPlaylistDoc playlistCount] -1;
	int nonPlayingBuffer;

    if (![audioOut isPlaying]
        || [audioOut areBothBuffersFromSameFile]) return;

    nonPlayingBuffer = [audioOut playingBuffer]==0?1:0;
    if (![audioOut isAudioBuffersEmpty:nonPlayingBuffer]) {
        if ([mPlaylistDoc loadedTrackNonShuffledIndex] == 0) {
            [audioOut closeBuffer:nonPlayingBuffer];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:newLoadedPosition-1];
            [mPlaylistDoc setLoadedTrackIndex:[mPlaylistDoc shuffledIndexFromNonShuffled:newLoadedPosition-1]];
        } else return;
    }

    if ([mPlaylistDoc shuffledIndexFromNonShuffled:([mPlaylistDoc loadedTrackNonShuffledIndex] +1)]
        != (signed)newLoadedPosition) return;

    [mPlaylistDoc setLoadedTrackNonShuffledIndex:([mPlaylistDoc loadedTrackNonShuffledIndex] +1)];
    [mPlaylistDoc setLoadedTrackIndex:[mPlaylistDoc shuffledIndexFromNonShuffled:[mPlaylistDoc loadedTrackNonShuffledIndex]]];

    fileToPlay = [mPlaylistDoc fileAtIndex:[mPlaylistDoc loadedTrackIndex]];
    if (fileToPlay)
        [audioOut loadFile:fileToPlay toBuffer:nonPlayingBuffer];
}

- (void)handlePlaylistReplacedLoadedBuffer:(NSNotification*)notification
{
    NSURL *fileToPlay;
	int nonPlayingBuffer;
    BOOL result = FALSE;

	if (![audioOut isPlaying]) return;

    if ([audioOut areBothBuffersFromSameFile]) {
        //Split load with both buffers on same track: ensure loaded track index follows playng track index
        NSInteger playingTrackIndex = [mPlaylistDoc playingTrackIndex];
        [mPlaylistDoc setLoadedTrackIndex:playingTrackIndex];
        [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:playingTrackIndex]];
        return;
    }

	nonPlayingBuffer = [audioOut playingBuffer]==0?1:0;

	if (![audioOut isAudioBuffersEmpty:nonPlayingBuffer])
		[audioOut closeBuffer:nonPlayingBuffer];

    fileToPlay = [mPlaylistDoc fileAtIndex:[mPlaylistDoc loadedTrackIndex]];
    if (fileToPlay)
        result = [audioOut loadFile:fileToPlay toBuffer:nonPlayingBuffer];
    while (!result && (fileToPlay = [mPlaylistDoc nextFile])) {
        result = [audioOut loadFile:fileToPlay toBuffer:nonPlayingBuffer];
    }
}

- (void)handleNewPlayingTrackSelected:(NSNotification*)notification
{
	int newTrackIndex = [[[notification userInfo] objectForKey:@"index"] intValue];

	//If not playing, set first track that will play and start playing
	if (![audioOut isPlaying]) {
		[mPlaylistDoc setPlayingTrackIndex:newTrackIndex];
		[mPlaylistDoc setLoadedTrackIndex:newTrackIndex];
        [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:newTrackIndex]];
		[self startPlaying];
	}
	else if (newTrackIndex == [mPlaylistDoc playingTrackIndex]) return;
	else if (newTrackIndex == [mPlaylistDoc loadedTrackIndex]) {
		//For seeking to next or previous track, no need to do full reload of both buffers
		//The playing or next buffer to be is already loaded.
		[self seekNext:nil];
	} else if (newTrackIndex == ([mPlaylistDoc shuffledIndexFromNonShuffled:
                                  [mPlaylistDoc nonShuffledIndexFromShuffled:
                                   [mPlaylistDoc playingTrackIndex]]-1])) {
		[self seekPrevious:nil];
	} else {
		if ([audioOut isPlaying]) {
			int oldPlayingBuffer = [audioOut playingBuffer];
			int nonPlayingBuffer = oldPlayingBuffer==0?1:0;
			bool isPaused = [audioOut isPaused];

			if (!isPaused) [audioOut pause:YES];
			[audioOut resetWillChangePlayingBuffer];

			//Reload the to be playing buffer
			[mPlaylistDoc setPlayingTrackIndex:newTrackIndex];
			[audioOut closeBuffer:nonPlayingBuffer];
			[audioOut loadFile:[mPlaylistDoc fileAtIndex:newTrackIndex] toBuffer:nonPlayingBuffer];

			//Clear next buffer
			[mPlaylistDoc setLoadedTrackIndex:newTrackIndex];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:newTrackIndex]];
			[audioOut closeBuffer:oldPlayingBuffer];

			[audioOut setPlayingBuffer:nonPlayingBuffer];
			[audioOut seek:0];
			[self updateCurrentPlayingTime];
			[mPlaylistDoc refreshTableDisplay];
			if (!isPaused) [audioOut pause:NO];

			//And load (if possible) next track in non playing buffer
			if (![self fillBufferWithNext:oldPlayingBuffer]) {
                //Also remove this buffer from the loading progress bar if no other track after
                [self resetLoadStatus:YES];
            }
		}
	}
	[mPlaylistDoc refreshTableDisplay];
}

- (void)handlePlaylistSelectionCursorChanged:(NSNotification*)notification
{
	if (![audioOut isPlaying] && !mPlaybackInitiating) {
		int newTrackIndex = [[[notification userInfo] objectForKey:@"index"] intValue];

        if ((unsigned)newTrackIndex < [mPlaylistDoc playlistCount]) {
            [mPlaylistDoc setPlayingTrackIndex:newTrackIndex];
            [mPlaylistDoc setLoadedTrackIndex:newTrackIndex];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:newTrackIndex]];
            [mPlaylistDoc refreshTableDisplay];
        }
	}
}

- (void)handleMovePlayingTrackSelected:(NSNotification*)notification
{
	NSInteger newPlayingTrackIndex = [[[notification userInfo] objectForKey:@"playingIndex"] intValue];
	NSInteger newLoadedTrackIndex = [[[notification userInfo] objectForKey:@"loadedIndex"] intValue];
	bool needReloadPlayingTrack = [[[notification userInfo] objectForKey:@"reloadPlaying"] boolValue];
	bool needReloadLoadedTrack = [[[notification userInfo] objectForKey:@"reloadLoaded"] boolValue];
	NSInteger oldPlayingTrackIndex= [mPlaylistDoc playingTrackIndex];


	if (newPlayingTrackIndex == -1) {
		[self stop:nil];
		[audioOut closeBuffers];
		[mPlaylistDoc setPlayingTrackIndex:0];
		[mPlaylistDoc setLoadedTrackIndex:0];
        [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:0]];
	}
	else {
		[mPlaylistDoc setPlayingTrackIndex:newPlayingTrackIndex];

		//Playing track is at most just moved, but track next to be may have changed

		//If not playing, set first track that will play
		if (![audioOut isPlaying]) {
			if ((newPlayingTrackIndex != oldPlayingTrackIndex) && !needReloadPlayingTrack)  {
				[mPlaylistDoc setPlayingTrackIndex:newPlayingTrackIndex];
				[mPlaylistDoc setLoadedTrackIndex:newPlayingTrackIndex];
                [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:newPlayingTrackIndex]];
			}
		}
		else if (needReloadPlayingTrack) {
			//Need to reload playing buffer
			int oldPlayingBuffer = [audioOut playingBuffer];
			int nonPlayingBuffer = oldPlayingBuffer==0?1:0;
			bool isPaused = [audioOut isPaused];

			if (!isPaused) [audioOut pause:YES];
			[audioOut resetWillChangePlayingBuffer];

			//Reload the to be playing buffer
			[mPlaylistDoc setPlayingTrackIndex:newPlayingTrackIndex];
			[audioOut closeBuffer:nonPlayingBuffer];
			[audioOut loadFile:[mPlaylistDoc fileAtIndex:newPlayingTrackIndex] toBuffer:nonPlayingBuffer];

			//Check if need to reload next buffer
			if ((newLoadedTrackIndex != (newPlayingTrackIndex+1)) || needReloadLoadedTrack) {
				[mPlaylistDoc setLoadedTrackIndex:newPlayingTrackIndex];
                [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:newPlayingTrackIndex]];
				[audioOut closeBuffer:oldPlayingBuffer];
			}

			[audioOut setPlayingBuffer:nonPlayingBuffer];
			[audioOut seek:0];
			[self updateCurrentPlayingTime];
			[mPlaylistDoc refreshTableDisplay];
			if (!isPaused) [audioOut pause:NO];

			//And load (if needed and possible) next track in non playing buffer
			if ((newLoadedTrackIndex != (newPlayingTrackIndex+1)) || needReloadLoadedTrack) {
				[self fillBufferWithNext:oldPlayingBuffer];
			}
		}
		else if ([audioOut areBothBuffersFromSameFile]) {
			//Moved the playing track that contains both buffers (split load)
			[mPlaylistDoc setLoadedTrackIndex:[mPlaylistDoc playingTrackIndex]];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:[mPlaylistDoc playingTrackIndex]]];
		}
		else if ((newPlayingTrackIndex != oldPlayingTrackIndex)
			&& (newLoadedTrackIndex == [mPlaylistDoc shuffledIndexFromNonShuffled:
                                        ([mPlaylistDoc nonShuffledIndexFromShuffled:newPlayingTrackIndex]+1)])
                 && !needReloadLoadedTrack) {
			//If both tracks are moved simultaneously then not need to reload
			[mPlaylistDoc setLoadedTrackIndex:newLoadedTrackIndex];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:newLoadedTrackIndex]];
		}
		else {
			int nonPlayingBuffer = [audioOut playingBuffer]==0?1:0;
			[mPlaylistDoc setLoadedTrackIndex:[mPlaylistDoc playingTrackIndex]];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:[mPlaylistDoc playingTrackIndex]]];
			[audioOut closeBuffer:nonPlayingBuffer];
			[self fillBufferWithNext:nonPlayingBuffer];
		}
	}
	[mPlaylistDoc refreshTableDisplay];
}

- (void)handleStartPlaybackNotification:(NSNotification*)notification
{
	[self startPlaying];
}

- (void)handleUpdateRepeatStatus:(NSNotification*)notification
{
	if ([mPlaylistDoc isRepeating]) {
		[playRepeatButton setState:YES];

		//If currently playing last playlist item => load last buffer
		if ([mPlaylistDoc playingTrackIndex] == [mPlaylistDoc loadedTrackIndex]) {
			[self fillBufferWithNext:([audioOut playingBuffer]==0?1:0)];
		}
	}
	else {
		[playRepeatButton setState:NO];

		//If track 0 is loaded, that is a loop is set, then unload it
		if ([mPlaylistDoc loadedTrackNonShuffledIndex] == 0) {
			[audioOut closeBuffer:([audioOut playingBuffer]==0?1:0)];
            [mPlaylistDoc setLoadedTrackIndex:[mPlaylistDoc playingTrackIndex]];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:[mPlaylistDoc playingTrackIndex]]];
			[mPlaylistDoc refreshTableDisplay];
		}
	}
}

- (void)handleUpdateShuffleStatus:(NSNotification*)notification
{
    [playShuffleButton setState:[mPlaylistDoc isShuffling]];

    if ([audioOut isPlaying]) {
        //Need to reload the loaded track as it has changed
        int nonPlayingBuffer = [audioOut playingBuffer]^1;
        //First check for split load
        if (![audioOut areBothBuffersFromSameFile]) {
            [mPlaylistDoc setLoadedTrackIndex:[mPlaylistDoc playingTrackIndex]];
            [mPlaylistDoc setLoadedTrackNonShuffledIndex:[mPlaylistDoc nonShuffledIndexFromShuffled:[mPlaylistDoc playingTrackIndex]]];
            [audioOut closeBuffer:nonPlayingBuffer];
            [self fillBufferWithNext:nonPlayingBuffer];
        }
    }
    else {
        //Move starting song to shuffled index corresponding to the position of the current selection
        NSInteger newStartPos = [mPlaylistDoc playingTrackIndex];
        [mPlaylistDoc setLoadedTrackNonShuffledIndex:newStartPos];
        newStartPos = [mPlaylistDoc shuffledIndexFromNonShuffled:newStartPos];
        [mPlaylistDoc setPlayingTrackIndex:newStartPos];
        [mPlaylistDoc setLoadedTrackIndex:newStartPos];
        [mPlaylistDoc refreshTableDisplay];
    }
}

- (void)handleUpdateUISkinTheme:(NSNotification*)notification
{
	switch ([[NSUserDefaults standardUserDefaults] integerForKey:AUDUISkinTheme]) {
		case kAUDUIBlackTheme:
		{
			[parentWindow setBackgroundColor:[NSColor colorWithPatternImage:[NSImage imageNamed:@"Black_PlayerWin_mainWindowBackground.png"]]];

			NSImage *iconImage = [NSImage imageNamed:@"AudirvanaBlackAppIcon"];
            [NSApp setApplicationIconImage:iconImage];
            //Make application image change permanent
            [[NSWorkspace sharedWorkspace] setIcon:iconImage
                                           forFile:[[NSBundle mainBundle] bundlePath]
                                           options:0];
            [[NSWorkspace sharedWorkspace] noteFileSystemChanged:[[NSBundle mainBundle] bundlePath]];


			//Display DAC info string
			if (mSRCStringAttributes) [mSRCStringAttributes release];
			NSMutableParagraphStyle* styledParagraphStyle= [[NSMutableParagraphStyle alloc] init];
			[styledParagraphStyle setAlignment:NSCenterTextAlignment];
			NSFont *greyscaleFont = [NSFont fontWithName:@"GreyscaleBasic" size:11.0f];
			if (!greyscaleFont)
				greyscaleFont = [NSFont labelFontOfSize:11.0f];
			mSRCStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:greyscaleFont,
																		  styledParagraphStyle,
																		  [NSColor colorWithCalibratedRed:86.0f/255.0f green:97.0f/255.0f blue:105.0f/255.0f alpha:1.0f], nil]
																 forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																		  NSParagraphStyleAttributeName,
																		  NSForegroundColorAttributeName, nil]];
			[styledParagraphStyle release];
			NSAttributedString *dacSplRateStr = [[NSAttributedString alloc] initWithString:[currentDACSampleRate stringValue]
																				attributes:mSRCStringAttributes];
			[currentDACSampleRate setAttributedStringValue:dacSplRateStr];
			[dacSplRateStr release];


			//Handle volume control display
			[(CustomSliderCell*)[masterDeviceVolume cell] setKnobImage:[NSImage imageNamed:@"Black_PlayerWin_volume_knob.png"]];
			[(CustomSliderCell*)[masterDeviceVolume cell] setBackgroundImage:[NSImage imageNamed:@"Black_PlayerWin_volume_slider.png"]];
			[masterDeviceVolume setNeedsDisplayInRect:[masterDeviceVolume bounds]];

			//UI Buttons
			[powerButton setImage:[NSImage imageNamed:@"Black_PlayerWin_power_on.png"]];
			[powerButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_power_pressed.png"]];

			[displayOffButton setImage:[NSImage imageNamed:@"Black_PlayerWin_displayoff_on.png"]];
			[displayOffButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_displayoff_pressed.png"]];

			[nextButton setImage:[NSImage imageNamed:@"Black_PlayerWin_next_on.png"]];
			[nextButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_next_pressed.png"]];

			if (![audioOut isPlaying] || [audioOut isPaused]) {
				[playPauseButton setImage:[NSImage imageNamed:@"Black_PlayerWin_play_on.png"]];
				[playPauseButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_play_pressed.png"]];
			}
			else {
				[playPauseButton setImage:[NSImage imageNamed:@"Black_PlayerWin_pause_on.png"]];
				[playPauseButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_pause_pressed.png"]];
			}

			[togglePlaylistButton setImage:[NSImage imageNamed:@"Black_PlayerWin_playlist_on.png"]];
			[togglePlaylistButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_playlist_pressed.png"]];

			[prevButton setImage:[NSImage imageNamed:@"Black_PlayerWin_prev_on.png"]];
			[prevButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_prev_pressed.png"]];

			[stopButton setImage:[NSImage imageNamed:@"Black_PlayerWin_stop_on.png"]];
			[stopButton setAlternateImage:[NSImage imageNamed:@"Black_PlayerWin_stop_pressed.png"]];
		}
			break;

		case kAUDUISilverTheme:
		default:
		{
			[parentWindow setBackgroundColor:[NSColor colorWithPatternImage:[NSImage imageNamed:@"Silver_PlayerWin_mainWindowBackground.png"]]];

			NSImage *iconImage = [NSImage imageNamed:@"AudirvanaAppIcon"];
            [NSApp setApplicationIconImage:iconImage];
            //Make application image change permanent
            [[NSWorkspace sharedWorkspace] setIcon:iconImage
                                           forFile:[[NSBundle mainBundle] bundlePath]
                                           options:0];
            [[NSWorkspace sharedWorkspace] noteFileSystemChanged:[[NSBundle mainBundle] bundlePath]];

			//Display DAC info string
			if (mSRCStringAttributes) [mSRCStringAttributes release];
			NSMutableParagraphStyle* styledParagraphStyle= [[NSMutableParagraphStyle alloc] init];
			[styledParagraphStyle setAlignment:NSCenterTextAlignment];
			NSFont *greyscaleFont = [NSFont fontWithName:@"GreyscaleBasic" size:11.0f];
			if (!greyscaleFont)
				greyscaleFont = [NSFont labelFontOfSize:11.0f];
			NSShadow* shadow = [[NSShadow alloc] init];
				[shadow setShadowOffset:NSMakeSize(1.0f, -1.0f)];
				[shadow setShadowColor:[NSColor whiteColor]];
			mSRCStringAttributes = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:greyscaleFont,
																		  styledParagraphStyle,
																		  [NSColor colorWithCalibratedRed:100.0f/255.0f green:100.0f/255.0f blue:100.0f/255.0f alpha:1.0f],
																		  shadow
																		  ,nil]
																 forKeys:[NSArray arrayWithObjects:NSFontAttributeName,
																		  NSParagraphStyleAttributeName,
																		  NSForegroundColorAttributeName,
																		  NSShadowAttributeName, nil]];
			[styledParagraphStyle release];
			[shadow release];
			NSAttributedString *dacSplRateStr = [[NSAttributedString alloc] initWithString:[currentDACSampleRate stringValue]
																				attributes:mSRCStringAttributes];
			[currentDACSampleRate setAttributedStringValue:dacSplRateStr];
			[dacSplRateStr release];

			//Handle volume control display
			[(CustomSliderCell*)[masterDeviceVolume cell] setKnobImage:[NSImage imageNamed:@"Silver_PlayerWin_volume_knob.png"]];
			[(CustomSliderCell*)[masterDeviceVolume cell] setBackgroundImage:[NSImage imageNamed:@"Silver_PlayerWin_volume_slider.png"]];
			[masterDeviceVolume setNeedsDisplayInRect:[masterDeviceVolume bounds]];

			//UI Buttons
			[powerButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_power_on.png"]];
			[powerButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_power_pressed.png"]];

			[displayOffButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_displayoff_on.png"]];
			[displayOffButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_displayoff_pressed.png"]];

			[nextButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_next_on.png"]];
			[nextButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_next_pressed.png"]];

			if (![audioOut isPlaying] || [audioOut isPaused]) {
				[playPauseButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_play_on.png"]];
				[playPauseButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_play_pressed.png"]];
			}
			else {
				[playPauseButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_pause_on.png"]];
				[playPauseButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_pause_pressed.png"]];
			}

			[togglePlaylistButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_playlist_on.png"]];
			[togglePlaylistButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_playlist_pressed.png"]];

			[prevButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_prev_on.png"]];
			[prevButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_prev_pressed.png"]];

			[stopButton setImage:[NSImage imageNamed:@"Silver_PlayerWin_stop_on.png"]];
			[stopButton setAlternateImage:[NSImage imageNamed:@"Silver_PlayerWin_stop_pressed.png"]];
		}
			break;
	}

	//Update volume control texts
	[self setVolumeControl:[audioOut availableVolumeControls]];
}

- (void)handleUpdateAppleRemoteUse:(NSNotification *)notification
{
	[self startStopAppleRemoteUse:[[NSUserDefaults standardUserDefaults] boolForKey:AUDUseAppleRemote]];
}

- (void)handleUpdateMediaKeysUse:(NSNotification *)notification
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:AUDUseMediaKeys]) {
        if (!mKeyTap)
            mKeyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];

        if([SPMediaKeyTap usesGlobalMediaKeyTap])
            [mKeyTap startWatchingMediaKeys];

        [mKeyTap setInterceptVolumeControl:([[NSUserDefaults standardUserDefaults] boolForKey:AUDUseMediaKeysForVolumeControl]
                                            && [audioOut availableVolumeControls])];
    }
    else {
        if (mKeyTap)
            [mKeyTap stopWatchingMediaKeys];
    }
}


- (void)handleDeviceChange:(NSNotification*)notification
{
	[audioOut handleDeviceChange:notification];
	[preferenceController setActiveDeviceDesc:[[audioOut audioDevicesList] objectAtIndex:audioOut.selectedAudioDeviceIndex]];
    mIsAudioMute = [audioOut isMute];
    [mKeyTap setInterceptVolumeControl:([[NSUserDefaults standardUserDefaults] boolForKey:AUDUseMediaKeysForVolumeControl]
                                        && [audioOut availableVolumeControls])];
}

#pragma mark Other Audio HAL notifications

- (void)notifyProcessorOverload
{
	if (![audioOut isChangingSamplingRate]) {
		//Remove false alarms that occur when changing sampling rate

		//scan audio buffer to force it to be reloaded into memory if it was swapped to disk
		[audioOut unswapPlayingBuffer];

		//Display warning to user
		[displayOverload setHidden:NO];
		[[self class] cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(clearProcessorOverload:) object:nil];
		[self performSelector:@selector(clearProcessorOverload) withObject:nil afterDelay:1.0];
	}
}

- (void)clearProcessorOverload
{
	[displayOverload setHidden:YES];
}

- (void)notifyDeviceRemoved
{
	[self stop:nil];
}

- (void)notifyDevicesListUpdated
{
	[audioOut rebuildDevicesList];
	if (preferenceController) {
		[preferenceController setAvailableDevicesList:audioOut.audioDevicesList];
		[preferenceController setActiveDeviceDesc:[[audioOut audioDevicesList] objectAtIndex:audioOut.selectedAudioDeviceIndex]];
	}
}

- (void)notifyDeviceVolumeChanged
{
	NSAttributedString *volumeValueText;

	Float32 volumeValue = [audioOut masterVolumeScalar:[audioOut availableVolumeControls]&kAudioVolumePhysicalControl
						   ? kAudioVolumePhysicalControl:kAudioVolumeVirtualControl];
	Float32 volumedBValue = [audioOut masterVolumeDecibel:[audioOut availableVolumeControls]&kAudioVolumePhysicalControl
						   ? kAudioVolumePhysicalControl:kAudioVolumeVirtualControl];

	[masterDeviceVolume setFloatValue:volumeValue];

	if ([audioOut isMute])
        volumeValueText = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"MUTE", @"Mute text in LCD in place of volume value")
                                                          attributes:mLCDStringAttributes];
    else if (volumedBValue <= -INFINITY)
		volumeValueText = [[NSAttributedString alloc] initWithString:@"-∞ dB" attributes:mLCDStringAttributes];
	else
		volumeValueText = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%i dB",(int)volumedBValue] attributes:mLCDStringAttributes];

	[masterDeviceVolumeValue setAttributedStringValue:volumeValueText];
	[volumeValueText release];
}

- (void)notifyDeviceDataSourceChanged
{
    //Reload volume value as it can be different for headphones vs line output
    [self notifyDeviceVolumeChanged];
    //Workaround for latency afeter notification
    [self performSelector:@selector(notifyDeviceVolumeChanged) withObject:nil afterDelay:1.5];
}

@end