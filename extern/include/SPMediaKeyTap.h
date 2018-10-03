#include <Cocoa/Cocoa.h>
#import <IOKit/hidsystem/ev_keymap.h>
#import <Carbon/Carbon.h>

// http://overooped.com/post/2593597587/mediakeys

#define SPSystemDefinedEventMediaKeys 8

@interface SPMediaKeyTap : NSObject {
	EventHandlerRef _app_switching_ref;
	EventHandlerRef _app_terminating_ref;
	CFMachPortRef _eventPort;
	CFRunLoopSourceRef _eventPortSource;
	CFRunLoopRef _tapThreadRL;
	BOOL _shouldInterceptMediaKeyEvents;
	id _delegate;
	// The app that is frontmost in this list owns media keys
	NSMutableArray *_mediaKeyAppList;
    BOOL _interceptsVolumeControl;
}
+ (NSArray*)defaultMediaKeyUserBundleIdentifiers;

-(id)initWithDelegate:(id)delegate;

+(BOOL)usesGlobalMediaKeyTap;
-(void)startWatchingMediaKeys;
-(void)stopWatchingMediaKeys;
-(void)handleAndReleaseMediaKeyEvent:(NSEvent *)event;

@property (assign,setter = setInterceptVolumeControl:,getter = isInterceptingVolumeControl) BOOL _interceptsVolumeControl;
@end

@interface NSObject (SPMediaKeyTapDelegate)
-(void)mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event;
@end

extern NSString *kMediaKeyUsingBundleIdentifiersDefaultsKey;