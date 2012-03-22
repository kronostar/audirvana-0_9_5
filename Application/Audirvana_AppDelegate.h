//
//  Audirvana_AppDelegate.h
//  Audirvana
//
//  Created by Damien Plisson on 03/08/10.
//  Copyright __MyCompanyName__ 2010 . All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PlaylistDocument;
@class AppController;

@interface Audirvana_AppDelegate : NSObject
{
    NSWindow *window;

	PlaylistDocument *playlistDoc;
    AppController *appController;

    NSPersistentStoreCoordinator *persistentStoreCoordinator;
    NSManagedObjectModel *managedObjectModel;
    NSManagedObjectContext *managedObjectContext;

	bool openedWithFile;
}

@property (nonatomic, retain) IBOutlet NSWindow *window;

@property (nonatomic, retain, readonly) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, retain, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, retain, readonly) NSManagedObjectContext *managedObjectContext;

- (IBAction)saveAction:sender;
- (void)setPlaylistDocument:(PlaylistDocument*)plDoc;
- (void)setAppController:(AppController*)appCtrl;

@end