/*
 CustomSliderCell.m
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

 Original code written by Damien Plisson 02/2011
 */

#import "CustomSliderCell.h"


@implementation CustomSliderCell

- (void)dealloc
{
	if (mBackgroundImage) { [mBackgroundImage release]; mBackgroundImage = nil; }
	if (mKnobImage) { [mKnobImage release]; mKnobImage = nil; }
	[super dealloc];
}

- (void)setBackgroundImage:(NSImage*)backgroundImage
{
	[backgroundImage retain];
	if (mBackgroundImage) [mBackgroundImage release];
	mBackgroundImage = backgroundImage;
}

- (void)setKnobImage:(NSImage*)knobImage
{
	[knobImage retain];
	if (mKnobImage) [mKnobImage release];
	mKnobImage = knobImage;
}

- (void)drawKnob:(NSRect)knobRect
{
	if (mKnobImage) {
		if ([self isVertical])
			[mKnobImage drawInRect:NSMakeRect(knobRect.origin.x+1,knobRect.origin.y, [mKnobImage size].width, [mKnobImage size].height)
						  fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f respectFlipped:YES hints:nil];
		else
			[mKnobImage drawInRect:NSMakeRect(knobRect.origin.x+[mKnobImage size].width-2,knobRect.origin.y+[mKnobImage size].height,
											  [mKnobImage size].width, [mKnobImage size].height)
						  fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f respectFlipped:YES hints:nil];
	}
	else {
		[super drawKnob:knobRect];
	}
}

- (void)drawBarInside:(NSRect)aRect flipped:(BOOL)flipped
{
	if (mBackgroundImage) {
		if ([self isVertical])
			[mBackgroundImage drawAtPoint:NSMakePoint(aRect.origin.x+aRect.size.width/2-[mBackgroundImage size].width/2, aRect.origin.y+1)
								 fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
		else
			[mBackgroundImage drawAtPoint:NSMakePoint(aRect.origin.x+aRect.size.width/2-[mBackgroundImage size].width/2,
													  aRect.origin.y+(flipped?1:-1)*(aRect.size.height/2-[mBackgroundImage size].height/2))
									 fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];

	}
	else {
		[super drawBarInside:aRect flipped:flipped];
	}

}

- (BOOL)_usesCustomTrackImage
{
    return YES;
}

@end