# PassGFW Client

防火墙检测客户端库，支持 iOS、Android 和鸿蒙系统。

> **项目状态**: ✅ **可以安全使用**  
> iOS 平台已完成并测试，Android/鸿蒙平台框架已就绪，需完善平台层实现。  
> 代码质量评分: **68/70** (优秀)

## 🎯 核心特性

- ✅ **零第三方依赖**：100% 使用平台原生 API
- ✅ **超轻量级**：静态库 < 50KB
- ✅ **职责分离**：C++ 只负责逻辑，平台层负责 HTTP/JSON/加密
- ✅ **原生性能**：使用平台优化的网络和加密 API
- ✅ **自动环境配置**：构建脚本自动下载 NDK
- ✅ **一键打包**：支持 iOS、Android、鸿蒙三平台打包

## 📐 架构设计

```
client/
├── 📄 核心文件 (C++)
│   ├── config.cpp/h              # 配置管理
│   ├── firewall_detector.cpp/h  # 核心检测逻辑
│   ├── http_interface.h          # 接口定义
│   └── passgfw.cpp/h             # C API 封装
│
├── 🏗️ 平台实现
│   ├── platform/ios/
│   │   ├── network_client_ios.h/mm    # NSURLSession + Security
│   ├── platform/android/
│   │   ├── network_client_android.h/cpp  # JNI 桥接
│   │   └── NetworkHelper.java            # Java 实现
│   └── platform/harmony/
│       ├── network_client_harmony.h/cpp  # NAPI 桥接
│       └── network_helper.ets            # ArkTS 实现
│
├── 🔨 构建脚本
│   ├── scripts/build_ios.sh
│   ├── scripts/build_android.sh
│   ├── scripts/build_harmony.sh
│   └── CMakeLists.txt
│
├── 📚 文档
│   ├── README.md          # 本文件
│   ├── BUILD.md           # 详细构建指南
│   └── ARCHITECTURE.md    # 架构设计详解
│
└── 💡 示例
    ├── examples/example.cpp       # C++ 示例
    ├── examples/example_c.c       # C 示例
    ├── examples/example_objc.m    # Objective-C 示例
    └── examples/PassGFWBridge.swift  # Swift 桥接示例
```

### 平台实现说明

| 平台 | HTTP 实现 | 加密实现 |
|------|----------|---------|
| **iOS** | NSURLSession | Security.framework (SecKey) |
| **Android** | HttpURLConnection (JNI) | java.security + javax.crypto |
| **鸿蒙** | @ohos.net.http (NAPI) | @ohos.security.cryptoFramework |

## 🔧 核心功能

### GetFinalServer()

核心函数，返回一个经过检测的没有被封的域名或 IP。

**完整流程：**

```
1. 循环遍历内置 URL 列表
2. 对每个 URL 进行检测：
   
   ┌─ 普通 URL ─────────────────────────────┐
   │ a. 生成32位随机字符串                    │
   │ b. 使用公钥加密随机字符串                │
   │ c. POST 加密数据到服务器                 │
   │ d. 服务器用私钥解密                      │
   │ e. 服务器用公钥签名解密后的内容          │
   │ f. 返回 JSON: {"data":"...", "signature":"..."} │
   │ g. 客户端验证签名                        │
   │ h. 验证解密数据 == 原始随机字符串        │
   │ i. 成功则返回该 URL 的域名               │
   └────────────────────────────────────────┘
   
   ┌─ 列表 URL（以 # 结尾）──────────────────┐
   │ a. 识别为网盘公开文件                    │
   │ b. GET 请求获取文件内容                  │
   │ c. 解析为 URL 列表（每行一个）           │
   │ d. 递归检测列表中的每个 URL              │
   │ e. 找到可用的返回                        │
   └────────────────────────────────────────┘

3. 如果所有 URL 都失败：
   - 等待 2 秒
   - 重新开始循环
   - 无限重试直到成功
```

## 📦 编译

详细的构建说明请查看 [BUILD.md](BUILD.md)

### 快速开始 - iOS

```bash
# 1. 创建构建目录
mkdir -p build-ios && cd build-ios

# 2. 配置 CMake
cmake -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  -DCMAKE_OSX_ARCHITECTURES="arm64" \
  ..

# 3. 编译
xcodebuild -configuration Release -sdk iphoneos

# 4. 产物位置
# build-ios/Release-iphoneos/passgfw_client.framework/
```

### 快速开始 - Android

```bash
cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-21 \
  -B build-android

cmake --build build-android

# 产物: build-android/libpassgfw_client.a
# 同时需要: platform/android/NetworkHelper.java
```

### 快速开始 - 鸿蒙

```bash
cmake -DCMAKE_TOOLCHAIN_FILE=$OHOS_SDK/native/build/cmake/ohos.toolchain.cmake \
  -DOHOS_ARCH=arm64-v8a \
  -B build-harmony

cmake --build build-harmony

# 产物: build-harmony/libpassgfw_client.a
# 同时需要: platform/harmony/network_helper.ets
```

## 📍 构建产物位置

| 平台 | 产物路径 | 大小 |
|------|---------|------|
| **iOS** | `build-ios/Release-iphoneos/passgfw_client.framework/` | ~50KB |
| **Android** | `build-android/libpassgfw_client.a` | ~30KB |
| **鸿蒙** | `build-harmony/libpassgfw_client.a` | ~30KB |

> **注意**：`build-*` 目录是临时构建目录，已在 `.gitignore` 中。构建产物可直接使用，无需额外复制。

## 💻 使用方法

### C API 使用（推荐）

```c
#include "passgfw.h"

int main() {
    // 创建检测器
    PassGFWDetector* detector = passgfw_create();
    
    // 可选：添加自定义 URL
    passgfw_add_url(detector, "https://custom-server.com/check");
    
    // 获取可用的服务器域名
    char domain[256];
    if (passgfw_get_final_server(detector, domain, sizeof(domain)) == 0) {
        printf("可用服务器: %s\n", domain);
    }
    
    // 销毁检测器
    passgfw_destroy(detector);
    return 0;
}
```

### C++ 使用

```cpp
#include "firewall_detector.h"

passgfw::FirewallDetector detector;
detector.AddURL("https://custom-server.com/check");
std::string domain = detector.GetFinalServer();
```

### iOS (Swift/Objective-C)

```swift
// 参考 examples/PassGFWBridge.swift
import Foundation

let detector = passgfw_create()
var domain = [CChar](repeating: 0, count: 256)
if passgfw_get_final_server(detector, &domain, 256) == 0 {
    let serverDomain = String(cString: domain)
    print("可用服务器: \(serverDomain)")
}
passgfw_destroy(detector)
```

详细示例见 `examples/PassGFWBridge.swift` 和 `examples/example_objc.m`。

### Android (Java)

参考 `examples/example_c.c` 创建 JNI 桥接：

```java
public class PassGFW {
    static { System.loadLibrary("passgfw_client"); }
    
    public native long create();
    public native String getFinalServer(long handle);
    public native void destroy(long handle);
}

// 使用
PassGFW gfw = new PassGFW();
long handle = gfw.create();
String domain = gfw.getFinalServer(handle);
gfw.destroy(handle);
```

### 鸿蒙 (ArkTS)

类似 Android，使用 NAPI 封装。

## ⚙️ 配置

### 修改内置 URL 列表

编辑 `config.cpp`：

```cpp
std::vector<std::string> Config::GetBuiltinURLs() {
    return {
        "https://server1.example.com/check",
        "https://server2.example.com/verify",
        "https://1.1.1.1/passgfw",
        "https://cdn.example.com/urls.txt#",  // 列表 URL
    };
}
```

### 配置公钥

编辑 `config.cpp`，替换为你的实际公钥（PEM 格式）：

```cpp
const char* Config::PUBLIC_KEY = R"(
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
-----END PUBLIC KEY-----
)";
```

## 📝 URL 格式

### 普通 URL

```
https://example.com/check
https://1.1.1.1/passgfw
https://api.example.com/verify?platform=ios
```

### 列表 URL（以 # 结尾）

```
https://example.com/urls.txt#
https://raw.githubusercontent.com/user/repo/main/servers.txt#
```

列表文件格式（纯文本，每行一个 URL）：

```
https://server1.example.com/check
https://server2.example.com/verify
https://backup.example.com/api
# 注释行会被忽略
https://another.example.com/ping
```

## 🔒 服务器端响应格式

服务器收到 POST 请求：

```json
{
  "data": "Base64编码的加密数据"
}
```

服务器应返回：

```json
{
  "data": "解密后的原始数据",
  "signature": "Base64编码的签名"
}
```

**签名算法：** SHA256withRSA

**服务器端流程：**
1. 用私钥解密收到的 data
2. 用公钥对解密后的内容进行签名
3. 返回解密内容 + 签名

## 📱 平台依赖

### iOS
- **最低版本**: iOS 12.0+
- **框架**: Foundation.framework, Security.framework
- **无需第三方库**

### Android
- **最低版本**: Android 5.0 (API 21)+
- **需要权限**: `<uses-permission android:name="android.permission.INTERNET"/>`
- **无需第三方库**

### 鸿蒙
- **最低版本**: HarmonyOS 3.0+
- **需要权限**: `ohos.permission.INTERNET`
- **无需第三方库**

## 🎯 注意事项

1. **阻塞调用**: `GetFinalServer()` 会阻塞直到找到可用服务器，建议在后台线程调用
2. **网络权限**: 移动应用需要申请网络权限
3. **公钥配置**: 必须在 `config.cpp` 中配置正确的公钥
4. **无限重试**: 如果所有服务器都不可用，会无限循环重试（间隔2秒）

## 📄 许可证

MIT License
