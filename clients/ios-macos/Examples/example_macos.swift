#!/usr/bin/env swift

/*
 * PassGFW macOS Example
 * 
 * A simple command-line tool demonstrating PassGFW usage on macOS.
 * 
 * Build and run:
 *   swift build
 *   .build/debug/PassGFWExample
 * 
 * Or run directly:
 *   swift run
 */

import Foundation
#if canImport(PassGFW)
import PassGFW
#endif

print("╔════════════════════════════════════════════════════════════╗")
print("║           PassGFW Client - macOS Example (Swift)          ║")
print("╚════════════════════════════════════════════════════════════╝\n")

// Create PassGFW instance
let detector = PassGFWClient()

// Enable debug logging
detector.setLogLevel(.debug)

print("🔍 Starting firewall detection...")
print("⚠️  Note: This will block until an available server is found")
print("⚠️  Make sure server is running: cd server && go run main.go\n")

// Run detection
Task {
    if let domain = await detector.getFinalServer(customData: "macos-swift-example") {
        print("\n✅ Found available server: \(domain)\n")
        exit(0)
    } else {
        if let error = detector.getLastError() {
            print("\n❌ Error: \(error)\n")
        }
        exit(1)
    }
}

// Keep the program running
RunLoop.main.run()

