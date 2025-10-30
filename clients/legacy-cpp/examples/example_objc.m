/**
 * Objective-C Usage Example
 */

#import <Foundation/Foundation.h>
#import "passgfw.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"PassGFW Objective-C Example");
        NSLog(@"============================");
        
        // 1. Create detector
        PassGFWDetector* detector = passgfw_create();
        if (!detector) {
            NSLog(@"Failed to create detector");
            return 1;
        }
        
        // 2. Optional: Add custom URL
        // passgfw_add_url(detector, "https://custom.example.com/check");
        
        // 3. Run in background queue (blocking operation)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            char domain[256];
            
            NSLog(@"Starting server detection...");
            
            if (passgfw_get_final_server(detector, domain, sizeof(domain)) == 0) {
                NSString* domainStr = [NSString stringWithUTF8String:domain];
                NSLog(@"✅ Found available server: %@", domainStr);
            } else {
                char error[256];
                if (passgfw_get_last_error(detector, error, sizeof(error)) == 0) {
                    NSString* errorStr = [NSString stringWithUTF8String:error];
                    NSLog(@"❌ Detection failed: %@", errorStr);
                }
            }
            
            // 4. Destroy detector
            passgfw_destroy(detector);
            
            exit(0);
        });
        
        // Keep main thread running
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
