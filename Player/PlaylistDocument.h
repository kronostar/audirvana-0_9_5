/*
 PlaylistDocument.h

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

 Original code written by Damien Plisson 10/2010 */

#import <Cocoa/Cocoa.h>
#import <PlaylistArrayController.h>

#include <dispatch/dispatch.h>

//Playlist changes notifications
extern NSString * const AUDPlaylistItemAppendedtoPlaylistNotification;
extern NSString * const AUDPlaylistItemInsertedAtLoadedPositionNotification;
extern NSString * const AUDPlaylistSelectPlayingTrackNotification;
extern NSString * const AUDPlaylistSelectionCursorChangedNotification;
extern NSString * const AUDPlaylistMovePlayingTrackNotification;
extern NSString * const AUDStartPlaybackNotification;
extern NSString * const AUDTogglePlaylistRepeat;
extern NSString * const AUDTogglePlaylistShuffle;


//Playlist formats
typedef enum {
	kAudioPlaylistM3U = 1,
	kAudioPlaylistM3U8 = 2
} AudioPlaylistFormats;

@interface PlaylistDocument : NSWindowController {
	NSArray *audioFilesExtensions;
	NSMutableArray *playlist;
    NSMutableArray *mShuffleIndexes;
	IBOutlet NSTableView *playlistView;
	IBOutlet PlaylistArrayController *playlistController;
	IBOutlet NSWindow *progressSheet;
	IBOutlet NSProgressIndicator *addingTracksProgress;

    dispatch_queue_t mInsertTracksDispatchQueue;

	NSInteger mPlayingTrackIndex;
	NSInteger mLoadedTrackIndex;
    NSInteger mLoadedTrackNonShuffledIndex; //Maintains a count of played tracks, and position inside shuffle list
	BOOL mIsRepeating;
    BOOL mIsShuffling;
	BOOL mAbortAddingTracks;
	BOOL mAddingTracksInBackground;
	BOOL mTriggerPlaybackOnFirstTrackAdded;
}

@property (getter=playingTrackIndex,setter=setPlayingTrackIndex:) NSInteger mPlayingTrackIndex;
@property (getter=loadedTrackIndex,setter=setLoadedTrackIndex:) NSInteger mLoadedTrackIndex;
@property (getter=loadedTrackNonShuffledIndex,setter=setLoadedTrackNonShuffledIndex:) NSInteger mLoadedTrackNonShuffledIndex;
@property (getter=isShuffling,readonly) BOOL mIsShuffling;
@property (getter=isRepeating,readonly) BOOL mIsRepeating;

- (void)addPlaylistItems;
- (void)insertPlaylistItems:(NSArray*)urlsToOpen atRow:(NSUInteger)row sortToplist:(BOOL)isSorted;
- (NSUInteger)insertPlaylistItemFromFolder:(NSURL *)itemURL atRow:(NSUInteger)row;
- (void)movePlaylistItems:(NSIndexSet*)rowsToMove toRow:(NSInteger)rowToInsert;
- (void)removePlaylistItems:(NSIndexSet*)rowsToRemove;
- (void)deleteSelectedPlaylistItems;
- (void)prunePlaylistItems:(BOOL)removeAll;
- (void)changePlayingTrack:(NSInteger)newPlayingIndex;
- (void)setPlaylist:(NSMutableArray *)aPlaylist;
- (NSUInteger)playlistCount;
- (NSInteger)nonShuffledIndexFromShuffled:(NSInteger)shuffledIndex;
- (NSInteger)shuffledIndexFromNonShuffled:(NSInteger)nonShuffledIndex;

//Used by openFile in Application delegate to launch playback when launching Audirvana from document
- (void)triggerPlaybackOnFirstTrackAdded;

//Playlist load/save
- (bool)loadPlaylist:(NSURL*)playlistFile appendToExisting:(BOOL)isToAppend;
- (bool)savePlaylist:(NSURL*)playlistFile format:(AudioPlaylistFormats)playlistFormat;

//Cancel action called from the adding progress sheet
- (IBAction)cancelAddingTrack:(id)sender;

- (NSURL*)nextFile;
- (NSURL*)firstFileWhenStartingPlayback;
- (NSURL*)fileAtIndex:(NSInteger)index;
- (void)refreshTableDisplay;
- (void)resetPlayingPosToStart;

- (void)setIsRepeating:(BOOL)isRepeatingStatus;
- (void)setIsShuffling:(BOOL)isShuffling;
@end