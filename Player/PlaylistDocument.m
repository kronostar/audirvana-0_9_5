/*
 PlaylistDocument.m

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

#import "PlaylistDocument.h"
#import "PlaylistItem.h"
#import "PlaylistView_Delegate.h"
#import "PreferenceController.h"

#import "AudioFileLoader.h"

//Playlist changes notifications
NSString * const AUDPlaylistItemInsertedAtLoadedPositionNotification = @"AUDPlaylistItemInsertedAtLoadedPositionNotification";
NSString * const AUDPlaylistItemAppendedtoPlaylistNotification = @"AUDPlaylistItemAppendedtoPlaylistNotification";
NSString * const AUDPlaylistSelectPlayingTrackNotification = @"AUDPlaylistSelectPlayingTrackNotification";
NSString * const AUDPlaylistSelectionCursorChangedNotification = @"AUDPlaylistSelectionCursorChangedNotification";
NSString * const AUDPlaylistMovePlayingTrackNotification = @"AUDPlaylistMovePlayingTrackNotification";
NSString * const AUDStartPlaybackNotification = @"AUDStartPlaybackNotification";
NSString * const AUDTogglePlaylistRepeat = @"AUDTogglePlaylistRepeat";
NSString * const AUDTogglePlaylistShuffle = @"AUDTogglePlaylistShuffle";

#pragma mark PlaylistDocument implementation

@interface PlaylistDocument (PrivateMethods)
- (bool)insertPlaylistItem:(NSURL*)itemURL atRow:(NSUInteger)row;
@end


@implementation PlaylistDocument
@synthesize mPlayingTrackIndex,mLoadedTrackIndex,mLoadedTrackNonShuffledIndex,mIsRepeating,mIsShuffling;

- (id)init
{
	self = [super initWithWindowNibName:@"Playlist"];

    if (self) {
		playlist = [[NSMutableArray alloc] init];

        mShuffleIndexes = nil;

		audioFilesExtensions = [[AudioFileLoader supportedFileExtensions] retain];

		mPlayingTrackIndex = 0;
		mLoadedTrackIndex = 0;
        mLoadedTrackNonShuffledIndex = 0;
		mAddingTracksInBackground = FALSE;
		mTriggerPlaybackOnFirstTrackAdded = FALSE;
        mInsertTracksDispatchQueue = NULL;
    }
    return self;
}

- (void)awakeFromNib
{
	PlaylistView_Delegate *playlistView_del = [[PlaylistView_Delegate alloc] init];
	[playlistView_del setDocument:self];
	[playlistView setDelegate:playlistView_del];
	[playlistController setPlaylistDocument:self];
}

- (void)dealloc
{
	[self setPlaylist:nil];
	[audioFilesExtensions release];
    if (mShuffleIndexes) { [mShuffleIndexes release]; mShuffleIndexes = nil; }
    if (mInsertTracksDispatchQueue) { dispatch_resume(mInsertTracksDispatchQueue); mInsertTracksDispatchQueue = NULL; }
	[super dealloc];
}

- (NSString *)windowNibName {
    // Implement this to return a nib to load OR implement -makeWindowControllers to manually create your controllers.
    return @"Playlist";
}

#pragma mark Playlist contents management

- (void)setPlaylist:(NSMutableArray *)aPlaylist
{
	if (aPlaylist == playlist)
		return;

    if (playlist != aPlaylist)
	{
        [aPlaylist retain];
		[playlist release];
		playlist = aPlaylist;
    }
}

- (NSUInteger)playlistCount
{
	return [playlist count];
}

- (void)addPlaylistItems
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];

	[openPanel setCanChooseDirectories:TRUE];
	[openPanel setAllowsMultipleSelection:TRUE];
	if ([openPanel runModalForTypes:audioFilesExtensions] == NSOKButton) {
		[self insertPlaylistItems:[openPanel URLs] atRow:[playlist count] sortToplist:YES];
	}
}

- (void)insertPlaylistItems:(NSArray*)urlsToOpen atRow:(NSUInteger)row sortToplist:(BOOL)isSorted
{
	if ([urlsToOpen count] ==0) {
		mTriggerPlaybackOnFirstTrackAdded = FALSE;
		return;
	}

	NSUInteger oldSelectionPos = [self nonShuffledIndexFromShuffled:[playlistController selectionIndex]];
	if (oldSelectionPos > [playlist count]) oldSelectionPos = 0;

	[[self window] setDocumentEdited:YES];

	/*If adding only one file, no need to display progress sheet and perform insert in background */
	if (([urlsToOpen count] == 1) && !mAddingTracksInBackground) {
		NSNumber *isDirectory;
		NSURL *fileToAdd = [urlsToOpen objectAtIndex:0];
		if (!([fileToAdd getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL]
			&& [isDirectory boolValue])) {
			[self insertPlaylistItem:fileToAdd atRow:row];
			mTriggerPlaybackOnFirstTrackAdded = FALSE;
			return;
		}
	}


	[urlsToOpen retain];

    if (!mInsertTracksDispatchQueue) {
        mInsertTracksDispatchQueue = dispatch_queue_create("fr.dplisson.audirvana.insertTracks", NULL);
    }

	dispatch_async(mInsertTracksDispatchQueue, ^{
		NSNumber *isDirectory;
		NSUInteger currentRow = row;

        NSArray *sortedUrlsToOpen;

        mAbortAddingTracks = FALSE;
        mAddingTracksInBackground = TRUE;

        dispatch_async(dispatch_get_main_queue(), ^{
            [addingTracksProgress setMinValue:0.0f];
            [addingTracksProgress setMaxValue:[urlsToOpen count]];
            [addingTracksProgress setDoubleValue:0.0f];
            [NSApp beginSheet:progressSheet modalForWindow:[playlistView window]
                modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        });

        if (isSorted) {
            sortedUrlsToOpen = [urlsToOpen sortedArrayUsingComparator:^(id url1, id url2) {
                NSString *url1Name = [url1 path];
                return [url1Name compare:[url2 path]
                                 options:NSNumericSearch | NSWidthInsensitiveSearch | NSForcedOrderingSearch
                                   range:NSMakeRange(0, [url1Name length])
                                  locale:[NSLocale currentLocale]];
            }];
        }
        else sortedUrlsToOpen = urlsToOpen;

		for (NSURL *url in sortedUrlsToOpen) {
			if (mAbortAddingTracks) break;
			if ([url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL]
				&& [isDirectory boolValue]) {
				//Directory selected => enumerate it
				currentRow += [self insertPlaylistItemFromFolder:url atRow:currentRow];
			}
			else {
				if ([self insertPlaylistItem:url atRow:currentRow])
					currentRow++;
				dispatch_async(dispatch_get_main_queue(), ^{[addingTracksProgress incrementBy:1.0f];});
			}
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			[NSApp endSheet:progressSheet];
			[progressSheet orderOut:nil];
			[playlistController setSelectionIndex:[self shuffledIndexFromNonShuffled:oldSelectionPos]];
		});
		[urlsToOpen release];
		mAddingTracksInBackground = FALSE;
		mTriggerPlaybackOnFirstTrackAdded = FALSE;
	});
}

/* Insert playlist item from a folder, may be called by the background queue */
- (NSUInteger)insertPlaylistItemFromFolder:(NSURL *)itemURL atRow:(NSUInteger)row
{
	NSNumber *isDirectory;
	NSUInteger nbItemsInserted = 0;
	NSUInteger insertRevIdx = [playlist count] - row;
	NSFileManager *localFileManager=[[NSFileManager alloc] init];

	NSDirectoryEnumerator *dirEnum = [localFileManager enumeratorAtURL:itemURL
											includingPropertiesForKeys:[NSArray arrayWithObjects:NSURLNameKey,
																		NSURLIsDirectoryKey,nil]
															   options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    //Sort array as network mounts list may be in random order
	NSArray *dirFiles = [[dirEnum allObjects] sortedArrayUsingComparator:^(id url1, id url2) {
        NSString *url1Name = [url1 path];
        return [url1Name compare:[url2 path]
                            options:NSNumericSearch | NSWidthInsensitiveSearch | NSForcedOrderingSearch
                              range:NSMakeRange(0, [url1Name length])
                             locale:[NSLocale currentLocale]];
    }];
	NSUInteger dirSize = [dirFiles count];

	if (mAddingTracksInBackground)
		dispatch_async(dispatch_get_main_queue(),
				   ^{[addingTracksProgress setMaxValue:[addingTracksProgress maxValue] + dirSize];});

	for (NSURL *filesInDir in dirFiles) {
		if (mAbortAddingTracks) break;
		if (![filesInDir getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL]
			|| ![isDirectory boolValue]) {
			//Do not handle sub-directories listed, as enumeration is already deep
			if ([AudioFileLoader isFormatSupported:filesInDir])
				if ([self insertPlaylistItem:filesInDir atRow:[playlist count]-insertRevIdx])
					nbItemsInserted++;
		}
		if (mAddingTracksInBackground)
			dispatch_async(dispatch_get_main_queue(), ^{[addingTracksProgress incrementBy:1.0f];});
	}


	[localFileManager release];
	return nbItemsInserted;
}

/* Insert playlist item, may be called by the background queue */
- (bool)insertPlaylistItem:(NSURL*)itemURL atRow:(NSUInteger)row
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    AudioFileLoader *fileLoader = [[AudioFileLoader createWithURL:itemURL] retain];
	if (fileLoader) {
        NSUInteger previousPlaylistSize = [playlist count];
		PlaylistItem *newItem = [[PlaylistItem alloc]init];
		[newItem setFileURL:itemURL];
		NSString *str = [fileLoader title];
		[newItem setTitle:str?str:[itemURL lastPathComponent]];
		str = [fileLoader album];
		if (str) [newItem setAlbum:str];
		str = [fileLoader artist];
		if (str) [newItem setArtist:str];
		str = [fileLoader composer];
		if (str) [newItem setComposer:str];
		[newItem setDurationInSeconds:[fileLoader durationInSeconds]];
		[newItem setTrackNumber:[fileLoader trackNumber]];
		[fileLoader close];
		[fileLoader release];

        //Used to check if not playing: mPlayingTrackIndex changes in the playlist selection cursor event notification handler
        NSInteger currentPlayingTrackIndex = mPlayingTrackIndex;

		if (mAddingTracksInBackground)
			dispatch_sync(dispatch_get_main_queue(), ^{
                [playlistController insertObject:newItem atArrangedObjectIndex:row];
                if (mIsShuffling) {
                    NSUInteger playlistCount = [mShuffleIndexes count];
                    [mShuffleIndexes insertObject:[NSNumber numberWithInteger:playlistCount]
                                          atIndex:(arc4random() % (playlistCount+1))];
                }
            });
		else {
			[playlistController insertObject:newItem atArrangedObjectIndex:row];
            if (mIsShuffling) {
                NSUInteger playlistCount = [mShuffleIndexes count];
                [mShuffleIndexes insertObject:[NSNumber numberWithInteger:playlistCount]
                                      atIndex:(arc4random() % (playlistCount+1))];
            }
        }

		[newItem release];

        if (((NSInteger)row <= mPlayingTrackIndex) && (previousPlaylistSize > 0)
            && (currentPlayingTrackIndex == mPlayingTrackIndex)) { //Playing track selection stays on the actual playing track
            mPlayingTrackIndex++;
        }

		//Notify for immediate load of file if inserted at the position of the loaded one
		if (mLoadedTrackIndex == ((int)row)) {
            if (mAddingTracksInBackground)
                dispatch_async(dispatch_get_main_queue(),
                               ^{[[NSNotificationCenter defaultCenter] postNotificationName:AUDPlaylistItemInsertedAtLoadedPositionNotification
                                                                                     object:self];});
            else
                [[NSNotificationCenter defaultCenter] postNotificationName:AUDPlaylistItemInsertedAtLoadedPositionNotification
                                                                    object:self];
		} else if ((NSInteger)row < mLoadedTrackIndex) {
            mLoadedTrackIndex++;
            mLoadedTrackNonShuffledIndex = [self nonShuffledIndexFromShuffled:mLoadedTrackIndex];
        }

        //Check if track added at end of playlist, while playing last item
        if (row == ([playlist count]-1)) {
            if (mAddingTracksInBackground)
                dispatch_async(dispatch_get_main_queue(),
                               ^{[[NSNotificationCenter defaultCenter] postNotificationName:AUDPlaylistItemAppendedtoPlaylistNotification
                                                                                     object:self];});
            else
                [[NSNotificationCenter defaultCenter] postNotificationName:AUDPlaylistItemAppendedtoPlaylistNotification
                                                                    object:self];
        }

		//Notify for playback start if requested
		if (mTriggerPlaybackOnFirstTrackAdded) {
			mTriggerPlaybackOnFirstTrackAdded = NO;
            if (mAddingTracksInBackground)
                dispatch_async(dispatch_get_main_queue(), ^{[[NSNotificationCenter defaultCenter] postNotificationName:AUDStartPlaybackNotification
                                                                                                                object:self];});
            else
                [[NSNotificationCenter defaultCenter] postNotificationName:AUDStartPlaybackNotification
                                                                    object:self];
		}
		[pool drain];
		return TRUE;
	} else {
        [pool drain];
        return FALSE;
    }
}

- (void)movePlaylistItems:(NSIndexSet*)rowsToMove toRow:(NSInteger)rowToInsert
{
	if (mAddingTracksInBackground) return;

	NSInteger rowIndex = [rowsToMove lastIndex];
	NSInteger playingTrackIndexInSet = NSNotFound;
	NSInteger loadedTrackIndexInSet = NSNotFound;
	NSInteger newPlayingTrackIndex = mPlayingTrackIndex;
	NSInteger newLoadedTrackIndex = mLoadedTrackIndex;
	NSInteger posInSet = [rowsToMove count]-1;
	NSArray* oldArray = [playlistController arrangedObjects];
	NSMutableArray* tmpArray = [[NSMutableArray alloc] initWithCapacity:[rowsToMove count]];

	while (rowIndex != NSNotFound) {
		if (rowIndex == mPlayingTrackIndex) playingTrackIndexInSet = posInSet;
		else if (rowIndex == mLoadedTrackIndex) loadedTrackIndexInSet = posInSet;

		[tmpArray insertObject:[oldArray objectAtIndex:rowIndex] atIndex:0];
		[playlistController removeObjectAtArrangedObjectIndex:rowIndex];

		if (rowIndex < rowToInsert) rowToInsert--;

		if (rowIndex < newPlayingTrackIndex) newPlayingTrackIndex--;
		if (rowIndex < newLoadedTrackIndex) newLoadedTrackIndex--;

		rowIndex = [rowsToMove indexLessThanIndex:rowIndex];
		posInSet--;
	}

	if (newPlayingTrackIndex >= rowToInsert) newPlayingTrackIndex += [rowsToMove count];
	if (newLoadedTrackIndex >= rowToInsert) newLoadedTrackIndex += [rowsToMove count];

	if (playingTrackIndexInSet != NSNotFound) newPlayingTrackIndex = playingTrackIndexInSet+rowToInsert;

	if (loadedTrackIndexInSet != NSNotFound) newLoadedTrackIndex = loadedTrackIndexInSet + rowToInsert;

	[playlistController insertObjects:tmpArray
			  atArrangedObjectIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(rowToInsert, [rowsToMove count])]];

	NSDictionary *plTrackDict = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithLong:newPlayingTrackIndex],
																	 [NSNumber numberWithLong:newLoadedTrackIndex],nil]
															forKeys:[NSArray arrayWithObjects:@"playingIndex",@"loadedIndex",nil]];
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDPlaylistMovePlayingTrackNotification
														object:self userInfo:plTrackDict];

	[[self window] setDocumentEdited:YES];
	[tmpArray release];
}

- (void)removePlaylistItems:(NSIndexSet*)rowsToRemove
{
	if (mAddingTracksInBackground) return;

	NSInteger rowIndex = [rowsToRemove lastIndex];
	NSInteger newPlayingTrackIndex = mPlayingTrackIndex;
	NSInteger newLoadedTrackIndex = mLoadedTrackIndex;
	bool playingTrackRemoved = NO;
	bool loadedTrackRemoved = NO;
	NSInteger playlistCount;

	while (rowIndex != NSNotFound) {
		//Get next track if the current track in use is removed
		if (rowIndex == mPlayingTrackIndex) {
			newPlayingTrackIndex++;
			playingTrackRemoved = YES;
		} else if (rowIndex == mLoadedTrackIndex) {
			newLoadedTrackIndex++;
			loadedTrackRemoved = YES;
		}

		[playlistController removeObjectAtArrangedObjectIndex:rowIndex];
        if (mIsShuffling)
            [mShuffleIndexes removeObject:[NSNumber numberWithInteger:([mShuffleIndexes count]-1)]];

		if (rowIndex < newPlayingTrackIndex) newPlayingTrackIndex--;
		if (rowIndex < newLoadedTrackIndex) newLoadedTrackIndex--;

		rowIndex = [rowsToRemove indexLessThanIndex:rowIndex];
	}

	playlistCount = [[playlistController arrangedObjects] count];
	if (newPlayingTrackIndex >= playlistCount) newPlayingTrackIndex = playlistCount-1;
	if (newLoadedTrackIndex < newPlayingTrackIndex) newLoadedTrackIndex = newPlayingTrackIndex+1;
	if (newLoadedTrackIndex >= playlistCount) newLoadedTrackIndex = playlistCount-1;

	NSDictionary *plTrackDict = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithLong:newPlayingTrackIndex],
																	 [NSNumber numberWithLong:newLoadedTrackIndex],
																	 [NSNumber numberWithBool:playingTrackRemoved],
																	 [NSNumber numberWithBool:loadedTrackRemoved], nil]
															forKeys:[NSArray arrayWithObjects:@"playingIndex",@"loadedIndex",
																	 @"reloadPlaying",@"reloadLoaded",nil]];
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDPlaylistMovePlayingTrackNotification
														object:self userInfo:plTrackDict];

	[[self window] setDocumentEdited:YES];
}


- (void)deleteSelectedPlaylistItems
{
	[self removePlaylistItems:[playlistView selectedRowIndexes]];
}

/**
 prunePlaylistItems
 Remove all items except the playing one
 */
- (void)prunePlaylistItems:(BOOL)removeAll
{
	if (mAddingTracksInBackground) return;

	NSInteger rowIndex;
	NSInteger newPlayingTrackIndex = mPlayingTrackIndex;
	NSInteger newLoadedTrackIndex = mLoadedTrackIndex;
	bool loadedTrackRemoved = NO;
	NSInteger playlistCount;

	for (rowIndex = [[playlistController arrangedObjects] count]-1;rowIndex>=0;rowIndex--) {
		//Get next track if the current track in use is removed
		if ((rowIndex == mPlayingTrackIndex) && !removeAll) {
			continue;
		} else if (rowIndex == mLoadedTrackIndex) {
			newLoadedTrackIndex++;
			loadedTrackRemoved = YES;
		}

		[playlistController removeObjectAtArrangedObjectIndex:rowIndex];
        if (mIsShuffling)
            [mShuffleIndexes removeObject:[NSNumber numberWithInteger:rowIndex]];

		if (rowIndex < newPlayingTrackIndex) newPlayingTrackIndex--;
		if (rowIndex < newLoadedTrackIndex) newLoadedTrackIndex--;
	}

	playlistCount = [[playlistController arrangedObjects] count];
	if (newPlayingTrackIndex >= playlistCount) newPlayingTrackIndex = playlistCount-1;
	if (newLoadedTrackIndex < newPlayingTrackIndex) newLoadedTrackIndex = newPlayingTrackIndex+1;
	if (newLoadedTrackIndex >= playlistCount) newLoadedTrackIndex = playlistCount-1;

	NSDictionary *plTrackDict = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithLong:newPlayingTrackIndex],
																	 [NSNumber numberWithLong:newLoadedTrackIndex],
																	 [NSNumber numberWithBool:NO], //Playing track not removed
																	 [NSNumber numberWithBool:loadedTrackRemoved], nil]
															forKeys:[NSArray arrayWithObjects:@"playingIndex",@"loadedIndex",
																	 @"reloadPlaying",@"reloadLoaded",nil]];
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDPlaylistMovePlayingTrackNotification
														object:self userInfo:plTrackDict];

	[[self window] setDocumentEdited:YES];
}


- (IBAction)cancelAddingTrack:(id)sender
{
	mAbortAddingTracks = TRUE;
}

- (void)triggerPlaybackOnFirstTrackAdded
{
	mTriggerPlaybackOnFirstTrackAdded = YES;
}

#pragma mark Playlist load/save

- (bool)loadPlaylist:(NSURL*)playlistFile appendToExisting:(BOOL)isToAppend
{
	bool result = FALSE;
	NSMutableArray *playlistLoaded = [[NSMutableArray alloc] initWithCapacity:20];

	if (!isToAppend && ([playlist count] != 0))
		[self prunePlaylistItems:YES];

	//Decode playlist file
	NSString *playlistData;

	if (([[playlistFile pathExtension] caseInsensitiveCompare:@"m3u8"] == NSOrderedSame)
		|| [[NSUserDefaults standardUserDefaults] boolForKey:AUDUseUTF8forM3U])
		playlistData = [NSString stringWithContentsOfURL:playlistFile encoding:NSUTF8StringEncoding error:NULL];
	else
		playlistData = [NSString stringWithContentsOfURL:playlistFile encoding:NSISOLatin1StringEncoding error:NULL];

	if (playlistData) {
		NSArray *playlistFileLines = [playlistData componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"]];

		for (NSString *item in playlistFileLines) {
			NSString *cleanItem = [item stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n\t"]];

			if (([cleanItem length]>0) && ([cleanItem characterAtIndex:0] != '#')) {
				NSURL *itemURL = [NSURL fileURLWithPath:cleanItem];
				if (itemURL && [itemURL isFileURL])
					[playlistLoaded addObject:itemURL];
			}
		}
	}

	if ([playlistLoaded count] != 0) {
		[self insertPlaylistItems:playlistLoaded atRow:[playlist count] sortToplist:NO];
        result = TRUE;
    }
	else
		mTriggerPlaybackOnFirstTrackAdded = FALSE;

	[playlistLoaded release];

	if (!isToAppend) {
		[[self window] setTitle:[playlistFile lastPathComponent]];
		[[self window] setRepresentedURL:playlistFile];
		[[self window] setDocumentEdited:NO];
	}
	else
		[[self window] setDocumentEdited:YES];

	return result;
}

- (bool)savePlaylist:(NSURL*)playlistFile format:(AudioPlaylistFormats)playlistFormat
{
	bool result = FALSE;
	bool aborted = FALSE;

	if ([playlist count] == 0)
		return FALSE;

	NSMutableString *playlistData = [[NSMutableString alloc] initWithCapacity:1000];

	[playlistData appendString:@"#EXTM3U\n"];

	for (PlaylistItem* item in playlist) {
		[playlistData appendFormat:@"#EXTINF:%i,%@\n",(int)[item durationInSeconds],[item title]];
		[playlistData appendFormat:@"%@\n",[[item fileURL] path]];
	}
	if ([[NSUserDefaults standardUserDefaults] boolForKey:AUDUseUTF8forM3U])
		playlistFormat = kAudioPlaylistM3U8;

	switch (playlistFormat) {
		case kAudioPlaylistM3U8:
			result = [playlistData writeToURL:playlistFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
			break;
		case kAudioPlaylistM3U:
		default:
			result = [playlistData writeToURL:playlistFile atomically:YES encoding:NSISOLatin1StringEncoding error:NULL];

			if (!result) {
				if (NSRunAlertPanel(NSLocalizedString(@"Error saving playlist",@"Error saving playlist alert panel"),
                                    NSLocalizedString(@"Unable to save the playlist in M3U format.\nThis may be due to a character encoding issue.\nDo you want to tray saving in M3U8 format ?",@"Error saving playlist alert panel"),
									NSLocalizedString(@"Cancel",@"Cancel button title"),
                                    NSLocalizedString(@"Yes",@"Yes button title"), nil) == NSAlertAlternateReturn) {
					playlistFile = [[playlistFile URLByDeletingPathExtension] URLByAppendingPathExtension:@"m3u8"];
					result = [playlistData writeToURL:playlistFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
				}
				else aborted = TRUE;
			}
			break;
	}

	[playlistData release];

	if (result) {
		[[self window] setDocumentEdited:NO];
		[[self window] setRepresentedURL:playlistFile];
		[[self window] setTitle:[playlistFile lastPathComponent]];
	} else {
		if (!aborted)
			NSRunAlertPanel(NSLocalizedString(@"Error saving playlist",@"Error saving playlist alert panel"),
                            NSLocalizedString(@"An error occured trying to save the playlist",@"Error saving playlist alert panel"),
                            NSLocalizedString(@"Cancel",@"Cancel button title"), nil, nil);
	}

	return result;
}

#pragma mark Change play orders

- (void)setIsRepeating:(BOOL)isRepeatingStatus
{
	mIsRepeating = isRepeatingStatus;

	//Send notification to have all UI Repeat controls updated, and first track loaded if needed
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDTogglePlaylistRepeat
														object:self];

    //Remember settings
    [[NSUserDefaults standardUserDefaults] setBool:isRepeatingStatus forKey:AUDLoopModeActive];
}

- (void)setIsShuffling:(BOOL)isShuffling
{
    if (!mIsShuffling) {
        NSUInteger i;
        NSUInteger count = [playlist count];

        //Create list of indexes
        if (mShuffleIndexes) [mShuffleIndexes release];
        mShuffleIndexes = [[NSMutableArray alloc] initWithCapacity:count];
        for(i=0;i<count;i++) {
            [mShuffleIndexes addObject:[NSNumber numberWithInteger:i]];
        }
        //then shuffle it
        for (i=0; i<count; i++) {
            //Exchange element i with one of the elements after it
            [mShuffleIndexes exchangeObjectAtIndex:i withObjectAtIndex:(arc4random()%(count-i))+i];
        }
    }

    mIsShuffling = isShuffling;

    //Send notification to have all UI Shuffle controls updated, and first track loaded if needed
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDTogglePlaylistShuffle
														object:self];

    //Remember settings
    [[NSUserDefaults standardUserDefaults] setBool:isShuffling forKey:AUDShuffleModeActive];
}

- (void)changePlayingTrack:(NSInteger)newPlayingIndex
{
	if ((newPlayingIndex<0) || ([playlist count] <= (UInt32)(newPlayingIndex)))
		return;

	NSDictionary *plTrackDict = [NSDictionary dictionaryWithObject:[NSNumber numberWithLong:newPlayingIndex] forKey:@"index"];
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDPlaylistSelectPlayingTrackNotification
														object:self userInfo:plTrackDict];
}

#pragma mark Playlist items fetching

- (NSInteger)nonShuffledIndexFromShuffled:(NSInteger)shuffledIndex
{
    if (!mIsShuffling || (shuffledIndex<0) || ((NSUInteger) shuffledIndex >= [mShuffleIndexes count])) return shuffledIndex;
    else return [mShuffleIndexes indexOfObject:[NSNumber numberWithInteger:shuffledIndex]];
}

- (NSInteger)shuffledIndexFromNonShuffled:(NSInteger)nonShuffledIndex
{
    if (!mIsShuffling || (nonShuffledIndex<0) || ((NSUInteger) nonShuffledIndex >= [mShuffleIndexes count])) return nonShuffledIndex;
    else return [[mShuffleIndexes objectAtIndex:nonShuffledIndex] longValue];
}

- (NSURL*)nextFile
{
	if ([playlist count] <= (UInt32)(mLoadedTrackNonShuffledIndex+1)) {
		if (mIsRepeating && ([playlist count] >0))
			mLoadedTrackNonShuffledIndex = 0;
		else {
			[playlistView reloadData]; //To update playing track display
			return nil; //End of playlist reached
		}
	}
	else mLoadedTrackNonShuffledIndex++;

    if (mIsShuffling) {
        mLoadedTrackIndex = [[mShuffleIndexes objectAtIndex:mLoadedTrackNonShuffledIndex] longValue];
    }
    else mLoadedTrackIndex = mLoadedTrackNonShuffledIndex;

	[playlistView reloadData];
	return [[playlist objectAtIndex:mLoadedTrackIndex] fileURL];
}

- (NSURL*)firstFileWhenStartingPlayback
{
    if ((mLoadedTrackIndex <0)|| ((NSUInteger)mLoadedTrackIndex >= [playlist count])) return nil;

    if (mIsShuffling)
        mLoadedTrackNonShuffledIndex = [mShuffleIndexes indexOfObject:[NSNumber numberWithInteger:mLoadedTrackIndex]];
    else
        mLoadedTrackNonShuffledIndex = mLoadedTrackIndex;

    return [[playlist objectAtIndex:mLoadedTrackIndex] fileURL];
}

- (NSURL*)fileAtIndex:(NSInteger)index
{
	if ((index <0) || ((NSUInteger)index >= [playlist count])) return nil;

	return [[playlist objectAtIndex:index] fileURL];
}


- (void)refreshTableDisplay
{
	[playlistView reloadData];
}

- (void)resetPlayingPosToStart
{
    mLoadedTrackNonShuffledIndex = 0;
	mPlayingTrackIndex = mLoadedTrackIndex = [self shuffledIndexFromNonShuffled:0];
	[playlistController setSelectionIndex:mPlayingTrackIndex];
    [playlistView reloadData];
}
@end