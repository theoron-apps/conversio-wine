#!/usr/bin/env python3
"""Compile the actual patched update method against AppKit; no game input injection.
Usage: python3 check.py /path/to/patched/wine
"""
import pathlib, subprocess, sys, tempfile
s=(pathlib.Path(sys.argv[1])/'dlls/winemac.drv/cocoa_app.m').read_text()
helper=s[s.index('static NSCursor* transparent_cursor'):s.index('@implementation WineApplication\n')]
method=s[s.index('    - (void) updateCursor:(BOOL)force'):s.index('    - (void) hideCursor')]
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
@interface CursorTest : NSObject {
@public BOOL clientWantsCursorHidden, cursorHidden, cursorIsCurrent;
id lastTargetWindow; NSCursor* cursor;
}
-(void)handleCommandTab;
-(id)frontWineWindow;
-(void)updateCursor:(BOOL)force;
@end
'''+helper+'\n@implementation CursorTest\n-(void)handleCommandTab {}\n-(id)frontWineWindow { return nil; }\n'+method+dispatch_method+'''@end
int main(void) { @autoreleasepool {
 [NSApplication sharedApplication];
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
 puts("PASS: visible, hidden, AppKit reset, exit/re-entry, 1000 toggles, changed visible frame");
} }
'''
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d); (p/'check.m').write_text(code)
 subprocess.run(['clang','-arch','x86_64','-fblocks','-framework','AppKit','-framework','Carbon',str(p/'check.m'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
