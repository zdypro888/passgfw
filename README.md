# 🚀 PassGFW

跨平台防火墙检测和服务器可用性检查库，支持 iOS、macOS、Android 和 HarmonyOS。

**轻量级 • 安全 • 高性能 • 纯原生**

---

## 📖 概述

PassGFW 帮助应用通过测试多个服务器端点（使用 RSA 加密和签名验证）来绕过防火墙限制。

**特性：**
- 🔐 RSA 2048 位加密 + SHA256 签名
- 🌍 支持 iOS、macOS、Android、HarmonyOS
- 📱 平台原生实现（Swift、Kotlin、ArkTS）
- 🔄 自动重试，支持动态 URL 列表
- 🌐 Navigate 方法（静默打开浏览器）
- 💾 加密存储（自动持久化可用服务器）
- 🪶 轻量级（无第三方依赖）
- ⚡ 高性能 Go 服务器
- 🔑 内置密钥（无需外部配置文件）

---

## 🏗️ 架构

**设计原则：** 每个平台使用原生语言实现，避免跨语言桥接。

```
clients/
├── ios-macos/         Swift 实现
│   ├── Package.swift         Swift Package Manager
│   ├── Sources/PassGFW/      核心代码 (~1200 行)
│   └── Examples/             交互式示例程序（可执行）
│
├── android/           Kotlin 实现
│   ├── passgfw/              Library 模块
│   ├── app/                  测试应用（APK）
│   ├── build.gradle.kts      Gradle 配置
│   └── src/main/kotlin/      核心代码 (~1000 行)
│
├── harmony/           ArkTS 实现
│   ├── entry/                主模块
│   ├── build-profile.json5   项目配置
│   └── src/main/ets/         核心代码 (~1100 行)
│
└── build.sh           统一构建脚本（支持clean、verify、parallel）

server/                Go 服务器（内置密钥）
├── main.go                   Gin 框架实现 + Web管理界面
└── go.mod                    依赖管理
```

---

## 🚀 快速开始

### 1. 配置构建参数（所有平台）

```bash
cd clients
cp build_config.example.json build_config.json
vim build_config.json  # 填入你的服务器 URLs
```

配置示例：
```json
{
  "urls": [
    {
      "method": "api",
      "url": "https://server1.example.com/passgfw"
    },
    {
      "method": "api",
      "url": "https://server2.example.com/passgfw",
      "store": true
    },
    {
      "method": "navigate",
      "url": "https://github.com/yourproject"
    },
    {
      "method": "file",
      "url": "https://cdn.example.com/list.txt",
      "store": true
    }
  ],
  "public_key_path": "../server/keys/public_key.pem"
}
```

**Method 说明：**
- `api` - API检测（返回服务器域名）
- `file` - 文件列表（返回URL列表）
- `navigate` - 打开浏览器（静默，每个URL只打开一次）
- `remove` - 从存储中删除URL
- `store: true` - 检测成功后持久化存储（加密）

### 2. 启动服务器（内置密钥，无需配置）

```bash
cd server

# 方法1：直接运行
go run main.go --port 8080 --domain your-domain.com:443

# 方法2：编译后运行
go build -o passgfw-server main.go
./passgfw-server --port 8080

# 访问管理界面
open http://localhost:8080/admin
```

服务器会自动使用内置的RSA密钥，无需外部配置文件！

### 3. 构建客户端

```bash
cd clients

# iOS/macOS（Swift Package）
./build.sh ios              # 构建 Library + 可执行示例
./build.sh ios --clean      # 清理构建产物

# Android（Kotlin/Gradle）
./build.sh android          # 构建 AAR库 + 测试APK
./build.sh android --clean  # 清理（包括.gradle、.idea等）

# HarmonyOS（ArkTS）
./build.sh harmony          # 更新配置（需 DevEco Studio 构建HAR）
./build.sh harmony --clean  # 清理

# 高级选项
./build.sh all              # 构建所有平台
./build.sh all --parallel   # 并行构建（更快）
./build.sh ios --verify     # 构建并验证产物
```

### 4. 在项目中使用

#### iOS/macOS（Xcode）
1. File > Add Package Dependencies > Add Local
2. 选择 `clients/ios-macos` 目录
3. 代码中 `import PassGFW` 即可使用

#### Android（Android Studio）
1. 将 `clients/android/passgfw` 作为模块导入
2. 或使用生成的 AAR：`clients/android/passgfw/build/outputs/aar/passgfw-release.aar`
3. 测试APK：`clients/android/app/build/outputs/apk/debug/app-debug.apk`

#### HarmonyOS（DevEco Studio）
1. 打开 `clients/harmony/` 项目
2. 构建生成 HAR 包

**详细文档：**
- iOS/macOS：`clients/ios-macos/README.md`
- Android：`clients/android/README.md`
- HarmonyOS：`clients/harmony/README.md`
- Server：`server/README.md`

---

## 📱 平台支持

| 平台 | 语言 | 最低版本 | 构建工具 | 状态 |
|------|------|----------|----------|------|
| **iOS** | Swift 5.9 | iOS 13+ | Swift Package Manager | ✅ 完成 |
| **macOS** | Swift 5.9 | macOS 10.15+ | Swift Package Manager | ✅ 完成 |
| **Android** | Kotlin 1.9 | API 24+ (Android 7.0+) | Gradle 8.14 + Java 24 | ✅ 完成 |
| **HarmonyOS** | ArkTS | API 10+ | DevEco Studio | ✅ 完成 |
| **Server** | Go 1.21+ | - | go build | ✅ 完成 |

---

## 🔐 密钥管理

**服务器和客户端都已内置密钥对**，开箱即用！

如需自定义密钥：

```bash
cd server/keys
# 生成新的密钥对
openssl genrsa -out private_key.pem 2048
openssl rsa -in private_key.pem -pubout -out public_key.pem

# 重新构建客户端（会自动嵌入新公钥）
cd ../../clients
./build.sh all
```

**密钥说明：**
- `private_key.pem` - 服务器私钥（**勿泄露**，已内置到server）
- `public_key.pem` - 公钥（已内置到所有客户端）
- 内置密钥仅用于开发测试，生产环境请生成新密钥！

---

## 📚 文档

- **iOS/macOS**: [clients/ios-macos/README.md](clients/ios-macos/README.md)
- **Android**: [clients/android/README.md](clients/android/README.md)
- **HarmonyOS**: [clients/harmony/README.md](clients/harmony/README.md)
- **服务器**: [server/README.md](server/README.md)
- **安全与权限**: [docs/SECURITY_AND_PERMISSIONS.md](docs/SECURITY_AND_PERMISSIONS.md)

---

## ⚙️ 配置

### 统一构建配置（推荐）

使用 `build_config.json` 统一管理所有平台的配置：

```bash
cd clients
vim build_config.json
```

```json
{
  "urls": [
    "https://your-server.com/passgfw",
    "https://backup.com/passgfw",
    "https://cdn.com/list.txt#"
  ],
  "public_key_path": "../server/keys/public_key.pem",
  "config": {
    "request_timeout": 10,
    "max_retries": 3,
    "retry_delay": 1.0,
    "max_list_recursion_depth": 5,
    "log_level": "INFO"
  }
}
```

然后运行构建脚本：
```bash
./build.sh ios      # 自动注入配置到 Swift
./build.sh android  # 自动注入配置到 Kotlin
./build.sh harmony  # 自动注入配置到 ArkTS
```

### 手动更新配置（不推荐）

如果不使用构建脚本，可以手动修改每个平台的 `Config` 文件：

**iOS/macOS (Swift):**
```swift
// clients/ios-macos/Sources/PassGFW/Config.swift
static func getBuiltinURLs() -> [String] {
    return [
        "https://your-server.com/passgfw",
        "https://backup.com/passgfw",
        "https://cdn.com/list.txt#"  // URL 列表
    ]
}
```

**Android (Kotlin):**
```kotlin
// clients/android/passgfw/src/main/kotlin/com/passgfw/Config.kt
fun getBuiltinURLs(): List<String> {
    return listOf(
        "https://your-server.com/passgfw",
        "https://backup.com/passgfw"
    )
}
```

**HarmonyOS (ArkTS):**
```typescript
// clients/harmony/entry/src/main/ets/passgfw/Config.ets
static getBuiltinURLs(): string[] {
    return [
        'https://your-server.com/passgfw',
        'https://backup.com/passgfw'
    ];
}
```

### URL 列表文件格式

URL 以 `#` 结尾表示这是一个**列表文件**。支持两种格式：

**格式 1: 带 `*GFW*` 标记（推荐用于云存储）**
```
*GFW*
https://server1.com/passgfw|https://server2.com/passgfw
*GFW*
```

**格式 2: 逐行列表**
```
https://server1.com/passgfw
https://server2.com/passgfw
# 注释会被忽略
```

---

## 🔄 工作流程

```
┌─────────┐
│  Client │
└────┬────┘
     │ 1. 生成随机数
     │ 2. 用公钥加密（含自定义数据）
     │ 3. POST /passgfw
     ▼
┌─────────┐
│ Server  │
└────┬────┘
     │ 4. 用私钥解密
     │ 5. 返回随机数 + 服务器域名
     │ 6. 用私钥签名
     ▼
┌─────────┐
│  Client │
└─────────┘
     7. 验证签名
     8. 验证随机数匹配
     9. 使用返回的服务器域名
```

---

## 📊 性能

| 指标 | 数值 |
|------|------|
| **Swift 代码** | ~1200 行 |
| **Kotlin 代码** | ~1000 行 |
| **ArkTS 代码** | ~1100 行 |
| **内存占用** | <2MB |
| **服务器吞吐** | >10K req/s |
| **请求延迟** | <10ms (典型) |

---

## 🧪 测试

### 快速测试

```bash
# 1. 编译并启动服务器
cd server
go build -o passgfw-server main.go
./passgfw-server

# 2. 测试 macOS（新终端）
cd clients
./build.sh ios
cd ios-macos/.build/release
./PassGFWExample    # 交互式菜单

# 3. 测试 Android
cd clients
./build.sh android
# 安装APK到设备
adb install android/app/build/outputs/apk/debug/app-debug.apk
# 或在Android Studio中运行

# 4. 测试 HarmonyOS
# 使用 DevEco Studio 打开 clients/harmony 运行
```

### 测试输出示例

**macOS 示例程序：**
```
=== PassGFW macOS 示例程序 ===

选择示例:
  1. 基本防火墙检测
  2. 自定义 URL 列表
  3. 错误处理演示
  4. 动态添加 URL
  直接按 Enter: 运行所有示例
```

**Android 测试应用：**
- 3个测试按钮：基本检测、自定义URL、动态添加
- 实时状态显示
- 找到的服务器域名显示

---

## 🐛 故障排除

### 服务器无法启动

```bash
# 检查端口占用
lsof -i :8080

# 使用其他端口
go run main.go --port 3000
```

### 客户端连接失败

1. 确认服务器正在运行
2. 检查 URL 配置
3. Android 模拟器使用 `10.0.2.2` 代替 `localhost`

### 构建失败

```bash
# iOS/macOS
cd clients
./build.sh ios --clean
./build.sh ios

# Android
cd clients
./build.sh android --clean
./build.sh android

# HarmonyOS
cd clients
./build.sh harmony --clean
# DevEco Studio > Build > Clean Project
```

### Android: Java版本不兼容

如果出现 "Can't use Java XX and Gradle XX" 错误：

- **Java 24+** 需要 **Gradle 8.14+**
- 项目已配置 Gradle 8.14，支持 Java 24
- 重新导入项目即可解决

---

## 🎯 优势

### vs. C++ + JNI/NAPI 方案

✅ **无跨语言桥接** - 避免 JNI/NAPI 复杂性  
✅ **性能更好** - 直接使用平台 API  
✅ **易于维护** - 各平台独立开发  
✅ **更小体积** - 无额外运行时  
✅ **更快开发** - 使用平台最佳实践  

### 平台原生优势

| 平台 | HTTP 库 | JSON | 加密 |
|------|---------|------|------|
| iOS/macOS | URLSession | NSJSONSerialization | Security.framework |
| Android | OkHttp | Gson | java.security |
| HarmonyOS | @ohos.net.http | JSON.parse | cryptoFramework |

**无第三方依赖！**

---

## 📄 许可证

MIT License

---

## 🏷️ 版本历史

### v2.1 (2025-11-02)
- ⚡ **并发检测** - 默认3个URL同时检测，速度提升2.5倍（20s→8s）
- 📊 **完整统计** - 100%记录所有URL成功/失败次数，优化优先级排序
- 🎯 **平台统一** - iOS/Android/HarmonyOS检测逻辑完全一致
- 🔧 **后台统计** - 首个成功即返回，剩余结果后台收集不阻塞
- 🐛 **Bug修复** - 修复HarmonyOS递归深度检查错误

### v2.0 (2025-11-01)
- ✨ **Navigate方法** - 静默打开浏览器（iOS/macOS/Android/HarmonyOS）
- 💾 **加密存储** - 自动持久化可用服务器（AndroidX Security、Keychain）
- 🔑 **内置密钥** - Server和客户端都内置密钥对，开箱即用
- 🛠️ **增强构建脚本** - 支持clean、verify、parallel等选项
- 📱 **macOS可执行示例** - 交互式菜单程序（244行）
- 📱 **Android测试APK** - 完整的测试应用（MainActivity + 3个示例）
- 🔧 **Gradle 8.14** - 支持Java 24
- 🧹 **智能清理** - 彻底清理构建产物和IDE配置
- 📝 **URL Entry格式** - 新增method、url、store字段
- 🌐 **Web管理界面** - Server端提供URL列表生成工具

### v1.0 (2025-10-30)
- ✅ 完整的 4 平台实现（iOS、macOS、Android、HarmonyOS）
- ✅ RSA 2048加密 + SHA256签名验证
- ✅ 动态 URL 列表支持
- ✅ 自动重试机制
- ✅ 统一日志系统

---

**状态：** ✅ 所有平台完成并测试
**版本：** 2.1.0
**最后更新：** 2025-11-02

Made with ❤️ for bypassing firewalls
