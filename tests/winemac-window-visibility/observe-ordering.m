/* Diagnostic only: observe the real inputs; never hide or reorder a sibling.
 * Catch the known exception so Wine can process the automatic close timer.
 * The regression suite must also run without this module. */
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <stdio.h>

static IMP original;

static void observe_order(id self, SEL selector, NSWindow *prev, NSWindow *next, BOOL activate)
{
    BOOL target = [[self title] hasPrefix:@"Conversio visibility dialog"];
    if (target)
        fprintf(stderr, "ORDER target=%ld prev=%ld visible=%d minimized=%d next=%ld visible=%d\n",
            (long)[self windowNumber], (long)[prev windowNumber], [prev isVisible],
            [prev isMiniaturized], (long)[next windowNumber], [next isVisible]);
    @try
    {
        ((void (*)(id, SEL, NSWindow *, NSWindow *, BOOL))original)(self, selector, prev, next, activate);
        if (target) fprintf(stderr, "ORDER returned visible=%d\n", [self isVisible]);
    }
    @catch (NSException *exception)
    {
        if (!target) @throw;
        fprintf(stderr, "ORDER exception=%s reason=%s visible=%d\n",
            [[exception name] UTF8String], [[exception reason] UTF8String], [self isVisible]);
        NSEnableScreenUpdates();
    }
    fflush(stderr);
}

static void loaded(const struct mach_header *image, intptr_t slide)
{
    if (original) return;
    Class cls = objc_getClass("WineWindow");
    Method method = class_getInstanceMethod(cls, sel_registerName("orderBelow:orAbove:activate:"));
    if (method) original = method_setImplementation(method, (IMP)observe_order);
}

__attribute__((constructor)) static void initialize(void)
{
    _dyld_register_func_for_add_image(loaded);
}
