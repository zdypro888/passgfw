# PassGFW Usage Examples

Examples for C, C++, Objective-C, Swift, and macOS.

---

## 📝 Examples

### C API (`example_c.c`)

```c
#include "passgfw.h"

PassGFWDetector* detector = passgfw_create();
char domain[256];
passgfw_get_final_server(detector, domain, sizeof(domain));
passgfw_destroy(detector);
```

### Objective-C (`example_objc.m`)

```objc
#import "passgfw.h"

PassGFWDetector* detector = passgfw_create();
char domain[256];
passgfw_get_final_server(detector, domain, sizeof(domain));
NSString* domainStr = [NSString stringWithUTF8String:domain];
passgfw_destroy(detector);
```

### Swift (`PassGFWBridge.swift`)

```swift
let manager = PassGFWManager()

manager.getFinalServerAsync { domain in
    if let domain = domain {
        print("Found: \(domain)")
    }
}
```

### macOS C (`example_macos.c`)

```c
#include "passgfw.h"

PassGFWDetector* detector = passgfw_create();
char domain[256];

// Run in background thread or blocking mode
passgfw_get_final_server(detector, domain, sizeof(domain));

passgfw_destroy(detector);
```

**Build & Run:**
```bash
cd client/scripts && ./build_macos.sh
cd ../build-macos
clang ../examples/example_macos.c -o example \
    -I./include -L./lib -lpassgfw_client \
    -framework Foundation -framework Security -lc++
./example
```

---

## 🚀 Quick Start

### iOS

1. Add `passgfw_client.xcframework` to your Xcode project
2. Copy `PassGFWBridge.swift` (for Swift) or import `<passgfw_client/passgfw.h>` (for Obj-C)
3. Use the API (see examples above)

### macOS

1. Build library: `cd client/scripts && ./build_macos.sh`
2. Link to your project (see `example_macos.c` for details)
3. Run: `./your_app`

### Android

1. Copy `.a` files to `jniLibs/`
2. Create JNI wrapper (see `example_c.c` for C API)
3. Load library: `System.loadLibrary("passgfw_client")`

---

## ⚠️ Important

`passgfw_get_final_server()` is **blocking** and will loop infinitely until finding a server.

**Always run in background thread:**

```swift
// Swift
DispatchQueue.global().async {
    // Call here
}
```

```objc
// Objective-C
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    // Call here
});
```

---

## 📖 API Reference

```c
// Create detector
PassGFWDetector* passgfw_create();

// Get available server (blocking!)
int passgfw_get_final_server(PassGFWDetector* detector, 
                             char* out_domain, 
                             int domain_size);

// Add custom URL
int passgfw_add_url(PassGFWDetector* detector, const char* url);

// Get last error
int passgfw_get_last_error(PassGFWDetector* detector, 
                           char* out_error, 
                           int error_size);

// Destroy detector
void passgfw_destroy(PassGFWDetector* detector);
```

**Return Values:**
- `0`: Success
- `-1`: Error

---

## 💡 Tips

1. Always call `passgfw_destroy()` when done
2. Create one detector per thread
3. Add custom URLs before calling `passgfw_get_final_server()`
4. Check return values and call `passgfw_get_last_error()` on errors

---

See `../../README.md` for more information.
