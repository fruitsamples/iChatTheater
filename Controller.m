/*
 
 File: Controller.m
 
 Abstract: The iChat Theater video source is set according the currently
           selected tab, as set by the user via the popup button.
           The SlideshowView and QTMovieView will be automatically started
           when an iChat Theater session begins.
 
 Version: 1.0
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by 
 Apple Inc. ("Apple") in consideration of your agreement to the
 following terms, and your use, installation, modification or
 redistribution of this Apple software constitutes acceptance of these
 terms.  If you do not agree with these terms, please do not use,
 install, modify or redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software. 
 Neither the name, trademarks, service marks or logos of Apple Inc. 
 may be used to endorse or promote products derived from the Apple
 Software without specific prior written permission from Apple.  Except
 as expressly stated in this notice, no other rights or licenses, express
 or implied, are granted by Apple herein, including but not limited to
 any patent rights that may be infringed by your derivative works or by
 other works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2007 Apple Inc. All Rights Reserved.
 
*/

#import "Controller.h"
#import "SlideshowView.h"
#import "DropQTMovieView.h"
#import <InstantMessage/IMService.h>
#import <InstantMessage/IMAVManager.h>
#import <QTKit/QTMovie.h>
#import <QTKit/QTTrack.h>
#import <QTKit/QTMedia.h>

#pragma mark -

@implementation Controller

#pragma mark -
#pragma mark App Lifecycle

- (void) awakeFromNib {
    // Populate _sourcePopUp with items in _sourceTabView.
    NSMenu *sourceMenu = [_sourcePopUp menu];
    [sourceMenu removeItemAtIndex:0];
    for (NSTabViewItem *tab in [_sourceTabView tabViewItems]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[tab label]
                                                      action:NULL
                                               keyEquivalent:@""];
        [item setRepresentedObject:tab];
        [sourceMenu addItem:item];
        [item release];
    }
    
    // Sync source popup and tab view.
    [_sourcePopUp selectItemAtIndex:0];
    [self selectSource:_sourcePopUp];
    
    // Subscribe to state-changed notifications, and sync initial state.
    [[IMService notificationCenter] addObserver:self
                                       selector:@selector(_stateChanged:)
                                           name:IMAVManagerStateChangedNotification
                                         object:nil];
    [self performSelector:@selector(_stateChanged:) withObject:nil];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    // We're a single-window application.
    return YES;
}

#pragma mark -
#pragma mark Actions

- (NSUInteger) _numberOfAudioChannels {
    // single channel for the slideshow pause/unpause sounds
    if ([_slideshowView window] != nil)
        return 1;
    
    // look for an audio track in the QTMovieView, promise single-channel sound
    if ([_movieView window] != nil) {
        QTMovie *movie = [_movieView movie];
        NSArray *tracks = [movie tracks];
        for (QTTrack *track in tracks)
            if ([[track media] hasCharacteristic:QTMediaCharacteristicAudio])
                return 1;
    }

    // no audio found
    return 0;
}

- (void) _setOptimizationOptions {
    // The "stills" optimization option is specified in the nib via the tab identifier.
    IMVideoOptimizationOptions options = IMVideoOptimizationDefault;
    if ([[[_sourceTabView selectedTabViewItem] identifier] isEqualToString:@"stills"])
        options |= IMVideoOptimizationStills;
    
    // The "replacement" option is set by the menu item
    if (_replaceVideo)
        options |= IMVideoOptimizationReplacement;
    
    [[IMAVManager sharedAVManager] setVideoOptimizationOptions:options];
}

- (void) _stateChanged:(NSNotification *)aNotification {
    // Read the state.
    IMAVManager *avManager = [IMAVManager sharedAVManager];
    IMAVManagerState state = [avManager state];
    
    // Update the play button based on the state.
    [_playStopButton setState:((state >= IMAVStartingUp) ? NSOnState : NSOffState)];
    [_playStopButton setEnabled:(state >= IMAVPending || state == IMAVStopped)];
    
    // The slideshow and QuickTime movie should be automatically started when the session begins.
    id videoDataSource = [avManager videoDataSource];
    if (videoDataSource == _slideshowView) {
        if (state == IMAVRunning)
            [_slideshowView start];
        else
            [_slideshowView stop];
    } else if (videoDataSource == _movieView) {
        if (state == IMAVRunning)
            [_movieView play:nil];
    }
}

- (void) setMovie:(QTMovie *)aMovie {
    [_movieView setMovie:aMovie];
    
    // the audio may have changed
    IMAVManager *avManager = [IMAVManager sharedAVManager];
    [avManager setNumberOfAudioChannels:[self _numberOfAudioChannels]];
    
    if ([avManager state] == IMAVRunning)
        [_movieView play:nil];
}

- (IBAction) selectSource:(id)sender {
    // Select the tab.
    NSTabViewItem *tab = [[sender selectedItem] representedObject];
    [_sourceTabView selectTabViewItem:tab];
    
    // re-configure the AV manager
    [self _setOptimizationOptions];
    IMAVManager *avManager = [IMAVManager sharedAVManager];
    [avManager setNumberOfAudioChannels:[self _numberOfAudioChannels]];
    id videoDataSource = [[_sourceTabView selectedTabViewItem] initialFirstResponder];
    [avManager setVideoDataSource:videoDataSource];
    
    // manage the app
    if ([avManager state] == IMAVRunning) {
        // start/stop the slideshow as appropriate
        if (videoDataSource == _slideshowView)
            [_slideshowView start];
        else
            [_slideshowView stop];
        
        // start/pause the movie as appropriate
        if (videoDataSource == _movieView)
            [_movieView play:nil];
        else
            [_movieView pause:nil];
    }
}

- (IBAction) playStop:(id)sender {
    IMAVManager *avManager = [IMAVManager sharedAVManager];
    
    if ([avManager state] == IMAVStopped)
        [avManager start];
    else
        [avManager stop];
}

- (IBAction) toggleReplaceVideo:(id)sender {
    _replaceVideo = !_replaceVideo;
    [self _setOptimizationOptions];
}

- (BOOL) validateMenuItem:(NSMenuItem *)item {
    SEL action = [item action];
    IMAVManagerState state = [[IMAVManager sharedAVManager] state];
    
    if (action == @selector(playStop:)) {
        [item setTitle:((state >= IMAVPending) ? NSLocalizedString(@"Stop Sharing With iChat Theater", @"Menu title: stop iChat Theater")
                                               : NSLocalizedString(@"Share With iChat Theater", @"Menu title: start iChat Theater"))];
        return (state >= IMAVPending || state == IMAVStopped);
        
    } else if (action == @selector(toggleReplaceVideo:)) {
        [item setState:(_replaceVideo ? NSOnState : NSOffState)];
        return YES;
        
    } else if (action == @selector(selectSource:)) {
        return YES;
    }
    
    return NO;
}

@end
