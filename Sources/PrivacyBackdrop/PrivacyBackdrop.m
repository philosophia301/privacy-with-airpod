#import "PrivacyBackdrop.h"
#import <dlfcn.h>

// 소유 Space 수명 진단 기록. Lab과 테스트가 쓰는 debug 빌드에만 남기고 배포(release) 빌드에는 넣지 않음.
#if DEBUG
#define PBTrace(...) do { printf(__VA_ARGS__); fflush(stdout); } while (0)
#else
#define PBTrace(...) do { } while (0)
#endif

static void PBError(NSError **outError, NSString *message) {
    if (outError) *outError = [NSError errorWithDomain:@"PrivacyBackdropProbe" code:1
        userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSObject *PBFilter(BOOL variable, double radius, CGImageRef mask, NSError **error) {
    @try {
        Class filterClass = NSClassFromString(@"CAFilter");
        SEL factory = NSSelectorFromString(@"filterWithType:");
        if (![filterClass respondsToSelector:factory]) {
            PBError(error, @"Filter factory unavailable"); return nil;
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSObject *filter = [filterClass performSelector:factory withObject:variable ? @"variableBlur" : @"gaussianBlur"];
#pragma clang diagnostic pop
        if (!filter) { PBError(error, @"Requested filter unavailable"); return nil; }
        [filter setValue:@(radius) forKey:@"inputRadius"];
        [filter setValue:@YES forKey:@"inputNormalizeEdges"];
        if (variable) [filter setValue:(__bridge id)mask forKey:@"inputMaskImage"];
        return filter;
    } @catch (NSException *exception) {
        PBError(error, exception.reason ?: exception.name); return nil;
    }
}

CALayer *PBBackdrop(BOOL variable, double radius, CGImageRef mask, NSError **error) {
    @try {
        Class layerClass = NSClassFromString(@"CABackdropLayer");
        if (!layerClass) { PBError(error, @"Backdrop layer unavailable"); return nil; }
        NSObject *filter = PBFilter(variable, radius, mask, error);
        if (!filter) return nil;
        CALayer *layer = [layerClass layer];
        [layer setValue:@YES forKey:@"windowServerAware"];
        [layer setValue:@1.0 forKey:@"scale"];
        layer.filters = @[filter];
        return layer;
    } @catch (NSException *exception) {
        PBError(error, exception.reason ?: exception.name); return nil;
    }
}

BOOL PBConfigureWindow(NSWindow *window, NSError **error) {
    @try {
        // 시험 창만 조정함. 시스템 전역 설정이나 다른 앱 창에는 적용하지 않음.
        [window setValue:@NO forKey:@"shouldAutoFlattenLayerTree"];
        [window setValue:@NO forKey:@"canHostLayersInWindowServer"];
        [window setValue:@YES forKey:@"canHostLayersInWindowServer"];
        return YES;
    } @catch (NSException *exception) {
        PBError(error, exception.reason ?: exception.name); return NO;
    }
}

BOOL PBUpdateMask(CALayer *layer, CGImageRef mask, double radius, NSError **error) {
    @try {
        NSObject *filter = PBFilter(YES, radius, mask, error);
        if (!filter) return NO;
        // 기존 filter 객체 변경만으로 WindowServer 출력이 갱신되지 않아 새 값으로 commit함.
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        @try { layer.filters = @[filter]; }
        @finally { [CATransaction commit]; }
        return YES;
    } @catch (NSException *exception) {
        PBError(error, exception.reason ?: exception.name); return NO;
    }
}


// Owned auxiliary composition space; existing user Spaces are never created/destroyed here.
@implementation PBIndependentSpace {
    int32_t _connection;
    uint64_t _space;
    void (*_destroy)(int32_t, uint64_t);
    void (*_hide)(int32_t, CFArrayRef);
    void (*_show)(int32_t, CFArrayRef);
    void (*_add)(int32_t, CFArrayRef, CFArrayRef);
    void (*_remove)(int32_t, CFArrayRef, CFArrayRef);
    CFArrayRef (*_windowSpaces)(int32_t, int32_t, CFArrayRef);
}
- (instancetype)initWithError:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    typedef uint64_t (*Create)(int32_t, uintptr_t, CFDictionaryRef);
    typedef void (*Level)(int32_t, uint64_t, int32_t);
    typedef int32_t (*Connection)(void);
    Create create = (Create)dlsym(RTLD_DEFAULT, "CGSSpaceCreate");
    Level level = (Level)dlsym(RTLD_DEFAULT, "CGSSpaceSetAbsoluteLevel");
    Connection connection = (Connection)dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
    _destroy = dlsym(RTLD_DEFAULT, "CGSSpaceDestroy");
    _hide = dlsym(RTLD_DEFAULT, "CGSHideSpaces");
    _show = dlsym(RTLD_DEFAULT, "CGSShowSpaces");
    _add = dlsym(RTLD_DEFAULT, "CGSAddWindowsToSpaces");
    _remove = dlsym(RTLD_DEFAULT, "CGSRemoveWindowsFromSpaces");
    _windowSpaces = dlsym(RTLD_DEFAULT, "CGSCopySpacesForWindows");
    if (!create || !level || !connection || !_destroy || !_hide || !_show || !_add || !_remove || !_windowSpaces) {
        PBError(error, @"Auxiliary composition space API unavailable"); return nil;
    }
    _connection = connection();
    // Flag 1 requests an unmanaged space without Finder desktop content.
    _space = create(_connection, 1, NULL);
    if (!_space) { PBError(error, @"Auxiliary composition space creation failed"); return nil; }
    level(_connection, _space, 1);
    PBTrace("OWNED_SPACE CREATED %llu\n", _space);
    return self;
}
- (BOOL)attachWindow:(NSWindow *)window error:(NSError **)error {
    if (!_space || window.windowNumber <= 0) { PBError(error, @"Auxiliary space or window unavailable"); return NO; }
    NSArray *windows = @[@(window.windowNumber)], *spaces = @[@(_space)];
    CFArrayRef previous = _windowSpaces(_connection, 15, (__bridge CFArrayRef)windows);
    if (previous) { _remove(_connection, (__bridge CFArrayRef)windows, previous); CFRelease(previous); }
    _add(_connection, (__bridge CFArrayRef)windows, (__bridge CFArrayRef)spaces);
    _show(_connection, (__bridge CFArrayRef)spaces);
    CFArrayRef actual = _windowSpaces(_connection, 15, (__bridge CFArrayRef)windows);
#if DEBUG
    NSLog(@"OWNED_SPACE MEMBERSHIPS %@", (__bridge NSArray *)actual);
#endif
    BOOL attached = actual && [(__bridge NSArray *)actual containsObject:@(_space)];
    if (actual) CFRelease(actual);
    if (!attached) { PBError(error, @"Auxiliary space attachment was not confirmed"); return NO; }
    PBTrace("OWNED_SPACE ATTACHED %llu %ld\n", _space, (long)window.windowNumber);
    return YES;
}
- (void)close {
    if (!_space) return;
    uint64_t owned = _space; _space = 0;
    _hide(_connection, (__bridge CFArrayRef)@[@(owned)]);
    _destroy(_connection, owned);
    PBTrace("OWNED_SPACE DESTROYED %llu\n", owned);
}
- (void)dealloc { [self close]; }
@end
