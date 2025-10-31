# PassGFW URL List Format Examples

PassGFW 支持多种 URL 列表格式，可以灵活嵌入到各种环境中。

## 格式类型

### 1. *PGFW* 编码格式（推荐）⭐

这是最灵活的格式，可以嵌入到任何地方（HTML注释、文本文件、图片EXIF等）。

#### 格式定义

```
*PGFW*base64编码的URLEntry[]的JSON*PGFW*
```

#### 示例

**原始 JSON 数组：**
```json
[
  {"method":"api","url":"https://server1.example.com/passgfw"},
  {"method":"api","url":"https://server2.example.com/passgfw"},
  {"method":"file","url":"https://cdn.example.com/backup-list.txt"}
]
```

**Base64 编码后：**
```
*PGFW*W3sibWV0aG9kIjoiYXBpIiwidXJsIjoiaHR0cHM6Ly9zZXJ2ZXIxLmV4YW1wbGUuY29tL3Bhc3NnZncifSx7Im1ldGhvZCI6ImFwaSIsInVybCI6Imh0dHBzOi8vc2VydmVyMi5leGFtcGxlLmNvbS9wYXNzZ2Z3In0seyJtZXRob2QiOiJmaWxlIiwidXJsIjoiaHR0cHM6Ly9jZG4uZXhhbXBsZS5jb20vYmFja3VwLWxpc3QudHh0In1d*PGFW*
```

#### 嵌入示例

**嵌入到 HTML 注释：**
```html
<!DOCTYPE html>
<html>
<head>
    <title>Example Page</title>
    <!-- 
    *PGFW*W3sibWV0aG9kIjoiYXBpIiwidXJsIjoiaHR0cHM6Ly9zZXJ2ZXIxLmV4YW1wbGUuY29tL3Bhc3NnZncifV0=*PGFW*
    -->
</head>
<body>
    <h1>Regular content</h1>
</body>
</html>
```

**嵌入到普通文本文件：**
```
This is a regular text file.
Some random content here.

*PGFW*W3sibWV0aG9kIjoiYXBpIiwidXJsIjoiaHR0cHM6Ly9zZXJ2ZXIxLmV4YW1wbGUuY29tL3Bhc3NnZncifV0=*PGFW*

More regular content below.
Nothing suspicious here.
```

**嵌入到 CSS 注释：**
```css
/* Some styles */
body {
    margin: 0;
    padding: 0;
}

/*
*PGFW*W3sibWV0aG9kIjoiYXBpIiwidXJsIjoiaHR0cHM6Ly9zZXJ2ZXIxLmV4YW1wbGUuY29tL3Bhc3NnZncifV0=*PGFW*
*/
```

---

### 2. 直接 JSON 数组格式

直接提供 URLEntry 数组的 JSON。

```json
[
  {"method":"api","url":"https://server1.example.com/passgfw"},
  {"method":"api","url":"https://server2.example.com/passgfw"},
  {"method":"file","url":"https://cdn.example.com/list.txt"}
]
```

---

### 3. Legacy 包装格式

旧版格式，包装在 `urls` 字段中（向后兼容）。

```json
{
  "urls": [
    {"method":"api","url":"https://server1.example.com/passgfw"},
    {"method":"api","url":"https://server2.example.com/passgfw"}
  ]
}
```

---

### 4. 纯文本格式（已弃用）

仅作为最后的降级选项，不推荐使用。

```
https://server1.example.com/passgfw
https://server2.example.com/passgfw
http://server3.example.com:8080/passgfw
```

---

## URLEntry 结构

每个 URL 条目包含两个字段：

```typescript
interface URLEntry {
  method: "api" | "file";  // 方法类型
  url: string;             // URL 地址
}
```

### Method 类型

- **`api`**: API 接口，返回签名的服务器域名
  - 客户端发送加密的 nonce
  - 服务器返回签名的响应：`{random, domain, signature}`
  - 需要 RSA 签名验证

- **`file`**: 静态文件，包含更多 URL 列表
  - 可以包含任何上述格式的列表
  - 支持递归（有深度限制）
  - 不需要签名

---

## 如何生成 *PGFW* 格式

### Python 示例

```python
import json
import base64

# 准备 URL 列表
urls = [
    {"method": "api", "url": "https://server1.example.com/passgfw"},
    {"method": "api", "url": "https://server2.example.com/passgfw"},
    {"method": "file", "url": "https://cdn.example.com/backup.txt"}
]

# 转换为 JSON
json_str = json.dumps(urls, separators=(',', ':'), ensure_ascii=False)

# Base64 编码
b64_str = base64.b64encode(json_str.encode('utf-8')).decode('utf-8')

# 添加标记
result = f"*PGFW*{b64_str}*PGFW*"

print(result)
```

### Shell 示例

```bash
#!/bin/bash

# 准备 JSON
JSON='[{"method":"api","url":"https://server1.example.com/passgfw"}]'

# Base64 编码
BASE64=$(echo -n "$JSON" | base64)

# 添加标记
echo "*PGFW*${BASE64}*PGFW*"
```

### JavaScript/Node.js 示例

```javascript
const urls = [
  {method: "api", url: "https://server1.example.com/passgfw"},
  {method: "api", url: "https://server2.example.com/passgfw"}
];

const json = JSON.stringify(urls);
const b64 = Buffer.from(json).toString('base64');
const result = `*PGFW*${b64}*PGFW*`;

console.log(result);
```

---

## 解析顺序

PassGFW 客户端按以下顺序尝试解析：

1. **查找 `*PGFW*` 标记**
   - 提取标记之间的内容
   - Base64 解码
   - 解析为 URLEntry[]

2. **尝试直接解析为 URLEntry[]**
   - 直接 JSON 数组

3. **尝试 Legacy 格式**
   - 包装在 `{"urls": [...]}` 中

4. **降级到纯文本**
   - 逐行解析 URL（假定为 api method）

---

## 最佳实践

1. **优先使用 *PGFW* 格式**
   - 最灵活，可嵌入任何地方
   - 不易被识别和过滤
   - 支持所有功能

2. **使用 HTTPS**
   - 所有 URL 应使用 HTTPS
   - 提供传输层加密

3. **设置合理的递归深度**
   - 默认最大递归深度：5
   - 避免无限循环

4. **提供多个备份**
   - API 服务器至少 2-3 个
   - File URL 至少 1-2 个
   - 混合使用不同域名和 CDN

5. **定期更新列表**
   - 使用 file method 提供动态列表
   - 允许在不更新客户端的情况下添加新服务器

---

## 安全注意事项

- **API 方法**: 始终验证 RSA 签名，防止中间人攻击
- **File 方法**: 不提供签名验证，建议仅从可信来源获取
- **Base64 编码**: 不是加密，仅用于编码，不要存放敏感信息
- **递归限制**: 防止无限循环和资源耗尽攻击

---

## 常见问题

### Q: 为什么不直接使用 JSON？
A: JSON 格式在某些环境下可能被识别和过滤。*PGFW* 格式可以伪装成普通的 Base64 数据，嵌入到各种文件中。

### Q: Base64 编码的性能开销大吗？
A: 极小。Base64 编解码非常快，列表文件通常很小（< 1KB），几乎没有性能影响。

### Q: 可以嵌入到图片中吗？
A: 理论上可以（如 EXIF 元数据），但需要额外的工具来读取和写入。建议使用简单的文本嵌入方式。

### Q: *PGFW* 标记可以自定义吗？
A: 当前版本不支持。如需自定义，可以修改客户端源代码中的 `startMarker` 和 `endMarker` 常量。

