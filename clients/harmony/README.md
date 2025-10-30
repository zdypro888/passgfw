# PassGFW - HarmonyOS Client (ArkTS)

纯 ArkTS 实现的 PassGFW 客户端，支持 HarmonyOS NEXT (API 10+)。

## 特性

- ✅ 纯 ArkTS 实现，使用 Promise/async
- ✅ 使用 @ohos.net.http + @ohos.security.cryptoFramework
- ✅ 完整的防火墙检测逻辑
- ✅ RSA 加密和签名验证
- ✅ 支持 list.txt# 动态列表
- ✅ 自动重试机制
- ✅ 统一日志系统

## 要求

- HarmonyOS NEXT (API 10+)
- DevEco Studio 4.0+
- ArkTS

## 安装

### 作为模块引入

将 `passgfw` 目录复制到您的项目中，然后：

```typescript
import { PassGFW } from './passgfw/PassGFW';
```

### HAR 包（未来支持）

```json
{
  "dependencies": {
    "passgfw": "1.0.0"
  }
}
```

## 使用

### 基本用法

```typescript
import { PassGFW } from './passgfw/PassGFW';

// 创建实例
const passgfw = new PassGFW();

// 获取可用服务器（异步）
async function detectServer() {
  const server = await passgfw.getFinalServer();
  if (server) {
    console.log(`Found server: ${server}`);
  }
}
```

### 带自定义数据

```typescript
// 发送自定义数据到服务器
const server = await passgfw.getFinalServer('harmony-app-v1.0');
if (server) {
  console.log(`Found server: ${server}`);
}
```

### 自定义 URL 列表

```typescript
const passgfw = new PassGFW();

// 设置自定义 URL 列表
passgfw.setURLList([
  'https://example.com/passgfw',
  'https://backup.com/passgfw'
]);

// 或添加单个 URL
passgfw.addURL('https://another.com/passgfw');
```

### 日志控制

```typescript
import { PassGFW, LogLevel } from './passgfw/PassGFW';

const passgfw = new PassGFW();

// 设置日志级别
passgfw.setLogLevel(LogLevel.INFO);  // 只显示 INFO 及以上

// 禁用日志
passgfw.setLoggingEnabled(false);
```

### 错误处理

```typescript
const server = await passgfw.getFinalServer();
if (server) {
  console.log(`Success: ${server}`);
} else {
  const error = passgfw.getLastError();
  console.error(`Error: ${error}`);
}
```

### 在 Page 中使用

```typescript
@Entry
@Component
struct MainPage {
  @State serverDomain: string = '';
  private passgfw: PassGFW = new PassGFW();
  
  async detectServer() {
    const server = await this.passgfw.getFinalServer('harmony-demo');
    if (server) {
      this.serverDomain = server;
    }
  }
  
  build() {
    Column() {
      Text(this.serverDomain)
      Button('Detect Server')
        .onClick(() => this.detectServer())
    }
  }
}
```

## 权限

在 `module.json5` 中添加：

```json
{
  "requestPermissions": [
    {
      "name": "ohos.permission.INTERNET"
    }
  ]
}
```

## 构建

在 DevEco Studio 中：

1. 打开项目
2. Build > Make Module 'entry'
3. 或直接运行应用

## API 文档

### PassGFW

主类，提供防火墙检测功能。

#### 方法

- `constructor()` - 创建实例
- `async getFinalServer(customData?: string): Promise<string | null>` - 获取可用服务器
- `setURLList(urls: string[]): void` - 设置 URL 列表
- `addURL(url: string): void` - 添加 URL
- `getLastError(): string | null` - 获取最后的错误
- `setLoggingEnabled(enabled: boolean): void` - 启用/禁用日志
- `setLogLevel(level: LogLevel): void` - 设置日志级别

### LogLevel

日志级别枚举：
- `DEBUG` = 0 - 调试信息
- `INFO` = 1 - 一般信息
- `WARNING` = 2 - 警告
- `ERROR` = 3 - 错误

## 配置

编辑 `Config.ets` 修改默认配置：

- `REQUEST_TIMEOUT` - HTTP 超时时间 (ms)
- `MAX_RETRIES` - 最大重试次数
- `RETRY_DELAY` - 重试延迟 (ms)
- 其他配置选项

## 架构

```
ets/passgfw/
├── PassGFW.ets           # 主入口
├── FirewallDetector.ets  # 核心检测逻辑
├── NetworkClient.ets     # HTTP 客户端
├── CryptoHelper.ets      # 加密和签名
├── Config.ets            # 配置
└── Logger.ets            # 日志系统
```

## 依赖

- @ohos.net.http - HTTP 网络请求
- @ohos.security.cryptoFramework - 加密框架
- @kit.ArkTS - ArkTS 工具包

## 注意事项

1. **权限申请**: 必须在 `module.json5` 中申请 `INTERNET` 权限
2. **异步操作**: 所有网络操作都是异步的，请使用 `await`
3. **错误处理**: 检测失败时会返回 `null`，可通过 `getLastError()` 获取错误信息
4. **日志**: 使用 HiLog 输出日志，可在 DevEco Studio 的 Log 窗口查看

## 测试

使用 DevEco Studio 的测试工具：

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { PassGFW } from '../passgfw/PassGFW';

describe('PassGFW Test', () => {
  it('should detect server', async () => {
    const passgfw = new PassGFW();
    const server = await passgfw.getFinalServer();
    expect(server).not.toBeNull();
  });
});
```

## License

MIT License

