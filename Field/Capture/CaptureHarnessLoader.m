#if DEBUG
#import <UIKit/UIKit.h>

// `-FieldCaptureHarness YES` starts CaptureHarness once the scene is up. It's
// Objective-C because a constructor is the one way into the app that needs
// no line in the files other tracks own. Debug builds only.

@protocol FieldCaptureHarnessStarting
+ (void)start;
@end

__attribute__((constructor)) static void FieldCaptureHarnessLoad(void) {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"-FieldCaptureHarness"]) return;
    __block id token = [NSNotificationCenter.defaultCenter
        addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:token];
        token = nil;
        [(Class<FieldCaptureHarnessStarting>)NSClassFromString(@"FieldCaptureHarness") start];
    }];
}
#endif
