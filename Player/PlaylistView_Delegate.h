/*
 PlaylistView_Delegate.h

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

#import <Cocoa/Cocoa.h>

@class PlaylistDocument;

@interface PlaylistView_Delegate : NSObject <NSTableViewDelegate> {
	PlaylistDocument *document;
}
-(void)setDocument:(PlaylistDocument*)mydoc;
@end