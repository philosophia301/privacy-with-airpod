#import "BackdropSPI.h"

static uint32_t diagnosticBackdropFlags = 0;
void PBSetDiagnosticBackdropFlags(uint32_t flags) { diagnosticBackdropFlags = flags; }

static void PBError(NSError **outError, NSString *message) {
    if (outError) *outError = [NSError errorWithDomain:@"PrivacyBackdropProbe" code:1
        userInfo:@{NSLocalizedDescriptionKey: message}];
}

CALayer *PBDiagnosticBackdrop(BOOL variable, double radius, CGImageRef mask, NSError **error) {
    CALayer *layer = PBBackdrop(variable, radius, mask, error);
    if (!layer) return nil;
    @try {
        if (diagnosticBackdropFlags & 1) [layer setValue:@YES forKey:@"ignoresScreenClip"];
        if (diagnosticBackdropFlags & 2) [layer setValue:@YES forKey:@"preallocatesScreenArea"];
        return layer;
    } @catch (NSException *exception) { PBError(error, exception.reason ?: exception.name); return nil; }
}

#import <dlfcn.h>
BOOL PBSwipeTag(NSWindow *window, uint32_t upperBits, NSError **error) {
    @try {
        typedef int32_t (*SetTags)(int32_t, int32_t, const uint32_t *, int32_t);
        SetTags setTags = (SetTags)dlsym(RTLD_DEFAULT, "CGSSetWindowTags");
        if (!setTags) { PBError(error, @"CGSSetWindowTags unavailable"); return NO; }
        NSNumber *connection = [NSApp valueForKey:@"contextID"];
        uint32_t tags[2] = {0, upperBits};
        int32_t result = setTags(connection.intValue, (int32_t)window.windowNumber, tags, 64);
        if (result != 0) { PBError(error, [NSString stringWithFormat:@"Window tag error %d", result]); return NO; }
        return YES;
    } @catch (NSException *exception) {
        PBError(error, exception.reason ?: exception.name); return NO;
    }
}

@interface PBProbeView : NSView
@end
@implementation PBProbeView
- (BOOL)_shouldAutoFlattenLayerTree { return NO; }
@end
NSView *PBUnflattenedView(NSRect frame) { return [[PBProbeView alloc] initWithFrame:frame]; }

static NSUInteger PBTuneLayer(CALayer *layer, NSArray *filters) {
    NSUInteger found = 0;
    if ([layer isKindOfClass:NSClassFromString(@"CABackdropLayer")]) {
        layer.filters = filters;
        found++;
    }
    if ([@[@"fill", @"tone", @"Chameleon"] containsObject:layer.name]) layer.opacity = 0;
    for (CALayer *child in layer.sublayers) found += PBTuneLayer(child, filters);
    return found;
}
BOOL PBTuneNative(NSView *view, double radius, CGImageRef mask, NSError **error) {
    @try {
        CALayer *candidate = PBDiagnosticBackdrop(YES, radius, mask, error);
        if (!candidate) return NO;
        if (!PBTuneLayer(view.layer, candidate.filters)) {
            PBError(error, @"Native backdrop not found"); return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        PBError(error, exception.reason ?: exception.name); return NO;
    }
}

BOOL PBWindowBlur(NSWindow *window, NSInteger radius, NSError **error) {
    typedef void *(*MainConnection)(void);
    typedef int32_t (*SetBlur)(void *, NSInteger, int64_t);
    MainConnection connection = (MainConnection)dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
    SetBlur blur = (SetBlur)dlsym(RTLD_DEFAULT, "CGSSetWindowBackgroundBlurRadius");
    if (!connection || !blur) { PBError(error, @"Window blur API unavailable"); return NO; }
    int32_t result = blur(connection(), window.windowNumber, radius);
    if (result) { PBError(error, [NSString stringWithFormat:@"Window blur error %d", result]); return NO; }
    return YES;
}

#import <mach/mach_time.h>
static void PBTraceClip(NSWindow *window, int32_t connection) {
    typedef int32_t (*CopyClip)(int32_t, int32_t, CFTypeRef *);
    typedef int32_t (*Bounds)(CFTypeRef, CGRect *);
    typedef int32_t (*Release)(CFTypeRef);
    CopyClip copy = (CopyClip)dlsym(RTLD_DEFAULT, "CGSCopyWindowClipShape");
    Bounds bounds = (Bounds)dlsym(RTLD_DEFAULT, "CGSGetRegionBounds");
    Release release = (Release)dlsym(RTLD_DEFAULT, "CGSReleaseRegion");
    if (!copy || !bounds || !release) { printf("CLIP UNAVAILABLE\n"); return; }
    CFTypeRef region = NULL; CGRect rect = CGRectNull;
    int32_t result = copy(connection, (int32_t)window.windowNumber, &region);
    int32_t boundResult = region && !result ? bounds(region, &rect) : -1;
    if (region) release(region);
    printf("CLIP %llu %ld %d %d %.3f %.3f %.3f %.3f\n", mach_absolute_time(), (long)window.windowNumber,
           result, boundResult, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    fflush(stdout);
}

BOOL PBTraceWindow(NSWindow *window, NSError **error) {
    @try {
        typedef int32_t (*GetTransform)(int32_t, int32_t, CGAffineTransform *);
        GetTransform get = (GetTransform)dlsym(RTLD_DEFAULT, "CGSGetCatenatedWindowTransform");
        if (!get) { PBError(error, @"Window transform API unavailable"); return NO; }
        NSNumber *connection = [NSApp valueForKey:@"contextID"];
        CGAffineTransform transform = CGAffineTransformIdentity;
        int32_t result = get(connection.intValue, (int32_t)window.windowNumber, &transform);
        if (result) { PBError(error, @"Window transform read failed"); return NO; }
        printf("TRANSFORM %llu %ld %.5f %.5f %.5f %.5f %.3f %.3f\n", mach_absolute_time(), (long)window.windowNumber,
            transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty);
        if (diagnosticBackdropFlags & 8) PBTraceClip(window, connection.intValue);
        return YES;
    } @catch (NSException *exception) {
        PBError(error, exception.reason ?: exception.name); return NO;
    }
}

BOOL PBPositionBackdrop(NSWindow *window, CALayer *layer, double period, NSError **error) {
    @try {
        typedef int32_t (*GetTransform)(int32_t, int32_t, CGAffineTransform *);
        GetTransform get = (GetTransform)dlsym(RTLD_DEFAULT, "CGSGetCatenatedWindowTransform");
        if (!get) { PBError(error, @"Window transform API unavailable"); return NO; }
        NSNumber *connection = [NSApp valueForKey:@"contextID"];
        CGAffineTransform transform = CGAffineTransformIdentity;
        if (get(connection.intValue, (int32_t)window.windowNumber, &transform)) {
            PBError(error, @"Window transform read failed"); return NO;
        }
        if (transform.a != 1 || transform.d != 1 || transform.b != 0 || transform.c != 0) {
            PBError(error, [NSString stringWithFormat:@"Unsupported transform %.6f %.6f %.6f %.6f %.3f %.3f", transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]); return NO;
        }
        double offset = transform.tx + window.frame.origin.x;
        if (period > 0) offset = remainder(offset, period);
        if (layer.affineTransform.tx == offset) return YES;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        layer.affineTransform = CGAffineTransformMakeTranslation(offset, 0);
        [CATransaction commit];
        return YES;
    } @catch (NSException *exception) {
        PBError(error, exception.reason ?: exception.name); return NO;
    }
}


BOOL PBPinDiagnosticWindowMesh(NSWindow *window, NSError **error) {
    // CGS mesh ABI uses float pairs, including on 64-bit macOS.
    typedef struct { float x, y; } Point;
    typedef struct { Point local, global; } WarpPoint;
    typedef int32_t (*SetWarp)(int32_t, int32_t, int, int, const WarpPoint *);
    SetWarp set = (SetWarp)dlsym(RTLD_DEFAULT, "CGSSetWindowWarp");
    if (!set) { PBError(error, @"Window mesh API unavailable"); return NO; }
    @try {
        NSNumber *connection = [NSApp valueForKey:@"contextID"];
        NSRect frame = window.frame;
        float x = frame.origin.x, y = NSMaxY(NSScreen.screens.firstObject.frame) - NSMaxY(frame);
        float w = frame.size.width, h = frame.size.height;
        WarpPoint mesh[4] = {{{0,0},{x,y}}, {{w,0},{x+w,y}}, {{0,h},{x,y+h}}, {{w,h},{x+w,y+h}}};
        int32_t result = set(connection.intValue, (int32_t)window.windowNumber, 2, 2, mesh);
        if (result) { PBError(error, [NSString stringWithFormat:@"Window mesh error %d", result]); return NO; }
        return YES;
    } @catch (NSException *exception) { PBError(error, exception.reason ?: exception.name); return NO; }
}


BOOL PBRebaseDiagnosticWindow(NSWindow *window, double screenWidth, double period, NSError **error) {
    typedef int32_t (*GetTransform)(int32_t, int32_t, CGAffineTransform *);
    GetTransform get = (GetTransform)dlsym(RTLD_DEFAULT, "CGSGetCatenatedWindowTransform");
    if (!get) { PBError(error, @"Window transform API unavailable"); return NO; }
    @try {
        NSNumber *connection = [NSApp valueForKey:@"contextID"];
        CGAffineTransform t = CGAffineTransformIdentity;
        if (get(connection.intValue, (int32_t)window.windowNumber, &t)) {
            PBError(error, @"Rebase transform read failed"); return NO;
        }
        if (t.a != 1 || t.d != 1 || t.b != 0 || t.c != 0 || !isfinite(t.tx)) {
            PBError(error, @"Rebase requires a finite translation"); return NO;
        }
        double target = (window.frame.size.width - screenWidth) / 2;
        double shift = round((t.tx - target) / period) * period;
        if (shift == 0) return YES;
        NSPoint origin = window.frame.origin;
        origin.x += shift;
        [window setFrameOrigin:origin];
        printf("REBASE %llu %ld %.3f %.3f\n", mach_absolute_time(), (long)window.windowNumber, t.tx, shift);
        return YES;
    } @catch (NSException *exception) { PBError(error, exception.reason ?: exception.name); return NO; }
}
