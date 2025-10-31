# PassGFW Server

防火墙检测服务器，用于安全地分发可用服务器域名。

## 🚀 快速开始

### 基本启动

```bash
./passgfw-server \
  -private-key=./keys/private_key.pem \
  -domain=example.com:443 \
  -port=8080
```

### 安全启动（推荐）

```bash
./passgfw-server \
  -private-key=./keys/private_key.pem \
  -domain=example.com:443 \
  -port=8080 \
  -admin-user=admin \
  -admin-pass=your-strong-password \
  -admin-local
```

## 📋 命令行参数

### 必需参数

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `-private-key` | 私钥文件路径 | `../client/keys/private_key.pem` | `-private-key=./keys/private_key.pem` |
| `-domain` | 服务器域名 | 无 | `-domain=example.com:443` |

### 可选参数

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `-port` | 服务器端口 | `8080` | `-port=8080` |
| `-debug` | 调试模式 | `false` | `-debug` |

### 安全参数 🔐

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `-admin-user` | 管理员用户名 | 空（禁用认证） | `-admin-user=admin` |
| `-admin-pass` | 管理员密码 | 空 | `-admin-pass=secretpass` |
| `-admin-local` | 限制仅本地访问管理页面 | `false` | `-admin-local` |

## 🔒 安全配置

### 方案1: HTTP Basic Auth（推荐用于生产环境）

启用用户名和密码认证：

```bash
./passgfw-server \
  -private-key=./keys/private_key.pem \
  -domain=example.com:443 \
  -admin-user=admin \
  -admin-pass=strong-password-here
```

访问管理页面时会弹出登录框。

**优点:**
- ✅ 防止未授权访问
- ✅ 可以从远程管理
- ✅ 标准的 HTTP 认证机制

**缺点:**
- ⚠️ 需要 HTTPS 才安全（否则密码明文传输）
- ⚠️ 需要管理密码

### 方案2: 限制本地访问（推荐用于开发环境）

仅允许从 localhost 访问管理页面：

```bash
./passgfw-server \
  -private-key=./keys/private_key.pem \
  -domain=example.com:443 \
  -admin-local
```

只有 `127.0.0.1`, `::1`, `localhost` 可以访问 `/admin`。

**优点:**
- ✅ 简单，无需密码
- ✅ 完全隔离外部访问
- ✅ 适合开发和本地管理

**缺点:**
- ⚠️ 无法远程管理
- ⚠️ 需要 SSH 或本地访问服务器

### 方案3: 双重保护（最安全，推荐用于生产环境）

同时启用用户名密码和本地限制：

```bash
./passgfw-server \
  -private-key=./keys/private_key.pem \
  -domain=example.com:443 \
  -admin-user=admin \
  -admin-pass=strong-password-here \
  -admin-local
```

**优点:**
- ✅ 双重认证
- ✅ 即使在本地网络也需要密码
- ✅ 最高安全级别

### 方案4: 无认证（仅用于测试，不推荐）

```bash
./passgfw-server \
  -private-key=./keys/private_key.pem \
  -domain=example.com:443
```

**⚠️ 警告:** 管理页面完全公开，任何人都可以访问！

**仅适用于:**
- 本地测试
- 内网环境
- 临时使用

## 🌐 API 端点

### 公开端点

| 端点 | 方法 | 说明 | 认证 |
|------|------|------|------|
| `/passgfw` | POST | 防火墙检测接口 | ❌ 无需认证 |
| `/health` | GET | 健康检查 | ❌ 无需认证 |

### 管理端点（受保护）

| 端点 | 方法 | 说明 | 认证 |
|------|------|------|------|
| `/admin` | GET | 管理工具页面 | ✅ 需要认证 |
| `/api/generate-list` | POST | 生成 URL 列表 | ✅ 需要认证 |
| `/api/generate-keys` | POST | 生成 RSA 密钥对 | ✅ 需要认证 |

## 🛡️ 安全最佳实践

### 1. 生产环境

```bash
# 1. 使用强密码
./passgfw-server \
  -private-key=./keys/private_key.pem \
  -domain=example.com:443 \
  -admin-user=admin \
  -admin-pass=$(openssl rand -base64 32) \
  -admin-local

# 2. 使用 systemd 服务
# 3. 配合 Nginx/Apache 反向代理 + HTTPS
# 4. 配置防火墙规则
# 5. 定期更换密码
# 6. 监控访问日志
```

### 2. 开发环境

```bash
# 简单的本地限制即可
./passgfw-server \
  -private-key=./keys/private_key.pem \
  -domain=localhost:8080 \
  -admin-local \
  -debug
```

### 3. 使用 HTTPS 反向代理

建议在生产环境使用 Nginx + Let's Encrypt：

```nginx
server {
    listen 443 ssl http2;
    server_name admin.example.com;
    
    ssl_certificate /etc/letsencrypt/live/admin.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.example.com/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

这样即使使用 HTTP Basic Auth，密码也会通过 HTTPS 加密传输。

### 4. 使用环境变量

不要在命令行直接暴露密码：

```bash
# 设置环境变量
export ADMIN_USER="admin"
export ADMIN_PASS="your-secret-password"

# 从环境变量读取（需要修改代码支持）
# 或者使用配置文件
```

### 5. IP 白名单（防火墙层面）

```bash
# 使用 iptables 限制访问
iptables -A INPUT -p tcp --dport 8080 -s 192.168.1.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 8080 -j DROP
```

## 📊 启动日志示例

### 启用认证

```
🚀 PassGFW Server Starting...
==============================
✅ Private key loaded: ./keys/private_key.pem
🌐 Server listening on :8080
   Endpoints:
   - POST http://localhost:8080/passgfw
   - GET  http://localhost:8080/health
   - GET  http://localhost:8080/admin (管理工具)

🔐 Admin authentication: ENABLED
   Username: admin
   Password: st***
🔒 Admin access: LOCALHOST ONLY
```

### 未启用认证（警告）

```
🚀 PassGFW Server Starting...
==============================
✅ Private key loaded: ./keys/private_key.pem
🌐 Server listening on :8080
   Endpoints:
   - POST http://localhost:8080/passgfw
   - GET  http://localhost:8080/health
   - GET  http://localhost:8080/admin (管理工具)

⚠️  Admin authentication: DISABLED (use -admin-user and -admin-pass to enable)
⚠️  Admin access: ALL IPs (use -admin-local to restrict)
```

## 🔍 访问日志

启用认证后，每次访问管理页面都会记录：

```
✅ Admin authenticated: admin (IP: 127.0.0.1)
❌ Admin authentication failed: invalid credentials (IP: 192.168.1.100)
❌ Admin access denied: not from localhost (IP: 8.8.8.8)
```

## 🆘 常见问题

### Q: 忘记管理员密码怎么办？

A: 重启服务器时使用新密码即可：

```bash
./passgfw-server -admin-user=admin -admin-pass=new-password
```

### Q: 如何在生产环境使用？

A: 推荐配置：

1. 使用 systemd 服务
2. 启用 `-admin-user` 和 `-admin-pass`
3. 启用 `-admin-local`
4. 使用 SSH 隧道访问管理页面
5. 或者配置 Nginx HTTPS 反向代理

### Q: 如何通过 SSH 隧道访问？

A: 服务器启用 `-admin-local` 后：

```bash
# 本地执行
ssh -L 8080:localhost:8080 user@server-ip

# 然后访问本地
http://localhost:8080/admin
```

### Q: 密码会被记录到日志吗？

A: 不会。密码只会显示前2个字符 + `***`，例如 `st***`。

### Q: 可以使用配置文件吗？

A: 当前版本使用命令行参数。可以创建一个启动脚本：

```bash
#!/bin/bash
./passgfw-server \
  -private-key=./keys/private_key.pem \
  -domain=example.com:443 \
  -port=8080 \
  -admin-user=admin \
  -admin-pass="$ADMIN_PASSWORD" \
  -admin-local
```

## 📝 示例：Systemd 服务

创建 `/etc/systemd/system/passgfw.service`:

```ini
[Unit]
Description=PassGFW Server
After=network.target

[Service]
Type=simple
User=passgfw
WorkingDirectory=/opt/passgfw
Environment="ADMIN_PASS=your-secret-password"
ExecStart=/opt/passgfw/passgfw-server \
  -private-key=/opt/passgfw/keys/private_key.pem \
  -domain=example.com:443 \
  -port=8080 \
  -admin-user=admin \
  -admin-pass=${ADMIN_PASS} \
  -admin-local
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

启动服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable passgfw
sudo systemctl start passgfw
sudo systemctl status passgfw
```

## 🔐 安全检查清单

部署前请确认：

- [ ] 已启用 `-admin-user` 和 `-admin-pass`
- [ ] 密码足够强（至少16字符，包含大小写字母、数字、符号）
- [ ] 启用了 `-admin-local` 或配置了防火墙规则
- [ ] 使用 HTTPS 反向代理（如果需要远程访问）
- [ ] 私钥文件权限正确（600 或 400）
- [ ] 服务以非 root 用户运行
- [ ] 配置了访问日志监控
- [ ] 定期备份私钥和配置
