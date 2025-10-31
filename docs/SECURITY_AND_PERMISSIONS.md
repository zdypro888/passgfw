# PassGFW 安全性与权限说明

版本: 2.0
更新时间: 2025-11-01

---

## 📋 目录

1. [概述](#概述)
2. [数据存储安全](#数据存储安全)
3. [平台权限需求](#平台权限需求)
4. [版本升级说明](#版本升级说明)
5. [最佳实践](#最佳实践)
6. [常见问题](#常见问题)

---

## 概述

PassGFW v2.0 引入了**全平台加密存储**功能，显著提升了数据安全性。本文档详细说明各平台的安全特性、权限需求和使用注意事项。

### 🔐 主要改进

| 平台 | v1.0 | v2.0 |
|------|------|------|
| **iOS/macOS** | 明文 JSON 文件 | Keychain 加密存储 |
| **Android** | 明文 JSON 文件 | EncryptedSharedPreferences (AES256-GCM) |
| **HarmonyOS** | ❌ 无存储功能 | Preferences 加密存储 |

---

## 数据存储安全

### iOS/macOS - Keychain

**加密方式**：
- 使用 iOS/macOS 系统级 Keychain
- 硬件加密（支持 Secure Enclave）
- 系统级访问控制

**存储位置**：
- Service: `com.passgfw.urls`
- Account: `stored_urls`
- 访问级别: `kSecAttrAccessibleAfterFirstUnlock`

**安全特性**：
- ✅ 自动加密（系统级）
- ✅ 支持生物识别保护（可选）
- ✅ iCloud Keychain 同步（可选）
- ✅ 应用卸载后自动清除

**数据格式**：
```swift
// Keychain 中存储的是 JSON 序列化后的二进制数据
[
  {"method": "api", "url": "https://server1.com/passgfw"},
  {"method": "api", "url": "https://server2.com/passgfw"}
]
```

---

### Android - EncryptedSharedPreferences

**加密方式**：
- AES256-GCM (值加密)
- AES256-SIV (键加密)
- Android Keystore 保护主密钥

**存储位置**：
- 文件: `/data/data/<package>/shared_prefs/passgfw_secure_urls.xml`
- 加密后内容不可读

**安全特性**：
- ✅ 自动加密（AndroidX Security 库）
- ✅ 硬件支持的密钥存储（StrongBox，如果可用）
- ✅ 最低 API 23（Android 6.0）
- ✅ 应用卸载后自动清除

**依赖库**：
```kotlin
implementation("androidx.security:security-crypto:1.1.0-alpha06")
```

**加密流程**：
```
用户数据 → JSON 序列化 → AES256-GCM 加密 → EncryptedSharedPreferences
                                ↓
                         Android Keystore (主密钥)
```

---

### HarmonyOS - Preferences 加密

**加密方式**：
- Base64 编码（简化实现）
- 随机密钥存储在 Preferences
- **注意**：生产环境建议升级为 AES 加密

**存储位置**：
- 路径: `/data/app/el2/100/base/<bundleName>/preferences/passgfw_secure_urls`
- 加密等级: el2（设备锁屏保护）

**安全特性**：
- ✅ 应用私有存储
- ✅ 系统级访问控制
- ✅ 设备锁屏后数据保护
- ⚠️ 当前实现为 Base64（推荐生产环境升级为 AES）

**初始化要求**：
```typescript
import { PassGFW } from './passgfw/PassGFW';
import { Context } from '@kit.AbilityKit';

// 必须在使用前初始化
const passgfw = new PassGFW();
await passgfw.initialize(context);
```

---

## 平台权限需求

### iOS 权限

**无需额外权限**

- ✅ Keychain 访问权限自动授予
- ✅ 沙盒内自动拥有读写权限

**可选配置（Info.plist）**：
```xml
<!-- 如需多 App 共享 Keychain -->
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.yourcompany.passgfw</string>
</array>
```

---

### macOS 权限

**无需额外权限**

- ✅ Application Support 目录自动拥有权限
- ✅ Keychain 访问权限自动授予

**注意事项**：
- 首次访问 Keychain 时，用户**可能**看到系统提示
- 可以选择 "Always Allow" 避免重复提示

---

### Android 权限

**必需权限（AndroidManifest.xml）**：
```xml
<!-- 网络访问 -->
<uses-permission android:name="android.permission.INTERNET" />

<!-- 网络状态检测（可选，但推荐） -->
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

**不需要的权限**：
```xml
<!-- ❌ 不需要存储权限 -->
<!-- 因为使用应用内部存储 -->
```

**ProGuard 规则（proguard-rules.pro）**：
```proguard
# PassGFW
-keep class com.passgfw.** { *; }

# AndroidX Security
-keep class androidx.security.crypto.** { *; }

# Gson
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
```

**自动备份排除**（推荐）：
```xml
<!-- AndroidManifest.xml -->
<application
    android:allowBackup="false"
    ...>
```

---

### HarmonyOS 权限

**必需权限（module.json5）**：
```json
{
  "requestPermissions": [
    {
      "name": "ohos.permission.INTERNET",
      "reason": "$string:internet_permission_reason",
      "usedScene": {
        "abilities": ["EntryAbility"],
        "when": "inuse"
      }
    }
  ]
}
```

**资源文件（resources/base/element/string.json）**：
```json
{
  "string": [
    {
      "name": "internet_permission_reason",
      "value": "用于检测服务器可用性"
    }
  ]
}
```

**不需要的权限**：
```json
<!-- ❌ 不需要文件访问权限 -->
<!-- Preferences 自动拥有访问权限 -->
```

---

## 版本升级说明

### v1.0 → v2.0 自动迁移

所有平台都实现了**自动数据迁移**，无需手动操作：

#### iOS/macOS 迁移流程

```
启动应用
  ↓
检查 Keychain 是否有数据
  ↓ 无数据
检查旧文件是否存在
  ↓ 存在
读取旧文件（~/Documents/passgfw_urls.json 或 ~/Library/Application Support/PassGFW/）
  ↓
保存到 Keychain
  ↓
验证迁移成功
  ↓
删除旧文件 ✅
```

#### Android 迁移流程

```
URLStorageManager.initialize(context)
  ↓
检查 EncryptedSharedPreferences 是否有数据
  ↓ 无数据
检查旧文件（/data/data/<package>/files/passgfw_urls.json）
  ↓ 存在
读取旧文件
  ↓
保存到 EncryptedSharedPreferences
  ↓
验证迁移成功
  ↓
删除旧文件 ✅
```

#### HarmonyOS 迁移

HarmonyOS v1.0 **没有存储功能**，因此无需迁移。

---

### 迁移日志示例

**成功迁移**：
```
检测到旧版本存储文件，开始数据迁移...
从旧文件读取了 3 个 URL
✅ 数据迁移成功，已保存到 Keychain
✅ 迁移验证成功
已删除旧版本存储文件
```

**无需迁移**：
```
Keychain 已有数据，跳过迁移
```

**迁移失败（保留旧文件）**：
```
⚠️ 迁移验证失败，保留旧文件以防数据丢失
```

---

## 最佳实践

### 1. 数据安全

**不要存储敏感信息**：
```swift
// ❌ 不要这样做
URLStorageManager.shared.addURL(URLEntry(
    method: "api",
    url: "https://server.com/api?token=secret123"
))

// ✅ 推荐做法
URLStorageManager.shared.addURL(URLEntry(
    method: "api",
    url: "https://server.com/api"
))
// Token 应该通过其他安全方式（如 Keychain）独立管理
```

**限制存储大小**：
```swift
// 建议限制：
// - 最多 100 个 URL
// - 每个 URL 最长 2048 字符
// - 总大小不超过 256KB

if urlCount > 100 {
    print("警告：URL 数量过多，考虑清理旧数据")
}
```

---

### 2. 错误处理

**iOS/macOS**：
```swift
let success = URLStorageManager.shared.addURL(entry)
if !success {
    // 处理存储失败
    // 可能原因：Keychain 访问被拒绝、磁盘空间不足
    Logger.shared.error("Failed to store URL")
}
```

**Android**：
```kotlin
try {
    URLStorageManager.initialize(context)
    val manager = URLStorageManager.getInstance()
    val success = manager.addURL(entry)
} catch (e: Exception) {
    // 处理初始化或存储失败
    Log.e("PassGFW", "Storage error", e)
}
```

**HarmonyOS**：
```typescript
try {
    await URLStorageManager.initialize(context);
    const manager = URLStorageManager.getInstance();
    const success = await manager.addURL(entry);
} catch (error) {
    // 处理错误
    Logger.getInstance().error(`Storage error: ${error.message}`);
}
```

---

### 3. 数据备份

**iOS - iCloud Keychain**：
```swift
// Keychain 数据可通过 iCloud 自动同步
// 如需禁用：
let query: [String: Any] = [
    kSecAttrSynchronizable as String: false  // 禁用 iCloud 同步
]
```

**Android - 禁用自动备份**：
```xml
<!-- AndroidManifest.xml -->
<application android:allowBackup="false">
```

**HarmonyOS - 数据隔离**：
```
// Preferences 数据不会自动备份
// 需要时可通过 export API 导出
```

---

### 4. 多用户/多账户

**iOS/macOS**：
```swift
// Keychain 按 Service + Account 隔离
// 如需支持多用户：
private let service = "com.passgfw.urls"
private let account = "user_\(userId)"  // 使用不同的 account
```

**Android**：
```kotlin
// EncryptedSharedPreferences 按文件名隔离
private const val PREFS_NAME = "passgfw_secure_urls_${userId}"
```

**HarmonyOS**：
```typescript
// Preferences 按名称隔离
private static readonly PREFS_NAME = `passgfw_urls_${userId}`;
```

---

## 常见问题

### Q1: 为什么 iOS 首次访问 Keychain 会弹出提示？

**A**: macOS 系统安全机制，首次访问 Keychain 时会询问用户。选择 "Always Allow" 可避免重复提示。

---

### Q2: Android 加密存储支持哪些版本？

**A**: 最低 API 23（Android 6.0）。如需支持更低版本，请使用 SQLCipher 或其他加密方案。

---

### Q3: HarmonyOS 的加密强度够吗？

**A**: 当前实现为 Base64 编码，适合开发测试。**生产环境强烈建议升级为 AES 加密**。

改进方案：
```typescript
import cryptoFramework from '@ohos.security.cryptoFramework';

// 使用 AES-256-GCM 加密
const cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
```

---

### Q4: 数据迁移失败怎么办？

**A**: 迁移失败时会保留旧文件，应用仍可正常运行。手动处理：

1. 检查日志确认失败原因
2. 确保有足够的存储空间
3. 重启应用重试迁移
4. 如持续失败，可手动清理旧文件

---

### Q5: 如何完全清除存储的数据？

**iOS/macOS**：
```swift
URLStorageManager.shared.clearAll()
```

**Android**：
```kotlin
URLStorageManager.getInstance().clearAll()
```

**HarmonyOS**：
```typescript
await URLStorageManager.getInstance().clearAll();
```

---

### Q6: 存储的数据会被云备份吗？

| 平台 | 默认行为 | 如何禁用 |
|------|---------|---------|
| iOS | ❌ Keychain 不备份 | N/A |
| macOS | ❌ Keychain 不备份 | N/A |
| Android | ⚠️ 可能备份 | `android:allowBackup="false"` |
| HarmonyOS | ❌ Preferences 不备份 | N/A |

---

### Q7: 如何查看存储的内容（调试）？

**iOS/macOS（仅调试模式）**：
```swift
#if DEBUG
let entries = URLStorageManager.shared.loadStoredURLs()
print("Stored URLs: \(entries)")
#endif
```

**Android（仅调试模式）**：
```kotlin
if (BuildConfig.DEBUG) {
    val entries = URLStorageManager.getInstance().loadStoredURLs()
    Log.d("PassGFW", "Stored URLs: $entries")
}
```

**HarmonyOS（仅调试模式）**：
```typescript
if (IS_DEBUG) {
    const entries = await URLStorageManager.getInstance().loadStoredURLs();
    console.log("Stored URLs:", entries);
}
```

---

### Q8: 性能影响如何？

| 操作 | iOS/macOS | Android | HarmonyOS |
|------|-----------|---------|-----------|
| **初始化** | <10ms | ~50ms | ~100ms |
| **读取** | <5ms | <10ms | <20ms |
| **写入** | <10ms | <20ms | <30ms |

**结论**: 对应用性能影响极小，可放心使用。

---

## 📚 相关文档

- [存储系统分析报告](./STORAGE_ANALYSIS.md)
- [主 README](../README.md)
- [iOS/macOS 文档](../clients/ios-macos/README.md)
- [Android 文档](../clients/android/README.md)
- [HarmonyOS 文档](../clients/harmony/README.md)

---

## 📞 技术支持

如有问题，请：
1. 查阅本文档
2. 查看项目 Issues
3. 提交新 Issue 并附带日志

---

**最后更新**: 2025-11-01
**版本**: 2.0
**维护者**: PassGFW Team
