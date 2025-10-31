# PassGFW v2.0 升级指南

从 v1.0 升级到 v2.0 的完整指南

---

## 🚀 主要变化

### 新增功能

✅ **全平台加密存储**
- iOS/macOS: Keychain 加密
- Android: EncryptedSharedPreferences (AES256-GCM)
- HarmonyOS: **新增**完整存储功能

✅ **自动数据迁移**
- 从明文文件自动迁移到加密存储
- 迁移后自动删除旧文件
- 无需手动操作

✅ **改进的安全性**
- 系统级加密保护
- 硬件支持的密钥存储
- 防止数据泄露

---

## 📦 升级步骤

### iOS/macOS

#### 1. 更新代码（无需改动）

**✅ API 完全兼容，无需修改代码**

```swift
// v1.0 和 v2.0 代码完全相同
import PassGFW

let passgfw = PassGFWClient()
let server = await passgfw.getFinalServer()
```

#### 2. 重新编译

```bash
cd clients/ios-macos
swift build
```

#### 3. 测试迁移

首次运行时，会自动迁移数据：

```
检测到旧版本存储文件，开始数据迁移...
从旧文件读取了 3 个 URL
✅ 数据迁移成功，已保存到 Keychain
✅ 迁移验证成功
已删除旧版本存储文件
```

---

### Android

#### 1. 更新依赖

```kotlin
// build.gradle.kts
dependencies {
    // 新增依赖
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}
```

#### 2. 同步项目

```bash
cd clients/android
./gradlew clean
./gradlew build
```

#### 3. 代码改动（无需改动）

**✅ API 完全兼容**

```kotlin
// v1.0 和 v2.0 代码完全相同
val passgfw = PassGFW()
lifecycleScope.launch {
    val server = passgfw.getFinalServer()
}
```

#### 4. ProGuard 规则（推荐）

```proguard
# PassGFW
-keep class com.passgfw.** { *; }

# AndroidX Security
-keep class androidx.security.crypto.** { *; }
```

---

### HarmonyOS

#### 1. 新增文件

需要添加新文件：
- `URLStorageManager.ets`

#### 2. 修改初始化代码

**⚠️ 需要添加初始化调用**

```typescript
// ❌ v1.0 用法
const passgfw = new PassGFW();
const server = await passgfw.getFinalServer();

// ✅ v2.0 用法 - 需要先初始化
const passgfw = new PassGFW();
await passgfw.initialize(context);  // 新增
const server = await passgfw.getFinalServer();
```

#### 3. 更新 API 调用

```typescript
// v1.0
passgfw.setURLList(['url1', 'url2']);

// v2.0 - 使用 URLEntry[]
passgfw.setURLList([
    { method: 'api', url: 'url1' },
    { method: 'api', url: 'url2' }
]);
```

---

## 🔄 自动迁移详情

### iOS/macOS

**迁移时机**: URLStorageManager 初始化时

**流程**:
```
1. 检查 Keychain 是否有数据
   ↓ 无
2. 检查旧文件是否存在
   - iOS: ~/Documents/passgfw_urls.json
   - macOS: ~/Library/Application Support/PassGFW/passgfw_urls.json
   ↓ 存在
3. 读取并验证旧文件
   ↓
4. 保存到 Keychain
   ↓
5. 验证迁移成功
   ↓
6. 删除旧文件 ✅
```

**失败处理**: 保留旧文件，记录错误日志

---

### Android

**迁移时机**: URLStorageManager.initialize(context) 时

**流程**:
```
1. 检查 EncryptedSharedPreferences 是否有数据
   ↓ 无
2. 检查旧文件
   - /data/data/<package>/files/passgfw_urls.json
   ↓ 存在
3. 读取并验证旧文件
   ↓
4. 保存到 EncryptedSharedPreferences
   ↓
5. 验证迁移成功
   ↓
6. 删除旧文件 ✅
```

**失败处理**: 保留旧文件，抛出警告日志

---

### HarmonyOS

**无需迁移**: v1.0 没有存储功能

---

## ⚠️ 注意事项

### 1. 数据安全

**升级后数据自动加密**，但需注意：

```swift
// ❌ 不要在 URL 中包含敏感信息
let url = "https://api.com?token=secret123"

// ✅ 敏感信息应独立管理
let url = "https://api.com"
// Token 通过其他方式（如 Keychain）独立存储
```

### 2. 多用户场景

如果应用支持多用户/多账户：

```swift
// iOS/macOS - 为每个用户使用不同的 account
private let account = "stored_urls_\(userId)"

// Android - 为每个用户使用不同的 preferences name
private const val PREFS_NAME = "passgfw_secure_urls_${userId}"

// HarmonyOS - 为每个用户使用不同的 preferences name
private static readonly PREFS_NAME = `passgfw_urls_${userId}`;
```

### 3. 测试环境

**建议在测试环境先验证迁移**：

```bash
# 1. 使用 v1.0 生成测试数据
# 2. 升级到 v2.0
# 3. 验证数据迁移成功
# 4. 确认旧文件已删除
```

---

## 🔍 故障排除

### 问题1: Android 编译失败

**错误**:
```
Could not find androidx.security:security-crypto:1.1.0-alpha06
```

**解决**:
```kotlin
// settings.gradle.kts
repositories {
    google()
    mavenCentral()
}
```

---

### 问题2: iOS Keychain 访问失败

**错误**:
```
保存 URL 到 Keychain 失败
```

**可能原因**:
1. Keychain 访问权限被拒绝
2. 设备存储空间不足
3. 模拟器 Keychain 问题

**解决**:
1. 检查 Xcode 的 Capabilities 设置
2. 清理模拟器数据重试
3. 在真机上测试

---

### 问题3: HarmonyOS 初始化失败

**错误**:
```
URLStorageManager 未初始化
```

**原因**: 忘记调用 `initialize(context)`

**解决**:
```typescript
// 在使用前添加
await passgfw.initialize(context);
```

---

### 问题4: 迁移验证失败

**日志**:
```
⚠️ 迁移验证失败，保留旧文件以防数据丢失
```

**处理步骤**:
1. 检查日志查看具体错误
2. 确保有足够存储空间
3. 重启应用重试
4. 手动检查旧文件内容是否正确
5. 如持续失败，可手动删除旧文件（确保新存储正常）

---

## 📊 性能对比

| 操作 | v1.0 | v2.0 | 影响 |
|------|------|------|------|
| 初始化 | <1ms | <100ms | 可忽略 |
| 读取 URL | <5ms | <20ms | 可忽略 |
| 写入 URL | <5ms | <30ms | 可忽略 |
| 内存占用 | ~1MB | ~1.5MB | 可忽略 |

**结论**: 性能影响极小，安全性大幅提升 ✅

---

## 🎯 升级检查清单

### iOS/macOS

- [ ] 重新编译项目
- [ ] 首次运行验证迁移
- [ ] 检查日志确认成功
- [ ] 验证新数据正常存储
- [ ] （可选）确认旧文件已删除

### Android

- [ ] 添加 security-crypto 依赖
- [ ] 同步 Gradle
- [ ] 添加 ProGuard 规则
- [ ] 首次运行验证迁移
- [ ] 检查日志确认成功

### HarmonyOS

- [ ] 添加 URLStorageManager.ets
- [ ] 更新初始化代码
- [ ] 更新 API 调用（URLEntry）
- [ ] 测试新存储功能
- [ ] 验证数据持久化

---

## 📚 相关文档

- [安全性与权限说明](./SECURITY_AND_PERMISSIONS.md)
- [存储系统分析](./STORAGE_ANALYSIS.md)
- [主 README](../README.md)

---

## ✅ 升级完成

完成以上步骤后，您的应用已成功升级到 v2.0！

**主要收益**:
- ✅ 数据自动加密
- ✅ 更高的安全性
- ✅ HarmonyOS 完整存储支持
- ✅ 无缝迁移体验

---

**如有问题，请查阅文档或提交 Issue。**

最后更新: 2025-11-01
