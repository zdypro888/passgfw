# PassGFW 构建指南

本项目提供两种构建方式：**配置文件构建**和**交互式构建**。

---

## 🚀 快速开始

### 方式1：交互式构建（推荐新手）

```bash
./build_interactive.sh <platform>
```

脚本会引导您配置所有参数，支持：
- 📝 交互式输入配置
- 💾 保存配置供将来使用
- ✅ 默认值提示（黄色显示）
- 🎨 彩色界面，易于阅读

**示例**：
```bash
# 构建 iOS
./build_interactive.sh ios

# 构建 Android
./build_interactive.sh android

# 构建所有平台
./build_interactive.sh all
```

### 方式2：配置文件构建（推荐高级用户）

```bash
./build.sh <platform> --config <config_file>
```

**示例**：
```bash
# 使用默认配置
./build.sh ios

# 使用自定义配置
./build.sh android --config production_config.json

# 清理构建
./build.sh all --clean

# 并行构建所有平台
./build.sh all --parallel
```

---

## 📋 配置参数说明

### 1. 基础配置

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `urls` | Array | localhost:8080 | 检测 URL 列表 |
| `public_key_path` | String | ../server/keys/public_key.pem | RSA 公钥路径 |

### 2. 网络参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `request_timeout` | Number | 5 | HTTP 请求超时（秒） |
| `max_retries` | Number | 2 | 最大重试次数 |
| `retry_delay` | Number | 0.5 | 重试延迟（秒） |
| `retry_interval` | Number | 2 | 全部失败后重试间隔（秒） |
| `url_interval` | Number | 0.5 | URL 检测间隔（秒） |

### 3. 安全参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `max_list_recursion_depth` | Number | 5 | 最大递归深度 |
| `nonce_size` | Number | 32 | Nonce 大小（字节） |
| `max_client_data_size` | Number | 200 | 最大 client_data 大小（字节） |

### 4. 并发配置 ⚡ **新功能**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enable_concurrent_check` | Boolean | true | 启用并发检测 |
| `concurrent_check_count` | Number | 3 | 并发批次大小（同时检测的 URL 数） |
| `file_method_concurrent` | Boolean | false | File 类型是否允许并发（不推荐） |

---

## 📝 配置文件示例

### 最小配置
```json
{
  "urls": [
    {
      "method": "api",
      "url": "https://example.com/passgfw"
    }
  ],
  "public_key_path": "../server/keys/public_key.pem"
}
```

### 完整配置
```json
{
  "urls": [
    {
      "method": "api",
      "url": "https://api1.example.com/passgfw"
    },
    {
      "method": "api",
      "url": "https://api2.example.com/passgfw"
    },
    {
      "method": "file",
      "url": "https://example.com/urls.json"
    }
  ],
  "public_key_path": "../server/keys/production_key.pem",
  "config": {
    "request_timeout": 10,
    "max_retries": 3,
    "retry_delay": 1,
    "retry_interval": 5,
    "url_interval": 0.5,
    "max_list_recursion_depth": 5,
    "nonce_size": 32,
    "max_client_data_size": 200,
    "enable_concurrent_check": true,
    "concurrent_check_count": 5,
    "file_method_concurrent": false
  }
}
```

---

## 🎯 交互式构建流程示例

```bash
$ ./build_interactive.sh ios

╔══════════════════════════════════════════════════════════════════╗
║   🚀 PassGFW 交互式构建工具                                      ║
║   Version 2.1.0                                                  ║
╚══════════════════════════════════════════════════════════════════╝

本工具将引导您配置构建参数。
您可以直接按 Enter 使用默认值（黄色显示）。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 基础配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❯ 是否使用所有默认配置？(快速构建) [Y/n]: n

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 URL 配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
请输入检测 URL（支持多个）
格式: method,url
例如: api,http://example.com/passgfw

支持的 method: api, file, navigate, remove
输入空行完成输入

❯ URL #1 [默认: ]: api,https://api1.example.com/passgfw
✅ 已添加: api,https://api1.example.com/passgfw
❯ URL #2 [默认: ]: api,https://api2.example.com/passgfw
✅ 已添加: api,https://api2.example.com/passgfw
❯ URL #3 [默认: ]:

✅ 已配置 2 个 URL

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔑 公钥配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❯ 公钥文件路径 [默认: ../server/keys/public_key.pem]:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚙️  网络参数
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❯ HTTP 请求超时 (秒) [默认: 5]:
❯ 最大重试次数 [默认: 2]:
❯ 重试延迟 (秒) [默认: 0.5]:
❯ 全部失败后重试间隔 (秒) [默认: 2]:
❯ URL 检测间隔 (秒) [默认: 0.5]:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔒 安全参数
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❯ 最大递归深度 [默认: 5]:
❯ Nonce 大小 (字节) [默认: 32]:
❯ 最大 client_data 大小 (字节) [默认: 200]:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ 并发配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
并发检测可以显著提升检测速度（推荐启用）

❯ 启用并发检测？ [Y/n]: y
❯ 并发批次大小 (建议2-5) [默认: 3]: 5
❯ File 类型允许并发？(不推荐，可能导致递归爆炸) [y/N]: n

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 配置摘要
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
平台:       ios
URL 数量:   2
公钥:       ../server/keys/public_key.pem
超时:       5s
重试:       2次
并发检测:   启用 (批次大小: 5)

❯ 确认开始构建？ [Y/n]: y

❯ 是否保存此配置以供将来使用？ [y/N]: y
❯ 配置文件名 [默认: my_config.json]: production_config.json
✅ 配置已保存到: production_config.json
下次可使用: ./build.sh ios --config production_config.json

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔨 开始构建
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 临时配置文件已创建

✅ 调用构建脚本...

[构建过程...]

╔══════════════════════════════════════════════════════════════════╗
║   🎉 构建成功完成！                                               ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## 🔧 命令行选项 (build.sh)

```bash
./build.sh <platform> [options]
```

### 选项

| 选项 | 说明 |
|------|------|
| `--config FILE` | 使用自定义配置文件（默认: build_config.json） |
| `--urls "url1,url2"` | 临时覆盖 URLs |
| `--clean` | 清理构建产物 |
| `--parallel` | 并行构建所有平台（仅用于 `all`） |
| `--verify` | 构建后验证产物 |
| `--help` | 显示帮助信息 |

### 平台

- `ios` - 构建 iOS framework
- `macos` - 构建 macOS library
- `android` - 构建 Android AAR
- `harmony` - 更新 HarmonyOS 配置
- `all` - 构建所有平台

---

## ⚡ 并发检测说明

并发检测是 v2.1 新增的功能，可以显著提升检测速度：

### 性能对比

假设 10 个 URL，每个检测需要 2 秒：

| 模式 | 时间 | 提升 |
|------|------|------|
| 串行 | 20秒 | - |
| 并发3个 | 8秒 | **2.5倍** |
| 并发5个 | 4秒 | **5倍** |

### 推荐配置

| 场景 | `concurrent_check_count` | 说明 |
|------|--------------------------|------|
| 移动设备 | 2-3 | 节省流量和电量 |
| WiFi 环境 | 3-5 | 平衡速度和资源 |
| PC/服务器 | 5-10 | 快速找到可用服务器 |

### 重要提示

- ⚠️ **File 类型不建议并发**（`file_method_concurrent: false`）
  - File 类型会递归下载子列表
  - 并发可能导致递归爆炸（3个并发 × 10个子URL = 30个并发）
  - 保持 `false` 可避免此问题

---

## 📦 构建产物

### iOS/macOS
```
ios-macos/.build/release/
├── PassGFW (framework)
└── PassGFWExample
```

### Android
```
android/passgfw/build/outputs/aar/
└── passgfw-release.aar

android/app/build/outputs/apk/debug/
└── app-debug.apk (测试应用)
```

### HarmonyOS
```
harmony/entry/build/default/outputs/default/
└── entry-default-signed.hap
```

---

## 🐛 故障排除

### 1. 构建失败

**问题**: `BUILD FAILED`

**解决**:
```bash
# 清理并重新构建
./build.sh <platform> --clean
./build.sh <platform>
```

### 2. 公钥未找到

**问题**: `Public key not found`

**解决**:
```bash
# 脚本会自动生成 RSA 密钥对
# 或手动指定公钥路径：
./build.sh ios --config my_config.json
```

### 3. 权限问题

**问题**: `Permission denied`

**解决**:
```bash
chmod +x build.sh
chmod +x build_interactive.sh
```

---

## 📚 更多信息

- **源代码**: `build.sh` (主构建脚本)
- **交互式工具**: `build_interactive.sh` (新手友好)
- **默认配置**: `build_config.json`
- **版本**: v2.1.0

---

## 🎉 更新日志

### v2.1.0 (2025-01-XX)
- ✨ 新增交互式构建工具
- ⚡ 支持并发检测配置
- 💾 支持保存自定义配置
- 🎨 改进用户界面

### v2.0.0 (2025-01-XX)
- 🚀 初始版本
- 支持多平台构建
- 支持配置文件
