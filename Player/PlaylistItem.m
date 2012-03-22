/*
 PlaylistItem.m

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


@implementation PlaylistItem
@synthesize fileURL,title,artist,composer,album,lengthFrames,trackNumber,durationInSeconds;

- (id) init
{
	[super init];
	lengthFrames = 0;
	trackNumber = 0;
	durationInSeconds = (float)0.0;
	fileURL = nil;
	title = nil;
	artist = nil;
	composer = nil;
	album = nil;
	return self;
}

- (void) dealloc
{
	if (fileURL) [fileURL release];
	if (title) [title release];
	if (artist) [artist release];
	if (composer) [composer release];
	if (album) [album release];
	[super dealloc];
}

#pragma mark Archival
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:fileURL forKey:@"fileURL"];
	[coder encodeObject:title forKey:@"title"];
	[coder encodeObject:artist forKey:@"artist"];
	[coder encodeObject:composer forKey:@"composer"];
	[coder encodeObject:album forKey:@"album"];
	[coder encodeInt64:lengthFrames forKey:@"lengthFrames"];
	[coder encodeInt64:trackNumber forKey:@"trackNumber"];
	[coder encodeFloat:durationInSeconds forKey:@"durationInSeconds"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	[super init];
	fileURL = [[coder decodeObjectForKey:@"fileURL"] retain];
	title = [[coder decodeObjectForKey:@"title"] retain];
	artist = [[coder decodeObjectForKey:@"artist"] retain];
	composer = [[coder decodeObjectForKey:@"composer"] retain];
	album = [[coder decodeObjectForKey:@"album"] retain];
	lengthFrames = [coder decodeInt64ForKey:@"lengthFrames"];
	trackNumber = (UInt64)[coder decodeInt64ForKey:@"trackNumber"];
	durationInSeconds = [coder decodeFloatForKey:@"durationInSeconds"];
	return self;
}
@end