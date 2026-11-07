#!/usr/bin/env python3
"""Compile the actual patched update method against AppKit; no game input injection.
Usage: python3 check.py /path/to/patched/wine
"""
import pathlib, subprocess, sys, tempfile
s=(pathlib.Path(sys.argv[1])/'dlls/winemac.drv/cocoa_app.m').read_text()
helper=s[s.index('static NSCursor* transparent_cursor'):s.index('@implementation WineApplication\n')]
method=s[s.index('    - (void) updateCursor:(BOOL)force'):s.index('    - (void) hideCursor')]
presentation=s[s.index('    - (void) updateCursorPresentation\n'):s.index('    - (void) updateCursor:(BOOL)force')]
visibility=s[s.index('    - (void) hideCursor\n'):s.index('    - (void) setCursor:(NSCursor*)newCursor')]
dispatch_method=s[s.index('    - (void) didSendEvent:(NSEvent*)anEvent\n'):s.index('    - (void) setupObservations\n    {')]
assert 'clientWantsCursorHidden' in dispatch_method
assert 'frontWineWindow' not in method  # No WindowServer enumeration per input event.
assert '[NSCursor hide]' not in method and '[NSCursor unhide]' not in method
code='''#import <AppKit/AppKit.h>
#include <assert.h>
#import <Carbon/Carbon.h>
@interface NSObject (FullscreenTestDeclaration)
-(BOOL)isFullscreen;
@end
@interface TestApplication : NSObject
@property BOOL active;
@property NSApplicationPresentationOptions presentationOptions;
-(BOOL)isActive;
@end
@implementation TestApplication
-(BOOL)isActive { return self.active; }
@end
static TestApplication* testApplication;
#define NSApp testApplication
@interface CursorTest : NSObject {
@public BOOL clientWantsCursorHidden, cursorHidden, cursorIsCurrent;
BOOL fullscreen;
id lastTargetWindow; NSCursor* cursor;
}
-(void)handleCommandTab;
-(id)frontWineWindow;
-(void)updateCursor:(BOOL)force;
-(void)updateCursorPresentation;
@end
'''+helper+'\n@implementation CursorTest\n-(void)handleCommandTab {}\n-(id)frontWineWindow { return self; }\n-(BOOL)isFullscreen { return fullscreen; }\n'+presentation+method+visibility+dispatch_method+'''@end
int main(void) { @autoreleasepool {
 [NSApplication sharedApplication];
 testApplication=[TestApplication new];
 testApplication.presentationOptions=NSApplicationPresentationDisableCursorLocationAssistance;
 CursorTest* t=[CursorTest new];
 t->cursor=[NSCursor crosshairCursor]; t->lastTargetWindow=t;
 [t updateCursor:NO]; assert([NSCursor currentCursor]==t->cursor);
 t->clientWantsCursorHidden=YES; [t updateCursor:NO];
 assert(t->cursorHidden && [NSCursor currentCursor]==transparent_cursor());
 [[NSCursor arrowCursor] set]; [t updateCursor:NO];
 assert([NSCursor currentCursor]==transparent_cursor());
 t->lastTargetWindow=nil; [t updateCursor:NO];
 assert(!t->cursorHidden && [NSCursor currentCursor]==[NSCursor arrowCursor]);
 t->lastTargetWindow=t; [t updateCursor:NO];
 assert([NSCursor currentCursor]==transparent_cursor());
 for(int i=0;i<1000;i++) {
   t->clientWantsCursorHidden=NO; [t updateCursor:NO];
   assert(!t->cursorHidden && [NSCursor currentCursor]==t->cursor);
   t->clientWantsCursorHidden=YES; [t updateCursor:NO];
   assert(t->cursorHidden && [NSCursor currentCursor]==transparent_cursor());
 }
 t->clientWantsCursorHidden=NO; t->cursor=[NSCursor pointingHandCursor];
 [t updateCursor:NO]; assert([NSCursor currentCursor]==t->cursor);
 t->lastTargetWindow=nil; [t updateCursor:NO];
 assert([NSCursor currentCursor]==[NSCursor arrowCursor]);
 t->lastTargetWindow=t; t->fullscreen=YES; testApplication.active=YES;
 [t hideCursor];
 NSApplicationPresentationOptions mask=NSApplicationPresentationHideDock|NSApplicationPresentationHideMenuBar;
 assert((testApplication.presentationOptions&mask)==mask);
 testApplication.active=NO; [t updateCursorPresentation];
 assert(!(testApplication.presentationOptions&mask));
 testApplication.active=YES; [t updateCursorPresentation];
 assert((testApplication.presentationOptions&mask)==mask);
 t->fullscreen=NO; [t updateCursorPresentation];
 assert(!(testApplication.presentationOptions&mask));
 t->fullscreen=YES; [t updateCursorPresentation]; [t unhideCursor];
 assert(!(testApplication.presentationOptions&mask));
 assert(testApplication.presentationOptions&NSApplicationPresentationDisableCursorLocationAssistance);
 puts("PASS: visible, hidden, AppKit reset, exit/re-entry, 1000 toggles, changed visible frame");
 puts("PASS: fullscreen Dock/menu suppression, activation/exit restore, unrelated options retained");
} }
'''
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d); (p/'check.m').write_text(code)
 subprocess.run(['clang','-arch','x86_64','-fblocks','-framework','AppKit','-framework','Carbon',str(p/'check.m'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
