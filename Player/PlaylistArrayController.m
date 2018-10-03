/*
 PlaylistArrayController.m

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

#import "PlaylistItem.h"
#import "PlaylistArrayController.h"
#import	"PlaylistDocument.h"

//Internal drag and drop type
NSString * const AUDPlaylistItemPBoardType = @"fr.dplisson.audirvana.playlistitemtype";
NSString * const iTunesPBoardType = @"CorePasteboardFlavorType 0x6974756E";

@interface PlaylistArrayController (Notifications)
- (void)handleUpdateRepeatStatus:(NSNotification*)notification;
- (void)handleUpdateShuffleStatus:(NSNotification*)notification;
@end

@implementation PlaylistArrayController

- (void)awakeFromNib
{
	[mPlaylistView setDoubleAction:@selector(trackSeek:)];
	[mPlaylistView setTarget:self];

	//Add playlist changes listeners
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(handleUpdateRepeatStatus:)
			   name:AUDTogglePlaylistRepeat object:nil];
	[nc addObserver:self selector:@selector(handleUpdateShuffleStatus:)
			   name:AUDTogglePlaylistShuffle object:nil];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (void)setPlaylistDocument:(PlaylistDocument*)playlistdoc
{
	mDocument = playlistdoc;
}

- (void)setSortDescriptors:(NSArray *)array
{
	//Do nothing, to prevent the user from sorting the playlist
}


#pragma mark add/remove/seek operations
- (IBAction)add:(id)sender
{
	[mDocument addPlaylistItems];
}

- (IBAction)remove:(id)sender
{
	[mDocument removePlaylistItems:[mPlaylistView selectedRowIndexes]];
}

- (IBAction)trackSeek:(id)sender
{
	[mDocument changePlayingTrack:[mPlaylistView clickedRow]];
}

- (IBAction)toggleRepeat:(id)sender
{
	[mDocument setIsRepeating:![mDocument isRepeating]];
}

- (IBAction)toggleShuffle:(id)sender
{
    [mDocument setIsShuffling:![mDocument isShuffling]];
}

- (void)handleUpdateRepeatStatus:(NSNotification*)notification
{
	[repeatButton setState:[mDocument isRepeating]];
}

- (void)handleUpdateShuffleStatus:(NSNotification*)notification
{
	[shuffleButton setState:[mDocument isShuffling]];
}

#pragma mark Drag and drop operations

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
    // Copy the row numbers to the pasteboard.
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
    [pboard declareTypes:[NSArray arrayWithObject:AUDPlaylistItemPBoardType] owner:self];
    [pboard setData:data forType:AUDPlaylistItemPBoardType];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op
{
    if ([info draggingSource] == tv)
		return NSDragOperationMove; //Internal drag is a move operation
	else
		return NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id <NSDraggingInfo>)info
			  row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	BOOL success = NO;
    NSPasteboard* pboard = [info draggingPasteboard];

	if ([info draggingSource] == aTableView) {
		// Internal drag: Move the specified row to its new location...
		NSData* rowData = [pboard dataForType:AUDPlaylistItemPBoardType];

		[mDocument movePlaylistItems:[NSKeyedUnarchiver unarchiveObjectWithData:rowData] toRow:row];
		success = YES;
	} else {
		//External drop
		NSArray* droppedTypes = [pboard types];

		if ([droppedTypes containsObject:iTunesPBoardType]) {
			NSDictionary *iTunesDroppedData = [[info draggingPasteboard] propertyListForType:iTunesPBoardType];
			NSDictionary *iTunesTracks = [iTunesDroppedData objectForKey:@"Tracks"];
			NSDictionary *playlistDropped = [[iTunesDroppedData objectForKey:@"Playlists"] objectAtIndex:0];
			NSArray *tracksIndexes = [playlistDropped objectForKey:@"Playlist Items"];
			NSURL *trackFileUrl;
			NSMutableArray *droppedURLs = [[[NSMutableArray alloc] initWithCapacity:[tracksIndexes count]] autorelease];

			for(NSDictionary *iTunesTrackNumber in tracksIndexes) {
				NSNumber *trackNum = [iTunesTrackNumber objectForKey:@"Track ID"];
				NSDictionary *track = [iTunesTracks objectForKey:[trackNum stringValue]];
				trackFileUrl = [NSURL URLWithString:[track objectForKey:@"Location"]];
				if([trackFileUrl isFileURL])
					[droppedURLs addObject:trackFileUrl];
			}
			if ([droppedURLs count] > 0) {
				[mDocument insertPlaylistItems:droppedURLs atRow:row sortToplist:NO];
				success = YES;
			}
		} else if ([droppedTypes containsObject:NSFilenamesPboardType]) {
			NSArray* droppedFiles = [pboard propertyListForType:NSFilenamesPboardType];
			NSMutableArray *droppedURLs = [[[NSMutableArray alloc] initWithCapacity:[droppedFiles count]] autorelease];

			for (NSString* filename in droppedFiles) {
				[droppedURLs addObject:[NSURL fileURLWithPath:filename]];
			}
			[mDocument insertPlaylistItems:droppedURLs atRow:row sortToplist:YES];
			success = YES;
		} else if ([droppedTypes containsObject:NSURLPboardType]) {
			NSURL* droppedURL = [NSURL URLFromPasteboard:pboard];
			if ([droppedURL isFileURL]) {
				[mDocument insertPlaylistItems:[NSArray arrayWithObject:droppedURL] atRow:row sortToplist:YES];
				success = YES;
			}
		}
	}
	return success;
}

@end