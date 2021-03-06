/*
 PlaylistItem.h

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


@interface PlaylistItem : NSObject {
	NSURL *fileURL;
	NSString *title;
	NSString *artist;
	NSString *composer;
	NSString *album;
	UInt64 trackNumber;
	SInt64 lengthFrames;
	float durationInSeconds;
}
@property (readwrite, copy) NSURL *fileURL;
@property (readwrite, copy) NSString *title;
@property (readwrite, copy) NSString *artist;
@property (readwrite, copy) NSString *composer;
@property (readwrite, copy) NSString *album;
@property (readwrite) SInt64 lengthFrames;
@property (readwrite) UInt64 trackNumber;
@property (readwrite) float durationInSeconds;
@end