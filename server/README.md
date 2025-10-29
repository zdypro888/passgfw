# PassGFW Server

Simple Go server for PassGFW client verification.

## 🚀 Quick Start

### 1. Generate Keys (if not already done)

```bash
cd ../client
./generate_keys.sh
```

This creates:
- `client/keys/private_key.pem` - Used by server
- `client/keys/public_key.pem` - Embedded in client

### 2. Start Server

```bash
cd server
go run main.go
```

Server will start on `http://localhost:8080`

### 3. Custom Options

```bash
# Custom port
go run main.go -port 3000

# Custom key paths
go run main.go -private-key /path/to/private.pem -public-key /path/to/public.pem

# All options
go run main.go -port 3000 -private-key ./private.pem -public-key ./public.pem
```

## 📡 API Endpoints

### POST /passgfw

Main verification endpoint.

**Request:**
```json
{
  "data": "BASE64_ENCRYPTED_DATA"
}
```

**Response:**
```json
{
  "data": "DECRYPTED_DATA",
  "signature": "BASE64_SIGNATURE"
}
```

**Process:**
1. Client encrypts random data with public key
2. Server decrypts with private key
3. Server signs decrypted data with private key
4. Client verifies signature with public key

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "server": "PassGFW Server"
}
```

### GET /

HTML page with server info.

## 🔧 Build

### Development

```bash
# Run with default settings
go run main.go

# Run with debug mode (detailed logs)
go run main.go -debug
```

### Production Binary

```bash
# Build for current platform
go build -o passgfw-server

# Run
./passgfw-server -port 8080
```

### Cross-compile

```bash
# Linux
GOOS=linux GOARCH=amd64 go build -o passgfw-server-linux

# macOS
GOOS=darwin GOARCH=arm64 go build -o passgfw-server-macos

# Windows
GOOS=windows GOARCH=amd64 go build -o passgfw-server.exe
```

## 🔒 Security Notes

1. **Private Key**: NEVER expose or commit `private_key.pem`
2. **HTTPS**: Use HTTPS in production (reverse proxy recommended)
3. **Rate Limiting**: Add rate limiting for production use
4. **Firewall**: Restrict access to trusted IPs if possible

## 📝 Example: Deploy with Nginx

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
    }
}
```

## 🧪 Testing

### Using curl

```bash
# Generate test data (requires openssl and base64)
echo -n "test123" | openssl rsautl -encrypt -pubin -inkey ../client/keys/public_key.pem | base64

# Send request
curl -X POST http://localhost:8080/passgfw \
  -H "Content-Type: application/json" \
  -d '{"data":"BASE64_ENCRYPTED_DATA_HERE"}'
```

### Using the Client

Build and run the iOS/Android client, which will automatically test the server.

## 📊 Logs

The server logs all requests:

```
🚀 PassGFW Server Starting...
✅ Keys loaded successfully
🌐 Server listening on :8080

📥 Request from 127.0.0.1:51234
✅ Decrypted: AbCdEf123456...
📤 Response sent successfully
```

## 🐳 Docker (Optional)

```dockerfile
FROM golang:1.21-alpine

WORKDIR /app
COPY . .
RUN go build -o server

EXPOSE 8080
CMD ["./server"]
```

```bash
docker build -t passgfw-server .
docker run -p 8080:8080 -v ./keys:/app/keys passgfw-server
```

## 📦 Dependencies

- `github.com/gin-gonic/gin` - High-performance HTTP web framework

**Why Gin?**
- 🚀 Fast performance (40x faster than some alternatives)
- 📝 Simple and elegant API
- ✅ Built-in validation
- 🔧 Middleware support
- 📊 Popular and well-maintained

Install:
```bash
go mod download
```

## ⚙️ Configuration

All configuration via command-line flags:

| Flag | Default | Description |
|------|---------|-------------|
| `-port` | `8080` | Server port |
| `-private-key` | `../client/keys/private_key.pem` | Private key path |
| `-debug` | `false` | Enable debug mode (verbose logs) |

## 🔗 Integration

The server is designed to work with:
- **iOS Client**: PassGFW iOS framework
- **Android Client**: PassGFW Android library
- **HarmonyOS Client**: PassGFW HarmonyOS library

All clients use the same verification protocol.

---

## 📋 URL List Files

### Creating URL Lists

URLs ending with `#` are treated as **list files** by clients. Create a list file:

**Format 1: With `*GFW*` Markers (Recommended for cloud storage)**

```
*GFW*
https://server1.example.com/passgfw|https://server2.example.com/passgfw|https://server3.example.com/passgfw
*GFW*
```

This format works even when embedded in HTML (e.g., Dropbox, Google Drive preview pages).

**Format 2: Line-by-line (Simple text files)**

```
https://server1.example.com/passgfw
https://server2.example.com/passgfw
https://server3.example.com/passgfw
```

### Deploying URL Lists

**Option 1: Cloud Storage (Recommended)**

1. Create `servers.txt` with your URLs
2. Upload to Dropbox, Google Drive, OneDrive, etc.
3. Get public sharing link
4. Add to client config with `#` suffix:
   ```cpp
   "https://dropbox.com/s/abc123/servers.txt#"
   ```

**Option 2: Static File Server**

```bash
# Serve with nginx
location /list.txt {
    root /var/www;
    add_header Access-Control-Allow-Origin *;
}
```

**Option 3: CDN**

Upload to CDN (Cloudflare, AWS CloudFront, etc.) for global distribution.

### Example Files

See:
- `example_list.txt` - Detailed format examples
- `list_example_simple.txt` - Simple ready-to-use template

### Benefits

- ✅ **No client rebuild** needed to add/remove servers
- ✅ **Dynamic updates** - Update file anytime
- ✅ **Redundancy** - Multiple servers in one list
- ✅ **Cloud storage** - Use free hosting services
- ✅ **HTML-safe** - Works even in preview pages

---

**Status**: ✅ Production Ready  
**Version**: 1.0.2  
**License**: MIT

