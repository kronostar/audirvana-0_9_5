/*
 AudioFileFLACLoader.h

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

 Original code written by Damien Plisson 08/2010
 */


#import "AudioFileLoader.h"
#include <FLAC/stream_decoder.h>
#include <samplerate/samplerate.h>

@interface AudioFileFLACLoader : AudioFileLoader {
	FLAC__StreamDecoder *mFLACStreamDecoder;

	int mFLACchannels;
	int mFLACmaxBlockSize;

	//Private data used by the FLAC decoding callback
	UInt64 mFLACreadFrames;
	UInt64 mFLACtmpInt32bufUnreadFrames;
    UInt64 mFLACbufferSizeInBytes;
	UInt32 mFLACLoadedSeconds;
	Float32 *mFLACbufferData;
	Float32 *tmpSRCbuf;
	Float32 *tmplibSampleRateOutBuf; //Used for Integer Mode with libSampleRate
	SInt32 *tmpInt32buf; //Used for Integer mode with no SRC
	SRC_STATE *mlibSrcState;
	AudioConverterRef mCoreAudioConverterRef;
}
@property (readonly,getter=FLACmaxBlockSize) int mFLACmaxBlockSize;
@end