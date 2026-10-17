#import "VirtualDisplay.h"
// Runtime declarations for Apple's undocumented display API; no private class is linked directly.
@interface NSObject (RLDisplayAPI)
- (id)initWithDescriptor:(id)descriptor;
- (id)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)rate;
- (BOOL)applySettings:(id)settings;
- (CGDirectDisplayID)displayID;
@end
@implementation RLVirtualDisplay { id _display; }
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height rate:(double)rate error:(NSError **)error {
    self=[super init]; if(!self) return nil;
    @try {
        Class dc=NSClassFromString(@"CGVirtualDisplayDescriptor"), vc=NSClassFromString(@"CGVirtualDisplay");
        Class sc=NSClassFromString(@"CGVirtualDisplaySettings"), mc=NSClassFromString(@"CGVirtualDisplayMode");
        if(!dc || !vc || !sc || !mc) @throw [NSException exceptionWithName:@"Unavailable" reason:@"Virtual display API is unavailable on this macOS version" userInfo:nil];
        id desc=[[dc alloc] init];
        [desc setValue:@"RetinaLink" forKey:@"name"];
        [desc setValue:@(width) forKey:@"maxPixelsWide"]; [desc setValue:@(height) forKey:@"maxPixelsHigh"];
        [desc setValue:[NSValue valueWithSize:NSMakeSize(597,336)] forKey:@"sizeInMillimeters"];
        [desc setValue:@(0x5254) forKey:@"vendorID"]; [desc setValue:@(0x1001) forKey:@"productID"];
        [desc setValue:@(0x52544C31) forKey:@"serialNum"];
        [desc setValue:dispatch_get_main_queue() forKey:@"queue"];
        _display=[[vc alloc] initWithDescriptor:desc];
        if(!_display) @throw [NSException exceptionWithName:@"Failed" reason:@"WindowServer refused to create the virtual display" userInfo:nil];
        id settings=[[sc alloc] init];
        [settings setValue:@1 forKey:@"hiDPI"];
        id mode=[[mc alloc] initWithWidth:width/2 height:height/2 refreshRate:rate];
        [settings setValue:@[mode] forKey:@"modes"];
        if(![_display applySettings:settings]) @throw [NSException exceptionWithName:@"Failed" reason:@"macOS rejected the requested display mode" userInfo:nil];
        return self;
    } @catch(NSException *ex) {
        if(error) *error=[NSError errorWithDomain:@"RetinaLink.VirtualDisplay" code:1 userInfo:@{NSLocalizedDescriptionKey:ex.reason ?: @"Virtual display creation failed"}];
        _display=nil; return nil;
    }
}
- (CGDirectDisplayID)displayID { return [_display displayID]; }
@end
