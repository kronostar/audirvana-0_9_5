/*
 AudioFileSndFileLoader.h

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

#include <sndfile/sndfile.h>
#include <samplerate/samplerate.h>

@interface AudioFileSndFileLoader : AudioFileLoader {
	SNDFILE *mSndFileRef;
	SF_INFO mSF_Info;

	//For libSampleRate
	SRC_STATE *mLibSrcState;
	Float32 *mTmpSRCdata;
	Float32 *mTmplibSampleRateOutBuf; //Used for Integer Mode with libSampleRate

	//For CoreAudio SRC
	AudioConverterRef mCoreAudioConverterRef;

	Float64 *mTmpSndFileSourceData; //Used for Integer mode
}

@end