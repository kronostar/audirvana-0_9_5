/*
 PlaylistArrayController.h

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

/* Playlist item PasteBoard type, mainly used for reordering drag and drop operations */
extern NSString * const AUDPlaylistItemPBoardType;
/* Undocumented in Cocoa : iTunes item */
extern NSString * const iTunesPBoardType;

@class PlaylistDocument,PlaylistView;

@interface PlaylistArrayController : NSArrayController {
	PlaylistDocument* mDocument;
	IBOutlet PlaylistView* mPlaylistView;
	IBOutlet NSButton* repeatButton;
    IBOutlet NSButton* shuffleButton;
}
- (void)setPlaylistDocument:(PlaylistDocument*)playlistdoc;
- (IBAction)trackSeek:(id)sender;
- (IBAction)toggleRepeat:(id)sender;
- (IBAction)toggleShuffle:(id)sender;
@end