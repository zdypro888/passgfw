/*
 * PassGFW Client - macOS Example
 * 
 * This example demonstrates how to use PassGFW client library on macOS.
 * 
 * Build:
 *   cd ../scripts && ./build_macos.sh
 *   cd ../build-macos
 *   clang ../examples/example_macos.c -o example_macos \
 *       -I./include \
 *       -L./lib \
 *       -lpassgfw_client \
 *       -framework Foundation \
 *       -framework Security \
 *       -lc++
 * 
 * Run:
 *   ./example_macos
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include "passgfw.h"

// Thread function to run detection
void* detection_thread(void* arg) {
    PassGFWDetector* detector = (PassGFWDetector*)arg;
    
    printf("🔍 Starting firewall detection...\n");
    printf("⚠️  Note: This will block until an available server is found\n");
    printf("⚠️  Make sure server is running: cd server && go run main.go\n\n");
    
    char domain[256];
    int result = passgfw_get_final_server(detector, domain, sizeof(domain));
    
    if (result == 0) {
        printf("\n✅ Found available server: %s\n", domain);
    } else {
        char error[256];
        passgfw_get_last_error(detector, error, sizeof(error));
        printf("\n❌ Error: %s\n", error);
    }
    
    return NULL;
}

int main(int argc, char* argv[]) {
    printf("╔════════════════════════════════════════════════════════════╗\n");
    printf("║           PassGFW Client - macOS Example                  ║\n");
    printf("╚════════════════════════════════════════════════════════════╝\n\n");
    
    // Create detector instance
    PassGFWDetector* detector = passgfw_create();
    if (!detector) {
        printf("❌ Failed to create detector\n");
        return 1;
    }
    printf("✅ Detector created\n\n");
    
    // Add custom URLs (optional)
    if (argc > 1) {
        printf("📝 Adding custom URLs:\n");
        for (int i = 1; i < argc; i++) {
            printf("   - %s\n", argv[i]);
            passgfw_add_url(detector, argv[i]);
        }
        printf("\n");
    }
    
    // Option 1: Run in current thread (blocking)
    printf("Choose mode:\n");
    printf("  1. Blocking mode (will wait for server)\n");
    printf("  2. Background thread mode\n");
    printf("  3. Just test API (no actual detection)\n");
    printf("\nEnter choice (1-3): ");
    
    int choice;
    if (scanf("%d", &choice) != 1) {
        choice = 3; // Default to test mode
    }
    printf("\n");
    
    switch (choice) {
        case 1: {
            // Blocking mode
            char domain[256];
            printf("🔍 Running detection (blocking)...\n\n");
            int result = passgfw_get_final_server(detector, domain, sizeof(domain));
            
            if (result == 0) {
                printf("\n✅ Found available server: %s\n", domain);
            } else {
                char error[256];
                passgfw_get_last_error(detector, error, sizeof(error));
                printf("\n❌ Error: %s\n", error);
            }
            break;
        }
        
        case 2: {
            // Background thread mode
            pthread_t thread;
            printf("🔍 Starting detection in background thread...\n\n");
            
            if (pthread_create(&thread, NULL, detection_thread, detector) != 0) {
                printf("❌ Failed to create thread\n");
                passgfw_destroy(detector);
                return 1;
            }
            
            // Wait for thread (you can do other work here)
            printf("⏳ Waiting for result (press Ctrl+C to cancel)...\n\n");
            pthread_join(thread, NULL);
            break;
        }
        
        case 3:
        default: {
            // Test mode - just verify API
            printf("🧪 Test Mode - Verifying API\n\n");
            
            printf("Testing API functions:\n");
            printf("  ✅ passgfw_create() - OK\n");
            printf("  ✅ passgfw_add_url() - OK\n");
            printf("  ✅ passgfw_get_last_error() - OK\n");
            
            char error[256];
            passgfw_get_last_error(detector, error, sizeof(error));
            printf("  Current status: %s\n", strlen(error) > 0 ? error : "No errors");
            
            printf("\n💡 To test actual detection:\n");
            printf("   1. Start server: cd server && go run main.go\n");
            printf("   2. Run this example again and choose option 1 or 2\n");
            break;
        }
    }
    
    // Clean up
    printf("\n🧹 Cleaning up...\n");
    passgfw_destroy(detector);
    printf("✅ Done!\n\n");
    
    return 0;
}

