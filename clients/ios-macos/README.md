# PassGFW - iOS/macOS Client (Swift)

纯 Swift 实现的 PassGFW 客户端，支持 iOS 13+ 和 macOS 10.15+。

## 特性

- ✅ 纯 Swift 实现，无需桥接
- ✅ 使用原生 Foundation 和 Security 框架
- ✅ 支持 async/await
- ✅ 完整的防火墙检测逻辑
- ✅ RSA 加密和签名验证
- ✅ 支持 list.txt# 动态列表
- ✅ 自动重试机制
- ✅ 统一日志系统

## 要求

- iOS 13.0+ / macOS 10.15+
- Xcode 15.0+
- Swift 5.9+

## 安装和配置

### Step 1: 配置构建参数

```bash
cd clients
cp build_config.example.json build_config.json
vim build_config.json  # 填入你的服务器 URLs
```

配置文件示例：
```json
{
  "urls": [
    "https://server1.example.com/passgfw",
    "https://server2.example.com/passgfw"
  ],
  "public_key_path": "../server/keys/public_key.pem"
}
```

### Step 2: 构建（可选）

```bash
cd clients
./build.sh ios  # 构建并注入配置
```

> 💡 **提示：** 这步可以跳过，Xcode 会自动构建。但运行后会将 URLs 注入到源码中。

### Step 3: 在 Xcode 中添加本地 Package

1. 打开你的 iOS/macOS 项目（`.xcodeproj`）
2. 菜单：**File > Add Package Dependencies...**
3. 点击窗口左下角的 **"Add Local..."**
4. 选择目录：`/path/to/passgfw/clients/ios-macos`
5. 点击 **"Add Package"**
6. 选择要添加的 Target，再次点击 **"Add Package"**

完成！Xcode 会自动编译和链接。

### 其他方式（从 Git 仓库）

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/your-org/passgfw", from: "1.0.0")
]
```

或在 Xcode 中：
1. File > Add Package Dependencies
2. 输入仓库 URL
3. 选择版本

## 使用

### 基本用法

```swift
import PassGFW

// 创建实例
let passgfw = PassGFWClient()

// 获取可用服务器（异步）
Task {
    if let server = await passgfw.getFinalServer() {
        print("Found server: \(server)")
    }
}
```

### 带自定义数据

```swift
// 发送自定义数据到服务器
if let server = await passgfw.getFinalServer(customData: "my-app-v1.0") {
    print("Found server: \(server)")
}
```

### 自定义 URL 列表

```swift
let passgfw = PassGFWClient()

// 设置自定义 URL 列表
passgfw.setURLList([
    "https://example.com/passgfw",
    "https://backup.com/passgfw"
])

// 或添加单个 URL
passgfw.addURL("https://another.com/passgfw")
```

### 日志控制

```swift
let passgfw = PassGFWClient()

// 设置日志级别
passgfw.setLogLevel(.info)  // 只显示 info 及以上

// 禁用日志
passgfw.setLoggingEnabled(false)
```

### 错误处理

```swift
if let server = await passgfw.getFinalServer() {
    print("Success: \(server)")
} else {
    if let error = passgfw.getLastError() {
        print("Error: \(error)")
    }
}
```

## 构建

```bash
# 构建库
swift build

# 运行测试
swift test

# 生成 Xcode 项目
swift package generate-xcodeproj
```

## 示例

查看 `Examples/` 目录中的示例项目：

- `Examples/macOS/` - macOS 命令行示例
- `Examples/iOS/` - iOS App 示例

## API 文档

### PassGFW

主类，提供防火墙检测功能。

#### 方法

- `init()` - 创建实例
- `getFinalServer(customData: String?) async -> String?` - 获取可用服务器
- `setURLList(_ urls: [String])` - 设置 URL 列表
- `addURL(_ url: String)` - 添加 URL
- `getLastError() -> String?` - 获取最后的错误
- `setLoggingEnabled(_ enabled: Bool)` - 启用/禁用日志
- `setLogLevel(_ level: LogLevel)` - 设置日志级别

## 配置

编辑 `Config.swift` 修改默认配置：

- `requestTimeout` - HTTP 超时时间
- `maxRetries` - 最大重试次数
- `retryDelay` - 重试延迟
- 其他配置选项

## 架构

```
PassGFW/
├── PassGFW.swift          # 主入口
├── FirewallDetector.swift # 核心检测逻辑
├── NetworkClient.swift    # HTTP 客户端
├── CryptoHelper.swift     # 加密和签名
├── Config.swift           # 配置
└── Logger.swift           # 日志系统
```

## License

MIT License

