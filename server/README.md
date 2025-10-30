# PassGFW Server

Go 服务器，用于 PassGFW 客户端验证。

## 🚀 快速开始

### 1. 生成密钥（首次运行）

```bash
cd server
mkdir -p keys
openssl genrsa -out keys/private_key.pem 2048
openssl rsa -in keys/private_key.pem -pubout -out keys/public_key.pem
```

这会创建：
- `keys/private_key.pem` - 服务器使用（**勿泄露**）
- `keys/public_key.pem` - 嵌入客户端

### 2. 启动服务器

```bash
cd server
go run main.go --port 8080 --domain localhost:8080
```

服务器将在 `http://localhost:8080` 启动

### 3. 自定义选项

```bash
# 自定义端口
go run main.go --port 3000

# 自定义域名（重要：防止 Host 头欺骗）
go run main.go --domain your-server.com:8080

# 自定义密钥路径
go run main.go --private-key /path/to/private.pem

# 所有选项
go run main.go --port 3000 --domain example.com:3000 --private-key ./keys/private.pem
```

---

## 📡 API 端点

### POST /passgfw

主验证端点。

**请求：**
```json
{
  "data": "BASE64_ENCRYPTED_JSON"
}
```

加密的 JSON 内容：
```json
{
  "nonce": "RANDOM_BASE64_STRING",
  "client_data": "CUSTOM_CLIENT_DATA"
}
```

**响应：**
```json
{
  "data": "{\"nonce\":\"...\",\"server_domain\":\"...\"}",
  "signature": "BASE64_SIGNATURE"
}
```

**流程：**
1. 客户端生成随机 nonce
2. 构建 JSON: `{"nonce":"...", "client_data":"..."}`
3. 用公钥加密 JSON
4. 服务器用私钥解密
5. 服务器返回 nonce + server_domain
6. 服务器用私钥签名响应
7. 客户端验证签名和 nonce

### GET /health

健康检查端点。

**响应：**
```json
{
  "status": "ok",
  "server": "PassGFW Server"
}
```

### GET /

HTML 页面，显示服务器信息。

---

## 🔧 构建

### 开发模式

```bash
# 使用默认设置运行
go run main.go

# 详细日志模式
go run main.go --debug
```

### 生产环境二进制

```bash
# 为当前平台构建
go build -o passgfw-server

# 运行
./passgfw-server --port 8080 --domain example.com:8080
```

### 交叉编译

```bash
# Linux
GOOS=linux GOARCH=amd64 go build -o passgfw-server-linux

# macOS (Apple Silicon)
GOOS=darwin GOARCH=arm64 go build -o passgfw-server-macos-arm64

# macOS (Intel)
GOOS=darwin GOARCH=amd64 go build -o passgfw-server-macos-x64

# Windows
GOOS=windows GOARCH=amd64 go build -o passgfw-server.exe
```

---

## 🔒 安全注意事项

1. **私钥保护**：绝不泄露或提交 `private_key.pem`
2. **HTTPS**：生产环境使用 HTTPS（推荐反向代理）
3. **速率限制**：生产环境添加速率限制
4. **防火墙**：限制可信 IP 访问
5. **域名验证**：使用 `--domain` 参数防止 Host 头欺骗

---

## 📝 示例：使用 Nginx 部署

```nginx
server {
    listen 443 ssl;
    server_name example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location /passgfw {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## 🧪 测试

### 使用客户端测试

最简单的方式是使用客户端：

```bash
# iOS/macOS
cd ../clients/ios-macos/Examples
swift example_macos.swift

# Android
cd ../clients/android
./gradlew :passgfw:build

# HarmonyOS
# 使用 DevEco Studio 打开 clients/harmony/
```

### 使用 curl 测试

```bash
# 健康检查
curl http://localhost:8080/health

# 主页
curl http://localhost:8080/
```

---

## 📊 日志

服务器会记录所有请求：

```
🚀 PassGFW Server Starting...
✅ Private key loaded from keys/private_key.pem
✅ Server domain set to: localhost:8080
🌐 Server listening on :8080

📥 Request from 127.0.0.1:51234
✅ Decrypted nonce: AbCdEf123456...
✅ Client data: test-client
📤 Response sent successfully: localhost:8080
```

---

## 🐳 Docker（可选）

```dockerfile
FROM golang:1.21-alpine

WORKDIR /app
COPY . .
RUN go build -o passgfw-server

EXPOSE 8080
CMD ["./passgfw-server", "--port", "8080"]
```

```bash
docker build -t passgfw-server .
docker run -p 8080:8080 \
  -v ./keys:/app/keys \
  -e DOMAIN=example.com:8080 \
  passgfw-server
```

---

## 📦 依赖

- `github.com/gin-gonic/gin` - 高性能 HTTP 框架

**为什么选择 Gin？**
- 🚀 高性能（比某些替代品快 40 倍）
- 📝 简洁优雅的 API
- ✅ 内置验证
- 🔧 中间件支持
- 📊 流行且维护良好

安装依赖：
```bash
go mod download
```

---

## ⚙️ 配置

所有配置通过命令行参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--port` | `8080` | 服务器端口 |
| `--domain` | (请求的 Host) | 服务器域名（推荐设置） |
| `--private-key` | `keys/private_key.pem` | 私钥路径 |

**重要：** 设置 `--domain` 参数以防止 Host 头欺骗攻击。

---

## 📋 URL 列表文件

### 创建 URL 列表

客户端将以 `#` 结尾的 URL 视为**列表文件**。创建列表文件：

**格式 1：带 `*GFW*` 标记（推荐用于云存储）**

```
*GFW*
https://server1.example.com/passgfw|https://server2.example.com/passgfw|https://server3.example.com/passgfw
*GFW*
```

即使嵌入在 HTML 中也能工作（如 Dropbox、Google Drive 预览页）。

**格式 2：逐行列表（简单文本文件）**

```
https://server1.example.com/passgfw
https://server2.example.com/passgfw
https://server3.example.com/passgfw
```

### 部署 URL 列表

**选项 1：云存储（推荐）**

1. 创建 `servers.txt` 包含你的 URL
2. 上传到 Dropbox、Google Drive、OneDrive 等
3. 获取公共分享链接
4. 添加到客户端配置（带 `#` 后缀）：
   ```swift
   "https://dropbox.com/s/abc123/servers.txt#"
   ```

**选项 2：静态文件服务器**

```bash
# 使用 nginx 服务
location /list.txt {
    root /var/www;
    add_header Access-Control-Allow-Origin *;
}
```

**选项 3：CDN**

上传到 CDN（Cloudflare、AWS CloudFront 等）实现全球分发。

### 优势

- ✅ **无需重新构建客户端** 即可添加/删除服务器
- ✅ **动态更新** - 随时更新文件
- ✅ **冗余** - 一个列表中有多个服务器
- ✅ **云存储** - 使用免费托管服务
- ✅ **HTML 安全** - 即使在预览页面也能工作

---

## 🔗 集成

服务器设计用于配合：
- **iOS/macOS Client**: Swift 实现
- **Android Client**: Kotlin 实现
- **HarmonyOS Client**: ArkTS 实现

所有客户端使用相同的验证协议。

---

**状态**: ✅ 生产就绪  
**版本**: 1.0.0  
**许可证**: MIT
