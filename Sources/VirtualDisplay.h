#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
NS_ASSUME_NONNULL_BEGIN
@interface RLVirtualDisplay : NSObject
@property(nonatomic,readonly) CGDirectDisplayID displayID;
- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height rate:(double)rate error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
