# PassGFW 客户端测试指南

完整的三平台客户端测试流程。

## 前提条件

### 1. 启动服务器

```bash
cd /Users/zdypro/Documents/projects/src/passgfw/server
go run main.go --port 8080 --domain localhost:8080
```

服务器应该显示：
```
Server running on :8080
Using domain: localhost:8080
```

## 平台测试

---

## 📱 iOS/macOS (Swift) 测试

### 方式 1: Swift 命令行（最快）

```bash
cd /Users/zdypro/Documents/projects/src/passgfw/clients/ios-macos
swift run
```

或直接运行示例：

```bash
cd /Users/zdypro/Documents/projects/src/passgfw/clients/ios-macos/Examples
swift example_macos.swift
```

### 方式 2: Swift Package Manager

```bash
cd /Users/zdypro/Documents/projects/src/passgfw/clients/ios-macos/PassGFW

# 构建
swift build

# 运行测试
swift test

# 运行示例
.build/debug/PassGFWExample
```

### 方式 3: Xcode 项目

```bash
cd /Users/zdypro/Documents/projects/src/passgfw/clients/ios-macos/PassGFW

# 生成 Xcode 项目
swift package generate-xcodeproj

# 在 Xcode 中打开
open PassGFW.xcodeproj
```

然后在 Xcode 中：
1. 选择 scheme: PassGFW-Package
2. 设置断点在 `FirewallDetector.swift`
3. 运行 (Cmd+R)

### 预期输出

```
╔════════════════════════════════════════════════════════════╗
║           PassGFW Client - macOS Example (Swift)          ║
╚════════════════════════════════════════════════════════════╝

🔍 Starting firewall detection...
⚠️  Note: This will block until an available server is found
⚠️  Make sure server is running: cd server && go run main.go

[2025-10-30T...] [DEBUG] getFinalServer() called with customData: macos-swift-example
[2025-10-30T...] [DEBUG] URL list size: 2
[2025-10-30T...] [DEBUG] Starting URL iteration...
[2025-10-30T...] [DEBUG] Checking URL: http://localhost:8080/passgfw
[2025-10-30T...] [INFO] Successfully verified URL: http://localhost:8080/passgfw on attempt 1
[2025-10-30T...] [INFO] Found available server: localhost:8080

✅ Found available server: localhost:8080
```

---

## 🤖 Android (Kotlin) 测试

### 方式 1: Gradle 构建

```bash
cd /Users/zdypro/Documents/projects/src/passgfw/clients/android

# 构建库
./gradlew :passgfw:build

# 运行测试
./gradlew :passgfw:test

# 生成 AAR
./gradlew :passgfw:assembleRelease
```

AAR 输出在: `passgfw/build/outputs/aar/passgfw-release.aar`

### 方式 2: Android Studio

1. 打开 Android Studio
2. File > Open > 选择 `clients/android/`
3. 等待 Gradle 同步
4. 创建测试文件 `PassGFWTest.kt`:

```kotlin
package com.passgfw

import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.Assert.*

class PassGFWTest {
    @Test
    fun testDetection() = runBlocking {
        val passgfw = PassGFW()
        val server = passgfw.getFinalServer("test-android")
        assertNotNull(server)
        println("Found server: $server")
    }
}
```

5. 运行测试 (右键 > Run)

### 方式 3: 示例 App（需要创建）

在 `android/example/` 创建简单的 Activity：

```kotlin
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val passgfw = PassGFW()
        
        lifecycleScope.launch {
            val server = passgfw.getFinalServer("android-example")
            Log.d("PassGFW", "Server: $server")
        }
    }
}
```

### 预期日志（Logcat）

```
D/PassGFW: [DEBUG] getFinalServer() called with customData: test-android
D/PassGFW: [DEBUG] URL list size: 2
D/PassGFW: [DEBUG] Checking URL: http://localhost:8080/passgfw
I/PassGFW: [INFO] Successfully verified URL: http://localhost:8080/passgfw on attempt 1
I/PassGFW: [INFO] Found available server: localhost:8080
```

**注意**: Android 模拟器需要使用 `10.0.2.2` 代替 `localhost`

---

## 🌟 HarmonyOS (ArkTS) 测试

### 方式 1: DevEco Studio

1. 打开 DevEco Studio
2. File > Open > 选择 `clients/harmony/`
3. 等待项目同步
4. 创建测试页面 `TestPage.ets`:

```typescript
import { PassGFW } from '../passgfw/PassGFW';

@Entry
@Component
struct TestPage {
  @State result: string = 'Testing...';
  private passgfw: PassGFW = new PassGFW();
  
  aboutToAppear() {
    this.testDetection();
  }
  
  async testDetection() {
    const server = await this.passgfw.getFinalServer('harmony-test');
    this.result = server ? `Server: ${server}` : 'Failed';
  }
  
  build() {
    Column() {
      Text(this.result)
        .fontSize(20)
    }
    .width('100%')
    .height('100%')
  }
}
```

5. 运行项目到模拟器/真机

### 方式 2: 命令行（如果支持）

```bash
cd /Users/zdypro/Documents/projects/src/passgfw/clients/harmony

# 构建
hvigorw assembleHap

# 安装到设备
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

### 预期日志（HiLog）

在 DevEco Studio 的 Log 窗口：

```
[PassGFW] [DEBUG] getFinalServer() called with customData: harmony-test
[PassGFW] [DEBUG] URL list size: 2
[PassGFW] [DEBUG] Checking URL: http://localhost:8080/passgfw
[PassGFW] [INFO] Successfully verified URL: http://localhost:8080/passgfw on attempt 1
[PassGFW] [INFO] Found available server: localhost:8080
```

---

## 🔍 调试技巧

### iOS/macOS 调试

使用 lldb:
```bash
cd clients/ios-macos/PassGFW
swift build
lldb .build/debug/PassGFWExample

(lldb) b FirewallDetector.swift:50
(lldb) run
```

### Android 调试

在 Android Studio 中：
1. 设置断点在 `FirewallDetector.kt`
2. Debug > Attach Debugger to Android Process
3. 选择应用进程

### HarmonyOS 调试

在 DevEco Studio 中：
1. 设置断点在 `FirewallDetector.ets`
2. Run > Debug 'entry'
3. 使用 Inspector 查看变量

---

## 🧪 单元测试

### iOS/macOS

```swift
import XCTest
@testable import PassGFW

final class PassGFWTests: XCTestCase {
    func testDetection() async throws {
        let passgfw = PassGFW()
        let server = await passgfw.getFinalServer()
        XCTAssertNotNil(server)
    }
}
```

运行: `swift test`

### Android

```kotlin
@Test
fun testDetection() = runBlocking {
    val passgfw = PassGFW()
    val server = passgfw.getFinalServer("test")
    assertNotNull(server)
}
```

运行: `./gradlew test`

### HarmonyOS

```typescript
import { describe, it, expect } from '@ohos/hypium';

describe('PassGFW Test', () => {
  it('should detect server', async () => {
    const passgfw = new PassGFW();
    const server = await passgfw.getFinalServer();
    expect(server).not.toBeNull();
  });
});
```

---

## ❌ 常见问题

### 1. 连接失败

**问题**: `Connection refused` 或 `Network error`

**解决**:
- 确认服务器正在运行: `curl http://localhost:8080/passgfw`
- 检查防火墙设置
- Android 模拟器使用 `10.0.2.2` 代替 `localhost`

### 2. 签名验证失败

**问题**: `Signature verification failed`

**解决**:
- 确认 public key 正确嵌入
- 检查服务器使用的 private key 匹配

### 3. iOS/macOS 编译错误

**问题**: `No such module 'PassGFW'`

**解决**:
```bash
swift package clean
swift build
```

### 4. Android Gradle 同步失败

**问题**: `Could not resolve dependencies`

**解决**:
```bash
./gradlew --refresh-dependencies
```

### 5. HarmonyOS 编译错误

**问题**: `Module not found`

**解决**:
- File > Invalidate Caches / Restart
- Rebuild Project

---

## 📊 性能测试

### 测试检测速度

```typescript
const start = Date.now();
const server = await passgfw.getFinalServer();
const duration = Date.now() - start;
console.log(`Detection took ${duration}ms`);
```

预期时间:
- 本地服务器: 50-200ms
- 远程服务器: 200-1000ms
- 失败重试: 3000-6000ms (取决于配置)

---

## ✅ 验收标准

所有平台应该:
1. ✅ 成功连接到服务器
2. ✅ 正确加密/解密数据
3. ✅ 验证签名通过
4. ✅ 返回正确的 domain
5. ✅ 日志输出正确
6. ✅ 错误处理正确
7. ✅ 重试机制工作

---

## 📝 测试报告模板

```
测试日期: 2025-10-30
测试平台: [iOS/Android/HarmonyOS]
测试版本: 1.0.0

结果:
- 基本检测: [✅/❌]
- 自定义数据: [✅/❌]
- 列表 URL: [✅/❌]
- 重试机制: [✅/❌]
- 日志系统: [✅/❌]
- 错误处理: [✅/❌]

性能:
- 平均检测时间: XXXms
- 内存占用: XXX MB

问题:
- [描述任何问题]

建议:
- [改进建议]
```

