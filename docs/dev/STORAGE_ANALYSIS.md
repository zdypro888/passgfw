# PassGFW 存储系统全面分析报告

生成时间：2025-11-01

## 📊 当前实现概览

### 1. iOS/macOS 实现

**文件位置**：`clients/ios-macos/Sources/PassGFW/URLStorageManager.swift`

**存储路径**：
- iOS: `~/Documents/passgfw_urls.json`
- macOS: `~/Library/Application Support/PassGFW/passgfw_urls.json`

**实现方式**：
```swift
- 使用 JSONEncoder/JSONDecoder
- 文件系统直接读写
- 明文存储 JSON
```

**权限需求**：无需额外权限（沙盒内）

**安全性**：❌ **明文存储，无加密**

---

### 2. Android 实现

**文件位置**：`clients/android/passgfw/src/main/kotlin/com/passgfw/URLStorageManager.kt`

**存储路径**：
- `/data/data/<package_name>/files/passgfw_urls.json`

**实现方式**：
```kotlin
- 使用 Gson 序列化
- context.filesDir 内部存储
- 明文存储 JSON
- 单例模式（需初始化）
```

**权限需求**：
- ✅ 无需存储权限（内部存储自动拥有）
- ⚠️ 需要 INTERNET 权限（用于网络请求）

**安全性**：❌ **明文存储，无加密**

---

### 3. HarmonyOS 实现

**文件位置**：❌ **未实现**

**存储功能**：❌ **完全缺失**

**影响**：
- 无法使用 `store` 方法保存动态 URL
- 无法使用 `remove` 方法删除 URL
- 每次重启只能使用内置 URL 列表

---

## 🔐 数据格式

### URLEntry 数据结构

```json
[
  {
    "method": "api",
    "url": "https://server1.example.com/passgfw"
  },
  {
    "method": "file",
    "url": "https://cdn.example.com/list.txt"
  }
]
```

### 存储的数据示例

```json
[
  {"method":"api","url":"https://server1.example.com/passgfw"},
  {"method":"api","url":"https://server2.example.com/passgfw"},
  {"method":"api","url":"https://backup.example.com/passgfw"}
]
```

---

## ⚠️ 安全风险分析

### 1. 明文存储风险

| 平台 | 风险等级 | 具体威胁 |
|------|---------|---------|
| **iOS** | 🟠 中等 | 越狱设备可读取 Documents 目录 |
| **macOS** | 🟠 中等 | 管理员权限可读取用户数据 |
| **Android** | 🔴 高 | Root 设备、ADB 备份、文件浏览器可读取 |
| **HarmonyOS** | ⚪ 无 | 未实现存储 |

### 2. 数据泄露场景

**iOS/macOS**：
- iTunes/Finder 备份可能包含明文文件
- iCloud 同步可能暴露数据
- 越狱/Root 设备直接访问

**Android**：
- `adb backup` 可导出应用数据
- Root 权限直接访问 `/data/data/`
- 恶意应用通过漏洞读取
- 设备丢失后的数据恢复

### 3. 数据内容风险

**当前存储的敏感信息**：
- ✅ 服务器 URL 列表（可能包含内部服务器地址）
- ⚠️ CDN 地址（可能暴露分发网络）
- ⚠️ 备用服务器信息（暴露灾备架构）

**如果未来扩展包含**：
- 🔴 认证 Token
- 🔴 用户标识
- 🔴 会话信息

---

## 🔍 权限分析

### iOS/macOS

**当前权限**：
- ✅ 无需特殊权限
- ✅ 沙盒内自动拥有读写权限

**建议权限**（使用 Keychain）：
- ✅ 无需额外权限
- ✅ Keychain 访问权限自动授予
- ⚠️ 需要配置 Keychain Sharing（如果多 App 共享）

### Android

**当前权限**（AndroidManifest.xml）：
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

**改进后权限**（使用 EncryptedSharedPreferences）：
- ✅ 无需额外权限
- ✅ 自动使用 Android Keystore
- ⚠️ 最低 API 23（Android 6.0）

### HarmonyOS

**当前权限**（module.json5）：
```json
{
  "requestPermissions": [
    {"name": "ohos.permission.INTERNET"}
  ]
}
```

**改进后权限**（使用 Preferences）：
- ✅ 无需额外权限
- ✅ Preferences 自动拥有访问权限

---

## 📈 功能完整性对比

| 功能 | iOS/macOS | Android | HarmonyOS |
|------|-----------|---------|-----------|
| **加载内置 URL** | ✅ | ✅ | ✅ |
| **加载存储 URL** | ✅ | ✅ | ❌ |
| **保存 URL（store）** | ✅ | ✅ | ❌ |
| **删除 URL（remove）** | ✅ | ✅ | ❌ |
| **加密存储** | ❌ | ❌ | ❌ |
| **数据迁移** | ❌ | ❌ | ❌ |
| **错误恢复** | ⚠️ 基础 | ⚠️ 基础 | ❌ |

---

## 🎯 改进方案

### 方案 1：iOS/macOS - 使用 Keychain

**优点**：
- ✅ iOS/macOS 原生加密存储
- ✅ 系统级别安全保护
- ✅ 自动与 iCloud Keychain 同步（可选）
- ✅ 无需第三方库

**实现**：
```swift
// 使用 Security.framework
// 将 URLEntry[] 序列化为 JSON
// 存储到 Keychain
// Service: "com.passgfw.urls"
// Account: "stored_urls"
```

**向后兼容**：
- 检测旧版本文件存在
- 自动迁移到 Keychain
- 删除旧文件

---

### 方案 2：Android - 使用 EncryptedSharedPreferences

**优点**：
- ✅ AndroidX Security 官方库
- ✅ 自动使用 Android Keystore
- ✅ AES256-GCM 加密
- ✅ 简单易用

**依赖**：
```kotlin
implementation("androidx.security:security-crypto:1.1.0-alpha06")
```

**实现**：
```kotlin
val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .build()

val encryptedPrefs = EncryptedSharedPreferences.create(
    context,
    "passgfw_secure_urls",
    masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
)
```

**向后兼容**：
- 检测旧版本文件存在
- 自动迁移到加密存储
- 删除旧文件

---

### 方案 3：HarmonyOS - 实现 Preferences 存储

**优点**：
- ✅ HarmonyOS 官方推荐方式
- ✅ 轻量级键值存储
- ✅ 支持加密（需手动实现）
- ✅ 异步操作

**实现**：
```typescript
import dataPreferences from '@ohos.data.preferences';
import cryptoFramework from '@ohos.security.cryptoFramework';

// 1. 获取 Preferences 实例
// 2. 使用 AES 加密 JSON 字符串
// 3. 存储加密后的 Base64
// 4. 读取时解密
```

**存储位置**：
- `/data/app/el2/100/base/<bundleName>/preferences/passgfw_urls`

---

## 🔄 数据迁移策略

### 迁移流程

```
1. 启动应用
   ↓
2. 检查新存储（Keychain/EncryptedPrefs/Preferences）
   ↓
3. 如果为空，检查旧存储（明文文件）
   ↓
4. 如果旧文件存在
   ├─ 读取旧数据
   ├─ 写入新存储（加密）
   ├─ 验证迁移成功
   └─ 删除旧文件
   ↓
5. 正常使用新存储
```

### 错误处理

- 旧文件损坏：记录错误，使用空列表
- 迁移失败：保留旧文件，重试
- 新存储失败：回退到旧存储（但警告用户）

---

## 📚 最佳实践建议

### 1. 存储内容限制

```
✅ 应该存储：
- 服务器 URL 列表
- 连接方法类型
- 非敏感配置

❌ 不应该存储：
- 用户密码
- 认证 Token（应使用独立的安全存储）
- 个人身份信息
```

### 2. 数据大小限制

```
建议限制：
- 最多 100 个 URL
- 每个 URL 最长 2048 字符
- 总大小不超过 256KB
```

### 3. 访问控制

```
iOS/macOS:
- Keychain 访问控制：kSecAttrAccessibleAfterFirstUnlock
- 支持生物识别保护（可选）

Android:
- Keystore 保护级别：StrongBox（如果支持）
- 自动备份排除：android:allowBackup="false"

HarmonyOS:
- 使用 el2 加密等级
- 设备锁屏后数据保护
```

---

## 📝 文档改进建议

### README.md 需要补充：

1. **权限说明章节**：
   - 详细说明各平台需要的权限
   - 权限用途解释
   - 可选权限说明

2. **数据安全章节**：
   - 说明数据加密方式
   - 数据存储位置
   - 用户隐私保护措施

3. **版本升级指南**：
   - 旧版本到新版本的迁移
   - 数据兼容性说明

---

## 🚀 实施优先级

### P0 - 立即实施
1. ✅ iOS/macOS Keychain 加密存储
2. ✅ Android EncryptedSharedPreferences 加密存储
3. ✅ HarmonyOS 实现存储功能

### P1 - 近期实施
4. ✅ 数据迁移逻辑（所有平台）
5. ✅ 错误处理和日志完善
6. ✅ 单元测试覆盖

### P2 - 后续优化
7. 存储配额管理
8. 数据备份/恢复 API
9. 多用户数据隔离

---

## 🧪 测试计划

### 功能测试

1. **基础功能**：
   - 存储 URL
   - 读取 URL
   - 删除 URL
   - 清空所有 URL

2. **迁移测试**：
   - 旧版本 → 新版本自动迁移
   - 迁移后数据完整性
   - 迁移失败回退

3. **边界测试**：
   - 空数据
   - 大量数据（100+ URLs）
   - 超长 URL
   - 特殊字符

### 安全测试

1. **加密验证**：
   - 文件系统检查（确认加密）
   - 内存转储分析
   - Root/越狱设备测试

2. **权限测试**：
   - 最小权限原则
   - 拒绝权限的降级处理

---

## 📊 预期改进效果

| 指标 | 改进前 | 改进后 |
|------|-------|--------|
| **iOS 数据安全** | ⚪ 明文 | 🟢 Keychain 加密 |
| **Android 数据安全** | ⚪ 明文 | 🟢 AES256-GCM 加密 |
| **HarmonyOS 功能** | ❌ 无存储 | ✅ 完整存储 + 加密 |
| **数据迁移** | ❌ 无 | ✅ 自动迁移 |
| **平台一致性** | 🟠 不一致 | 🟢 完全一致 |

---

## 总结

当前存储系统存在以下主要问题：
1. **安全性不足**：iOS/Android 均为明文存储
2. **功能缺失**：HarmonyOS 完全未实现
3. **无数据迁移**：升级后可能丢失数据
4. **文档不完善**：缺少安全和权限说明

改进后将实现：
1. **全平台加密存储**
2. **统一的存储接口**
3. **自动数据迁移**
4. **完善的错误处理**
5. **详细的文档说明**

---

*报告作者：Claude (Anthropic)*
*项目：PassGFW*
*版本：1.0*
