#import "../../Sources/PrivacyBackdrop/include/PrivacyBackdrop.h"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
NS_ASSUME_NONNULL_BEGIN
void PBSetDiagnosticBackdropFlags(uint32_t flags);
BOOL PBRebaseDiagnosticWindow(NSWindow *window, double screenWidth, double period, NSError **error);
BOOL PBPinDiagnosticWindowMesh(NSWindow *window, NSError **error);
CALayer * _Nullable PBDiagnosticBackdrop(BOOL variable, double radius, CGImageRef mask, NSError **error);
BOOL PBSwipeTag(NSWindow *window, uint32_t upperBits, NSError **error);
NSView *PBUnflattenedView(NSRect frame);
BOOL PBTuneNative(NSView *view, double radius, CGImageRef mask, NSError **error);
BOOL PBWindowBlur(NSWindow *window, NSInteger radius, NSError **error);
BOOL PBTraceWindow(NSWindow *window, NSError **error);
BOOL PBPositionBackdrop(NSWindow *window, CALayer *layer, double period, NSError **error);
NS_ASSUME_NONNULL_END
