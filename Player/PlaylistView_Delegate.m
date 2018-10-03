/*
 PlaylistView_Delegate.m

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

 Original code written by Damien Plisson 09/2010 */

#import "PlaylistView_Delegate.h"
#import "PlaylistDocument.h"


@implementation PlaylistView_Delegate

-(void)setDocument:(PlaylistDocument*)mydoc
{
	document = mydoc;
}

-(NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSTextFieldCell *cell = [tableColumn dataCell];
	if(document) {
		if (row == [document playingTrackIndex]) {
			[cell setTextColor: [NSColor colorWithCalibratedRed:0.0f green:0.0f blue:0.4f alpha:1.0f]];
			[cell setFont:[NSFont boldSystemFontOfSize:10.0f]];
		} else if (row == [document loadedTrackIndex]) {
			[cell setTextColor: [NSColor colorWithCalibratedRed:0.0f green:0.4f blue:0.0f alpha:1.0f]];
			[cell setFont:[NSFont systemFontOfSize:10.0f]];
		} else {
			[cell setTextColor: [NSColor blackColor]];
			[cell setFont:[NSFont systemFontOfSize:10.0f]];
		}
	}
	else [cell setTextColor: [NSColor blackColor]];

	return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	NSTableView *tableView = [aNotification object];

	NSDictionary *plTrackDict = [NSDictionary dictionaryWithObject:[NSNumber numberWithLong:[tableView selectedRow]] forKey:@"index"];
	[[NSNotificationCenter defaultCenter] postNotificationName:AUDPlaylistSelectionCursorChangedNotification
														object:self userInfo:plTrackDict];
}

@end