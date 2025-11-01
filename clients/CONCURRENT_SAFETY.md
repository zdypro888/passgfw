# 并发检测安全机制说明

## 🔒 问题分析

### 原始问题

在实现并发检测时，如果不做特殊处理，会导致以下问题：

#### 问题1：Navigate 方法并发执行
```
URL列表: [navigate:url1, navigate:url2, navigate:url3, api:url4, api:url5]
批次大小: 3

❌ 错误行为（未修复前）:
批次1: [navigate:url1, navigate:url2, navigate:url3] → 并发执行
结果: 同时打开3个浏览器窗口！用户体验极差！
```

#### 问题2：Remove 方法并发执行
```
URL列表: [remove:url1, remove:url2, api:url3]

❌ 错误行为（未修复前）:
批次1: [remove:url1, remove:url2, api:url3] → 并发执行
结果: 同时删除多个URL，可能导致存储竞争问题
```

#### 问题3：File 方法递归爆炸
```
URL列表: [file:list1, file:list2, file:list3]
每个 file 返回 10 个子 URL

❌ 错误行为（未修复前）:
批次1: 3个 file 并发下载
  → file:list1 递归检测 10 个子URL
  → file:list2 递归检测 10 个子URL
  → file:list3 递归检测 10 个子URL
结果: 可能同时检测 30 个 URL！
```

---

## ✅ 修复方案

### 核心策略：方法分类处理

将所有 URL 方法分为两类：

| 类别 | 方法 | 处理方式 | 原因 |
|------|------|---------|------|
| **特殊方法** | `navigate`, `remove` | **串行执行** | 不应同时打开多个浏览器 / 确保删除顺序 |
| **普通方法** | `api`, `file` | **并发执行** | 可以安全并发（file可配置） |

### 执行顺序

```
getFinalServer()
    ↓
加载 URL 列表
    ↓
┌─────────────────────────────────────────┐
│ 第一阶段: 串行处理特殊方法              │
│                                          │
│  navigate:url1 → 打开浏览器             │
│    ↓ 等待 URL_INTERVAL                  │
│  navigate:url2 → 打开浏览器             │
│    ↓ 等待 URL_INTERVAL                  │
│  remove:url3 → 删除 URL                 │
│                                          │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 第二阶段: 并发处理普通方法              │
│                                          │
│  批次1: [api:url4, api:url5, file:url6] │
│    ├─ api:url4 ─┐                       │
│    ├─ api:url5 ─┼→ 并发执行             │
│    └─ file:url6 ┘                       │
│                                          │
│  如果全部失败，继续下一批次...          │
└─────────────────────────────────────────┘
```

---

## 📋 实现细节

### Android (Kotlin)

```kotlin
private suspend fun checkURLsConcurrently(
    entries: List<URLEntry>,
    customData: String?,
    batchSize: Int
): String? = coroutineScope {
    // 1. 分离特殊方法和普通方法
    val specialMethods = setOf("navigate", "remove")
    val (specialEntries, normalEntries) = entries.partition {
        specialMethods.contains(it.method.lowercase())
    }

    // 2. 串行处理特殊方法
    if (specialEntries.isNotEmpty()) {
        Logger.debug("串行处理 ${specialEntries.size} 个特殊方法 URL")
        for (entry in specialEntries) {
            val domain = checkURLEntry(entry, customData, 0)
            if (domain != null) {
                urlManager.recordSuccess(entry.url)
                return@coroutineScope domain
            } else {
                urlManager.recordFailure(entry.url)
            }
            delay(Config.URL_INTERVAL)
        }
    }

    // 3. 并发处理普通方法（按批次）
    if (normalEntries.isEmpty()) {
        return@coroutineScope null
    }

    Logger.debug("并发处理 ${normalEntries.size} 个普通方法 URL")

    for (batchStart in normalEntries.indices step batchSize) {
        val batch = normalEntries.subList(batchStart, batchEnd)

        // 批次内并发
        val results = batch.map { entry ->
            async(Dispatchers.IO) {
                checkURLEntry(entry, customData, 0)
            }
        }.awaitAll()

        // 处理结果...
    }

    return@coroutineScope null
}
```

### iOS (Swift)

```swift
private func checkURLsConcurrently(
    entries: [URLEntry],
    customData: String?,
    batchSize: Int
) async -> String? {
    // 1. 分离特殊方法和普通方法
    let specialMethods = Set(["navigate", "remove"])
    let specialEntries = entries.filter {
        specialMethods.contains($0.method.lowercased())
    }
    let normalEntries = entries.filter {
        !specialMethods.contains($0.method.lowercased())
    }

    // 2. 串行处理特殊方法
    if !specialEntries.isEmpty {
        Logger.shared.debug("串行处理 \(specialEntries.count) 个特殊方法 URL")
        for entry in specialEntries {
            if let domain = await checkURLEntry(entry, ...) {
                await urlManager.recordSuccess(url: entry.url)
                return domain
            } else {
                await urlManager.recordFailure(url: entry.url)
            }
            try? await Task.sleep(nanoseconds: ...)
        }
    }

    // 3. 并发处理普通方法（按批次）
    if normalEntries.isEmpty {
        return nil
    }

    Logger.shared.debug("并发处理 \(normalEntries.count) 个普通方法 URL")

    for batchStart in stride(from: 0, to: normalEntries.count, by: batchSize) {
        let batch = Array(normalEntries[batchStart..<batchEnd])

        // 批次内并发
        let domain: String? = await withTaskGroup(...) { group in
            for entry in batch {
                group.addTask {
                    await self.checkURLEntry(entry, ...)
                }
            }
            // 收集结果...
        }

        if let domain = domain {
            return domain
        }
    }

    return nil
}
```

---

## 🧪 测试场景

### 场景1：混合 URL 列表

```json
{
  "urls": [
    {"method": "navigate", "url": "https://help.example.com"},
    {"method": "api", "url": "https://api1.example.com/passgfw"},
    {"method": "api", "url": "https://api2.example.com/passgfw"},
    {"method": "remove", "url": "https://old-api.example.com/passgfw"},
    {"method": "api", "url": "https://api3.example.com/passgfw"}
  ]
}
```

**执行顺序**（并发数=3）:
```
1. 串行处理特殊方法:
   navigate:help.example.com → 打开浏览器
   remove:old-api.example.com → 删除 URL

2. 并发处理普通方法（批次大小=3）:
   批次1: [api1, api2, api3] → 并发检测
```

### 场景2：全是 Navigate

```json
{
  "urls": [
    {"method": "navigate", "url": "https://help1.com"},
    {"method": "navigate", "url": "https://help2.com"},
    {"method": "navigate", "url": "https://help3.com"}
  ]
}
```

**执行顺序**:
```
✅ 全部串行执行，每个之间等待 URL_INTERVAL
   navigate:help1.com
   → 等待 0.5s
   navigate:help2.com
   → 等待 0.5s
   navigate:help3.com
```

### 场景3：全是 API

```json
{
  "urls": [
    {"method": "api", "url": "https://api1.com/passgfw"},
    {"method": "api", "url": "https://api2.com/passgfw"},
    {"method": "api", "url": "https://api3.com/passgfw"},
    {"method": "api", "url": "https://api4.com/passgfw"},
    {"method": "api", "url": "https://api5.com/passgfw"}
  ]
}
```

**执行顺序**（并发数=3）:
```
✅ 全部并发检测
   批次1: [api1, api2, api3] → 并发
   批次2: [api4, api5] → 并发
```

---

## 📊 性能影响

### 最坏情况分析

假设 10 个 URL，每个检测需要 2 秒：

| 场景 | 串行模式 | 并发模式（3个） | 说明 |
|------|---------|----------------|------|
| **全是 API** | 20秒 | 8秒 | **2.5倍提升** |
| **全是 Navigate** | 20秒 | 20秒 | 无提升（必须串行） |
| **混合 (5 API + 5 Navigate)** | 20秒 | ~14秒 | **1.4倍提升** |

### 实际场景

大多数情况下，URL 列表主要是 `api` 和 `file` 方法，`navigate` 和 `remove` 较少，因此并发优化仍能带来显著提升。

---

## 🛡️ 安全保证

### 1. Navigate 方法
- ✅ **始终串行执行**
- ✅ **避免重复打开**（已有 `openedNavigateURLs` 去重）
- ✅ **不阻塞主流程**（打开后继续检测）

### 2. Remove 方法
- ✅ **始终串行执行**
- ✅ **线程安全**（URLManager 使用 Mutex/Actor）
- ✅ **顺序删除**（按 URL 列表顺序）

### 3. File 方法
- ✅ **可配置并发**（默认禁止）
- ✅ **递归深度限制**（防止无限递归）
- ✅ **串行模式可用**（避免递归爆炸）

### 4. API 方法
- ✅ **安全并发**（无副作用）
- ✅ **独立检测**（互不影响）
- ✅ **批次控制**（限制并发数）

---

## ⚙️ 配置选项

### 并发相关配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `enable_concurrent_check` | Boolean | `true` | 是否启用并发检测 |
| `concurrent_check_count` | Number | `3` | 并发批次大小 |
| `file_method_concurrent` | Boolean | `false` | File 方法是否允许并发 |

### 配置示例

```json
{
  "config": {
    "enable_concurrent_check": true,
    "concurrent_check_count": 5,
    "file_method_concurrent": false
  }
}
```

### 推荐配置

| 场景 | `concurrent_check_count` | `file_method_concurrent` |
|------|--------------------------|--------------------------|
| **移动设备** | 2-3 | `false` |
| **WiFi环境** | 3-5 | `false` |
| **PC/服务器** | 5-10 | `false`（仍不推荐） |

---

## 📝 注意事项

### 1. 特殊方法的顺序
特殊方法（navigate, remove）会**严格按照 URL 列表顺序**执行：

```
URL列表: [navigate:A, api:B, navigate:C, api:D]

执行顺序:
1. navigate:A  （串行）
2. navigate:C  （串行）
3. [api:B, api:D] （并发批次）
```

**注意**: navigate:C 会在 navigate:A 之后立即执行，不会等待 api:B。

### 2. File 方法的并发风险
即使设置 `file_method_concurrent: true`，也要注意：
- File 方法会递归下载子列表
- 如果多个 file 并发，可能产生大量并发请求
- 建议保持 `false` 以避免问题

### 3. 性能调优
- 如果 URL 列表中大部分是 navigate/remove，并发优化效果有限
- 如果主要是 api/file，可以适当增加并发数
- 根据网络环境调整 `concurrent_check_count`

---

## 🔄 版本历史

### v2.1.1 - Navigate/Remove 安全修复
- ✅ Navigate 方法始终串行执行
- ✅ Remove 方法始终串行执行
- ✅ 方法分类处理机制
- ✅ 保持 URL 列表顺序

### v2.1.0 - 并发检测支持
- ✅ 基础并发检测实现
- ✅ File 方法并发配置
- ✅ 线程安全机制

---

## 📚 相关文档

- `BUILD_README.md` - 构建系统使用指南
- `build_config.json` - 默认配置文件
- `build_interactive.sh` - 交互式构建工具

---

## ✅ 总结

通过方法分类处理机制，我们确保了：

1. **Navigate 方法不会同时打开多个浏览器窗口**
2. **Remove 方法按顺序删除 URL**
3. **File 方法可控制并发，避免递归爆炸**
4. **API 方法安全并发，提升性能**
5. **保持 URL 列表的逻辑顺序**

这样既获得了并发检测的性能提升，又避免了特殊方法的并发问题。
