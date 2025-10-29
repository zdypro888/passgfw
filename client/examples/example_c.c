/**
 * C API Usage Example
 */

#include "passgfw.h"
#include <stdio.h>
#include <pthread.h>

// Run detection in background thread
void* detect_thread(void* arg) {
    PassGFWDetector* detector = (PassGFWDetector*)arg;
    
    char domain[256];
    printf("Starting server detection...\n");
    
    if (passgfw_get_final_server(detector, domain, sizeof(domain)) == 0) {
        printf("✅ Found available server: %s\n", domain);
    } else {
        char error[256];
        if (passgfw_get_last_error(detector, error, sizeof(error)) == 0) {
            printf("❌ Detection failed: %s\n", error);
        }
    }
    
    return NULL;
}

int main() {
    printf("PassGFW C API Example\n");
    printf("=====================\n\n");
    
    // 1. Create detector
    PassGFWDetector* detector = passgfw_create();
    if (!detector) {
        printf("Failed to create detector\n");
        return 1;
    }
    
    // 2. Optional: Add custom URL
    // passgfw_add_url(detector, "https://custom.example.com/check");
    
    // 3. Run detection in background thread (blocking operation)
    pthread_t thread;
    pthread_create(&thread, NULL, detect_thread, detector);
    
    printf("Detection running in background...\n");
    printf("Press Ctrl+C to exit\n\n");
    
    // Wait for thread to finish
    pthread_join(thread, NULL);
    
    // 4. Destroy detector
    passgfw_destroy(detector);
    
    return 0;
}
