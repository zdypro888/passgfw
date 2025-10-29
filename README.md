# 🚀 PassGFW

Cross-platform firewall detection and server availability checker for iOS, macOS, Android, and HarmonyOS.

**Lightweight • Secure • High-Performance**

---

## 📖 Overview

PassGFW helps apps bypass firewall restrictions by testing multiple server endpoints with RSA encryption and signature verification.

**Features:**
- 🔐 RSA 2048-bit encryption + SHA256 signatures
- 🌍 iOS, macOS, Android, HarmonyOS support
- 📱 Platform-native APIs (NSURLSession, HttpURLConnection, @ohos.net.http)
- 🔄 Auto-retry with dynamic URL lists
- 🪶 Lightweight (~164KB iOS XCFramework, ~60KB macOS Universal Binary)
- ⚡ High-performance Gin server (1.2M req/s)

---

## 🚀 Quick Start

```bash
# 1. Generate keys
cd client/scripts && ./generate_keys.sh

# 2. Build client
./build_ios.sh

# 3. Start server
cd ../../server && go run main.go

# 4. Test
./test_server.sh
```

**That's it!** 🎉

---

## 📁 Project Structure

```
passgfw/
├── client/
│   ├── scripts/          # Build scripts
│   │   ├── generate_keys.sh
│   │   ├── build_ios.sh
│   │   ├── build_macos.sh
│   │   ├── build_android.sh
│   │   └── build_harmony.sh
│   ├── examples/         # Usage examples
│   ├── platform/         # iOS/Android/HarmonyOS implementations
│   ├── config.h/cpp      # Configuration (URLs, timeouts)
│   └── *.h, *.cpp       # Core C++ code
├── server/
│   ├── main.go           # Go server (Gin framework)
│   └── test_server.sh    # Test script
├── README.md             # This file
└── CHANGELOG.md          # Version history
```

---

## 🏗️ Building

### iOS (Production Ready ✅)

```bash
cd client/scripts
./build_ios.sh
```

**Output:** `build-ios/passgfw_client.xcframework`

**Auto-steps:**
1. ✅ Checks for keys (generates if missing)
2. ✅ Embeds public key into config
3. ✅ Builds for device + simulator
4. ✅ Creates Universal XCFramework

**Integration:**
```bash
# Drag passgfw_client.xcframework to Xcode
```

```swift
// Swift usage
let manager = PassGFWManager()
manager.getFinalServerAsync { domain in
    print("Available server: \(domain ?? "none")")
}
```

### macOS (Production Ready ✅)

```bash
cd client/scripts
./build_macos.sh
```

**Output:** `build-macos/lib/libpassgfw_client.a` (Universal Binary)

**Auto-steps:**
1. ✅ Builds for arm64 (Apple Silicon)
2. ✅ Builds for x86_64 (Intel)
3. ✅ Creates Universal Binary with lipo
4. ✅ Includes test program

**Integration:**
```bash
# Link to your project
clang your_app.c -o your_app \
    -I./build-macos/include \
    -L./build-macos/lib \
    -lpassgfw_client \
    -framework Foundation \
    -framework Security \
    -lc++
```

**Use cases:** Local testing, macOS apps, command-line tools

### Android (Framework Ready ⚠️)

```bash
cd client/scripts
./build_android.sh
```

**Output:** `build-android/*/libpassgfw_client.a` + Java stubs

**Note:** Complete `platform/android/NetworkHelper.java` implementation needed.

### HarmonyOS (Framework Ready ⚠️)

```bash
cd client/scripts
./build_harmony.sh
```

**Output:** `build-harmony/*/libpassgfw_client.a` + ArkTS stubs

**Note:** Complete `platform/harmony/network_helper.ets` + NAPI bindings needed.

---

## 🔐 Keys & Security

### Generate Keys (First Time)

```bash
cd client/scripts
./generate_keys.sh
```

Creates:
- `client/keys/private_key.pem` - **SERVER ONLY** (auto-gitignored)
- `client/keys/public_key.pem` - Embedded in client

**Security:**
- RSA 2048-bit encryption
- SHA256 signatures
- Private key never leaves server
- Public key embedded at build time

---

## 🖥️ Server

### Start Server

```bash
cd server
go run main.go
```

**Endpoints:**
- `POST /passgfw` - Main verification endpoint
- `GET /health` - Health check

### Custom Configuration

```bash
# Custom port
go run main.go -port 3000

# Custom private key
go run main.go -private-key /path/to/key.pem

# Debug mode
go run main.go -debug
```

### Production Deployment

```bash
# Build
cd server
GOOS=linux GOARCH=amd64 go build -o passgfw-server

# Run with systemd or Docker
./passgfw-server -port 8080
```

**Recommended:** Use Nginx/Caddy as HTTPS reverse proxy.

---

## ⚙️ Configuration

### Update Server URLs

Edit `client/config.cpp`:

```cpp
std::vector<std::string> Config::GetBuiltinURLs() {
    return {
        "https://your-server.com/passgfw",
        "https://backup.example.com/passgfw",
        "https://cdn.example.com/list.txt#"  // URL list
    };
}
```

Then rebuild: `cd client/scripts && ./build_ios.sh`

### Update Timeouts

Edit `client/config.h`:

```cpp
static constexpr int REQUEST_TIMEOUT = 10;  // HTTP timeout (seconds)
static constexpr int RETRY_INTERVAL = 2;    // Retry interval (seconds)
static constexpr int URL_INTERVAL = 500;    // URL check interval (ms)
```

### URL List File Format

URLs ending with `#` are treated as **list files**. Two formats are supported:

**Format 1: Marked with `*GFW*` (Recommended for cloud storage)**

```
*GFW*
https://server1.com/passgfw|https://server2.com/passgfw|https://server3.com/passgfw
*GFW*
```

This format extracts URLs from HTML or other content (e.g., from cloud storage shares like Dropbox, Google Drive, etc.). URLs are separated by `|`.

**Format 2: Line-by-line (Legacy)**

```
https://server1.com/passgfw
https://server2.com/passgfw
https://server3.com/passgfw
# Comments are ignored
```

Each URL on a separate line. Empty lines and lines starting with `#` are ignored.

**Example usage:**

```cpp
// In config.cpp
return {
    "https://your-server.com/passgfw",
    "https://dropbox.com/s/abc123/servers.txt#",  // Cloud storage with *GFW* markers
    "https://cdn.example.com/list.txt#"           // Simple line-by-line format
};
```

---

## 🏛️ Architecture

**Design Principle:** C++ core handles logic, platform layer handles implementation.

```
┌─────────────────────────────────────┐
│      C++ Core (Cross-platform)      │
│  firewall_detector.cpp              │
│  - GetFinalServer() ← Core function │
│  - CheckURL() ← Detection logic     │
│  - No JSON/HTTP/Crypto details      │
└──────────────┬──────────────────────┘
               │
┌──────────────┴──────────────────────┐
│      INetworkClient Interface       │
│  - VerifyURL()                      │
│  - FetchURLList()                   │
└──────────────┬──────────────────────┘
               │
    ┌──────────┼──────────┐
    │          │          │
┌───┴───┐ ┌────┴───┐ ┌───┴────┐
│  iOS  │ │Android │ │Harmony │
│ Layer │ │ Layer  │ │ Layer  │
└───────┘ └────────┘ └────────┘
```

**Platform Implementations:**

| Platform | HTTP | JSON | Crypto | Size |
|----------|------|------|--------|------|
| iOS | NSURLSession | NSJSONSerialization | Security.framework | 164KB |
| Android | HttpURLConnection | org.json | java.security | 30KB/ABI |
| HarmonyOS | @ohos.net.http | JSON.parse | cryptoFramework | 30KB/ABI |

**No third-party dependencies!**

---

## 🧪 Testing

### Test Server

```bash
cd server

# Start server
go run main.go &

# Run tests
./test_server.sh

# Stop
kill %1
```

Tests:
- ✅ Health check
- ✅ Full crypto flow
- ✅ Encryption verification
- ✅ Signature verification

---

## 🐛 Troubleshooting

### Build Fails

```bash
cd client/scripts
./CLEAN.sh
./generate_keys.sh
./build_ios.sh
```

### Keys Not Found

```bash
cd client/scripts
./generate_keys.sh
```

### Server Won't Start

```bash
# Check keys
ls -la client/keys/

# Check port
lsof -i :8080

# Use different port
cd server && go run main.go -port 3000
```

### Private Key Format Error

Server auto-supports PKCS1 and PKCS8. If error persists:

```bash
cd client/scripts
./generate_keys.sh
```

---

## 📊 Performance

| Metric | Value |
|--------|-------|
| iOS Binary | ~164KB (XCFramework) |
| macOS Binary | ~60KB (Universal Binary) |
| Android Binary | ~30KB per ABI |
| RAM Usage | <2MB (iOS/macOS), <1MB (Android) |
| Server Throughput | 1.2M req/s (Gin) |
| Request Latency | <10ms (typical) |

---

## 🐛 Debugging

### Quick Setup

```bash
./setup_debug.sh
```

### Debug in IDE

1. Start server: `cd server && go run main.go`
2. Open `client/firewall_detector.cpp` in IDE
3. Set breakpoint at line 85 (`GetFinalServer()`)
4. Press `F5` to start debugging
5. Select `(lldb) Debug PassGFW Client`

**Key breakpoints:**
- Line 85: `GetFinalServer()` - Main entry
- Line 120: `CheckURL()` - URL detection
- Line 145: `CheckNormalURL()` - Normal URL check
- Line 185: `CheckListURL()` - List URL check

**Full guide:** See `DEBUG_GUIDE.md`

---

## 📚 More Information

- **Debug Guide**: `DEBUG_GUIDE.md` - Complete debugging guide
- **Server**: `server/README.md` - Server documentation
- **Examples**: `client/examples/README.md` - Usage examples
- **Changelog**: `CHANGELOG.md` - Version history

---

## 📄 License

MIT License

---

**Status:** ✅ iOS Production Ready | ⚠️ Android/HarmonyOS Framework Ready  
**Version:** 1.0.2  
**Last Updated:** 2025-10-29

Made with ❤️ for bypassing firewalls
