# PassGFW - Android Client (Kotlin)

纯 Kotlin 实现的 PassGFW 客户端，支持 Android 7.0+ (API 24+)。

## 特性

- ✅ 纯 Kotlin 实现，使用协程
- ✅ 使用 OkHttp + Gson
- ✅ 完整的防火墙检测逻辑
- ✅ RSA 加密和签名验证
- ✅ 支持 list.txt# 动态列表
- ✅ 自动重试机制
- ✅ 统一日志系统

## 要求

- Android 7.0+ (API 24+)
- Kotlin 1.9+
- Android Gradle Plugin 8.0+

## 安装

### Gradle

在 `build.gradle.kts` 中添加：

```kotlin
dependencies {
    implementation("com.passgfw:passgfw:1.0.0")
}
```

或通过 Maven：

```kotlin
repositories {
    maven { url = uri("https://your-maven-repo") }
}
```

## 使用

### 基本用法

```kotlin
import com.passgfw.PassGFW
import kotlinx.coroutines.*

// 创建实例
val passgfw = PassGFW()

// 获取可用服务器（挂起函数）
lifecycleScope.launch {
    val server = passgfw.getFinalServer()
    if (server != null) {
        Log.d("PassGFW", "Found server: $server")
    }
}
```

### 带自定义数据

```kotlin
// 发送自定义数据到服务器
lifecycleScope.launch {
    val server = passgfw.getFinalServer(customData = "my-app-v1.0")
    server?.let { Log.d("PassGFW", "Found server: $it") }
}
```

### 自定义 URL 列表

```kotlin
val passgfw = PassGFW()

// 设置自定义 URL 列表
passgfw.setURLList(listOf(
    "https://example.com/passgfw",
    "https://backup.com/passgfw"
))

// 或添加单个 URL
passgfw.addURL("https://another.com/passgfw")
```

### 日志控制

```kotlin
val passgfw = PassGFW()

// 设置日志级别
passgfw.setLogLevel(LogLevel.INFO)  // 只显示 INFO 及以上

// 禁用日志
passgfw.setLoggingEnabled(false)
```

### 错误处理

```kotlin
lifecycleScope.launch {
    val server = passgfw.getFinalServer()
    if (server != null) {
        Log.d("PassGFW", "Success: $server")
    } else {
        val error = passgfw.getLastError()
        Log.e("PassGFW", "Error: $error")
    }
}
```

### 在 ViewModel 中使用

```kotlin
class MainViewModel : ViewModel() {
    private val passgfw = PassGFW()
    
    fun detectServer() {
        viewModelScope.launch {
            val server = passgfw.getFinalServer(customData = "android-app")
            // 更新 UI
        }
    }
}
```

## 权限

在 `AndroidManifest.xml` 中添加：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

## 构建

```bash
# 构建库
./gradlew :passgfw:build

# 运行测试
./gradlew :passgfw:test

# 生成 AAR
./gradlew :passgfw:assembleRelease
```

生成的 AAR 文件在：`passgfw/build/outputs/aar/`

## ProGuard

如果启用了代码混淆，添加以下规则到 `proguard-rules.pro`：

```proguard
# PassGFW
-keep class com.passgfw.** { *; }
-keepclassmembers class com.passgfw.** { *; }

# OkHttp
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }

# Gson
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
```

## API 文档

### PassGFW

主类，提供防火墙检测功能。

#### 方法

- `PassGFW()` - 创建实例
- `suspend fun getFinalServer(customData: String? = null): String?` - 获取可用服务器
- `fun setURLList(urls: List<String>)` - 设置 URL 列表
- `fun addURL(url: String)` - 添加 URL
- `fun getLastError(): String?` - 获取最后的错误
- `fun setLoggingEnabled(enabled: Boolean)` - 启用/禁用日志
- `fun setLogLevel(level: LogLevel)` - 设置日志级别

### LogLevel

日志级别枚举：
- `DEBUG` - 调试信息
- `INFO` - 一般信息
- `WARNING` - 警告
- `ERROR` - 错误

## 配置

编辑 `Config.kt` 修改默认配置：

- `REQUEST_TIMEOUT` - HTTP 超时时间 (ms)
- `MAX_RETRIES` - 最大重试次数
- `RETRY_DELAY` - 重试延迟 (ms)
- 其他配置选项

## 架构

```
com.passgfw/
├── PassGFW.kt           # 主入口
├── FirewallDetector.kt  # 核心检测逻辑
├── NetworkClient.kt     # HTTP 客户端 (OkHttp)
├── CryptoHelper.kt      # 加密和签名
├── Config.kt            # 配置
└── Logger.kt            # 日志系统
```

## 依赖

- Kotlin Coroutines 1.7.3
- OkHttp 4.12.0
- Gson 2.10.1
- AndroidX Core KTX 1.12.0

## 示例 App

查看 `example/` 目录中的完整示例应用。

## License

MIT License

