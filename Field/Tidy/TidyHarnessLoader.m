#if DEBUG
#import <UIKit/UIKit.h>

// `-FieldTidyHarness YES` starts TidyHarness once the scene is up. It's
// Objective-C because a constructor is the one way into the app that needs
// no line in the files other tracks own. Debug builds only.

@protocol FieldTidyHarnessStarting
+ (void)start;
@end

__attribute__((constructor)) static void FieldTidyHarnessLoad(void) {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"-FieldTidyHarness"]) return;
    __block id token = [NSNotificationCenter.defaultCenter
        addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:token];
        token = nil;
        [(Class<FieldTidyHarnessStarting>)NSClassFromString(@"FieldTidyHarness") start];
    }];
}
#endif
