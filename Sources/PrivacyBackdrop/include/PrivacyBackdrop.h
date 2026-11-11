#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
NS_ASSUME_NONNULL_BEGIN
CALayer * _Nullable PBBackdrop(BOOL variable, double radius, CGImageRef mask, NSError **error);
BOOL PBConfigureWindow(NSWindow *window, NSError **error);
BOOL PBUpdateMask(CALayer *layer, CGImageRef mask, double radius, NSError **error);
@interface PBIndependentSpace : NSObject
- (nullable instancetype)initWithError:(NSError **)error;
- (BOOL)attachWindow:(NSWindow *)window error:(NSError **)error;
- (void)close;
@end
NS_ASSUME_NONNULL_END
