package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

var (
	privateKey   *rsa.PrivateKey
	port         string
	serverDomain string // Real server domain (configured, not from client)
	adminUser    string // Admin username for /admin access
	adminPass    string // Admin password for /admin access
	adminLocal   bool   // Restrict admin access to localhost only
)

// Request structure
type PassGFWRequest struct {
	Data string `json:"data" binding:"required"` // Base64 encoded encrypted data
}

// URL Entry structure
type URLEntry struct {
	Method string `json:"method"`          // "api", "file", or "remove"
	URL    string `json:"url"`             // URL string
	Store  bool   `json:"store,omitempty"` // Optional: whether to persist locally (only valid for api and file)
}

// Response structure
// Signature is calculated on the JSON of this struct WITHOUT the signature field
// IMPORTANT: domain must not use omitempty to ensure consistent JSON structure for signature verification
type PassGFWResponse struct {
	Random    string     `json:"random"`         // Echoed nonce from client
	Domain    string     `json:"domain"`         // Server domain (for API response) - MUST be present
	URLs      []URLEntry `json:"urls,omitempty"` // URL list (for file response)
	Signature string     `json:"signature"`      // Base64 encoded RSA-SHA256 signature
}

// Error response structure
type ErrorResponse struct {
	Error string `json:"error"`
}

func main() {
	// Parse command line flags
	privateKeyPath := flag.String("private-key", "../client/keys/private_key.pem", "Path to private key")
	flag.StringVar(&port, "port", "8080", "Server port")
	flag.StringVar(&serverDomain, "domain", "", "Server domain (e.g., example.com:443)")
	flag.StringVar(&adminUser, "admin-user", "", "Admin username (leave empty to disable admin auth)")
	flag.StringVar(&adminPass, "admin-pass", "", "Admin password")
	flag.BoolVar(&adminLocal, "admin-local", false, "Restrict admin access to localhost only")
	debug := flag.Bool("debug", false, "Enable debug mode")
	flag.Parse()

	log.Println("🚀 PassGFW Server Starting...")
	log.Println("==============================")

	// Load private key
	if err := loadPrivateKey(*privateKeyPath); err != nil {
		log.Fatalf("❌ Failed to load private key: %v", err)
	}

	log.Printf("✅ Private key loaded: %s", *privateKeyPath)

	// Set Gin mode
	if !*debug {
		gin.SetMode(gin.ReleaseMode)
	}

	// Create Gin router
	router := gin.Default()

	// Setup routes
	router.POST("/passgfw", handlePassGFW)
	router.GET("/health", handleHealth)

	// Admin routes (protected)
	router.GET("/admin", adminAuth(), handleAdminPage)
	router.POST("/api/generate-list", adminAuth(), handleGenerateList)
	router.POST("/api/generate-keys", adminAuth(), handleGenerateKeys)

	// Start server
	addr := ":" + port
	log.Printf("")
	log.Printf("🌐 Server listening on %s", addr)
	log.Printf("   Endpoints:")
	log.Printf("   - POST http://localhost:%s/passgfw", port)
	log.Printf("   - GET  http://localhost:%s/health", port)
	log.Printf("   - GET  http://localhost:%s/admin (管理工具)", port)

	// Admin security info
	if adminUser != "" && adminPass != "" {
		log.Printf("")
		log.Printf("🔐 Admin authentication: ENABLED")
		log.Printf("   Username: %s", adminUser)
		log.Printf("   Password: %s", maskPassword(adminPass))
	} else {
		log.Printf("")
		log.Printf("⚠️  Admin authentication: DISABLED (use -admin-user and -admin-pass to enable)")
	}

	if adminLocal {
		log.Printf("🔒 Admin access: LOCALHOST ONLY")
	} else {
		log.Printf("⚠️  Admin access: ALL IPs (use -admin-local to restrict)")
	}

	log.Printf("")

	if err := router.Run(addr); err != nil {
		log.Fatalf("❌ Server error: %v", err)
	}
}

// adminAuth middleware for protecting admin endpoints
func adminAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Check localhost restriction
		if adminLocal {
			clientIP := c.ClientIP()
			if clientIP != "127.0.0.1" && clientIP != "::1" && clientIP != "localhost" {
				log.Printf("❌ Admin access denied: not from localhost (IP: %s)", clientIP)
				c.JSON(http.StatusForbidden, ErrorResponse{
					Error: "Admin access is restricted to localhost only",
				})
				c.Abort()
				return
			}
		}

		// Check HTTP Basic Auth
		if adminUser != "" && adminPass != "" {
			user, pass, hasAuth := c.Request.BasicAuth()

			if !hasAuth || user != adminUser || pass != adminPass {
				log.Printf("❌ Admin authentication failed: invalid credentials (IP: %s)", c.ClientIP())
				c.Header("WWW-Authenticate", `Basic realm="PassGFW Admin"`)
				c.JSON(http.StatusUnauthorized, ErrorResponse{
					Error: "Authentication required",
				})
				c.Abort()
				return
			}

			log.Printf("✅ Admin authenticated: %s (IP: %s)", user, c.ClientIP())
		}

		c.Next()
	}
}

// maskPassword masks password for logging
func maskPassword(password string) string {
	if len(password) <= 2 {
		return "***"
	}
	return password[:2] + "***"
}

// Load RSA private key from file
func loadPrivateKey(privateKeyPath string) error {
	privateKeyData, err := os.ReadFile(privateKeyPath)
	if err != nil {
		return fmt.Errorf("read private key: %w", err)
	}

	block, _ := pem.Decode(privateKeyData)
	if block == nil {
		return fmt.Errorf("failed to decode private key PEM")
	}

	// Try PKCS1 first
	privateKey, err = x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		// Try PKCS8 format
		key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return fmt.Errorf("parse private key (tried PKCS1 and PKCS8): %w", err)
		}
		var ok bool
		privateKey, ok = key.(*rsa.PrivateKey)
		if !ok {
			return fmt.Errorf("private key is not RSA")
		}
	}

	return nil
}

// Handle /passgfw endpoint
func handlePassGFW(c *gin.Context) {
	log.Printf("📥 Request from %s", c.ClientIP())

	// Parse JSON request
	var req PassGFWRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("❌ Invalid JSON: %v", err)
		c.JSON(http.StatusBadRequest, ErrorResponse{
			Error: "Invalid JSON or missing 'data' field",
		})
		return
	}

	// Decode Base64
	encryptedData, err := base64.StdEncoding.DecodeString(req.Data)
	if err != nil {
		log.Printf("❌ Invalid Base64: %v", err)
		c.JSON(http.StatusBadRequest, ErrorResponse{
			Error: "Invalid Base64 encoding",
		})
		return
	}

	// Decrypt with private key
	decryptedData, err := rsa.DecryptPKCS1v15(rand.Reader, privateKey, encryptedData)
	if err != nil {
		log.Printf("❌ Decryption failed: %v", err)
		c.JSON(http.StatusBadRequest, ErrorResponse{
			Error: "Decryption failed",
		})
		return
	}

	decryptedStr := string(decryptedData)
	log.Printf("✅ Decrypted JSON: %s", decryptedStr)

	// Parse decrypted JSON payload
	var payload struct {
		Nonce      string `json:"nonce"`
		ClientData string `json:"client_data"`
	}

	if err := json.Unmarshal(decryptedData, &payload); err != nil {
		log.Printf("❌ Failed to parse payload JSON: %v", err)
		c.JSON(http.StatusBadRequest, ErrorResponse{
			Error: "Invalid payload format",
		})
		return
	}

	log.Printf("   Random: %s", payload.Nonce)
	if payload.ClientData != "" {
		log.Printf("   Client data: %s", payload.ClientData)
	}

	// Determine real server domain based on client data
	// Use configured domain or fallback to request host
	configuredDomain := serverDomain
	if configuredDomain == "" {
		configuredDomain = c.Request.Host
		log.Printf("   ⚠️  Using request Host (consider setting --domain flag)")
	}
	realDomain := getRealDomain(configuredDomain, payload.ClientData)
	log.Printf("   Server domain: %s", realDomain)

	// Construct response object (without signature first)
	response := PassGFWResponse{
		Random: payload.Nonce,
		Domain: realDomain,
	}

	// CRITICAL: Validate that domain is not empty (otherwise omitempty causes mismatch)
	if realDomain == "" {
		log.Printf("❌ Domain cannot be empty")
		c.JSON(http.StatusInternalServerError, ErrorResponse{
			Error: "Server configuration error: domain not set",
		})
		return
	}

	// CRITICAL: Create ordered map for consistent JSON serialization across platforms
	// All platforms must use alphabetically sorted keys for signature verification
	// Note: Go's map iteration order is random, but json.Marshal always outputs in sorted key order
	payloadMap := map[string]interface{}{
		"domain": realDomain,
		"random": payload.Nonce,
	}

	// Marshal response (Go json.Marshal automatically sorts keys alphabetically)
	responseJSON, err := json.Marshal(payloadMap)
	if err != nil {
		log.Printf("❌ Failed to marshal response JSON: %v", err)
		c.JSON(http.StatusInternalServerError, ErrorResponse{
			Error: "Failed to create response",
		})
		return
	}

	log.Printf("   Payload for signing: %s", string(responseJSON))

	// Sign the response JSON
	hashed := sha256.Sum256(responseJSON)
	signature, err := rsa.SignPKCS1v15(rand.Reader, privateKey, crypto.SHA256, hashed[:])
	if err != nil {
		log.Printf("❌ Signing failed: %v", err)
		c.JSON(http.StatusInternalServerError, ErrorResponse{
			Error: "Signing failed",
		})
		return
	}

	signatureBase64 := base64.StdEncoding.EncodeToString(signature)

	// Add signature to response
	response.Signature = signatureBase64

	c.JSON(http.StatusOK, response)
	log.Printf("✅ Response sent with signature")
}

// Get real server domain based on configured domain and client data
// You can customize this logic to route to different backends
func getRealDomain(configuredDomain, clientData string) string {
	// Route based on client data
	// You can add custom logic here based on clientData
	// For example:
	// - Route to different CDN based on clientData
	// - Return different domains for different clients
	// - Implement load balancing logic

	if clientData == "cdn" {
		return "cdn.example.com:443"
	}

	if clientData == "mobile" {
		return "mobile.example.com:443"
	}

	// Default: return configured domain
	return configuredDomain
}

// Handle /health endpoint
func handleHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"server":  "PassGFW Server",
		"version": "1.0.1",
	})
}

// Handle /admin - Admin management page
func handleAdminPage(c *gin.Context) {
	c.Header("Content-Type", "text/html; charset=utf-8")
	c.String(http.StatusOK, getAdminHTML())
}

// Handle /api/generate-list - Generate *PGFW* format URL list
func handleGenerateList(c *gin.Context) {
	var req struct {
		URLs []URLEntry `json:"urls" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Invalid request: " + err.Error()})
		return
	}

	// Convert to JSON
	jsonData, err := json.Marshal(req.URLs)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Failed to marshal JSON: " + err.Error()})
		return
	}

	// Base64 encode
	b64 := base64.StdEncoding.EncodeToString(jsonData)

	// Add markers
	pgfwFormat := fmt.Sprintf("*PGFW*%s*PGFW*", b64)

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"json":        string(jsonData),
		"base64":      b64,
		"pgfw_format": pgfwFormat,
	})
}

// Handle /api/generate-keys - Generate RSA key pair
func handleGenerateKeys(c *gin.Context) {
	var req struct {
		KeySize int `json:"key_size"`
	}

	if err := c.ShouldBindJSON(&req); err != nil || req.KeySize == 0 {
		req.KeySize = 2048 // Default
	}

	// Validate key size
	if req.KeySize < 1024 || req.KeySize > 8192 {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Key size must be between 1024 and 8192"})
		return
	}

	log.Printf("🔑 Generating RSA key pair (size: %d bits)...", req.KeySize)

	// Generate private key
	privKey, err := rsa.GenerateKey(rand.Reader, req.KeySize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Failed to generate key: " + err.Error()})
		return
	}

	// Encode private key to PEM
	privKeyBytes := x509.MarshalPKCS1PrivateKey(privKey)
	privKeyPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: privKeyBytes,
	})

	// Encode public key to PEM
	pubKeyBytes, err := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Failed to marshal public key: " + err.Error()})
		return
	}

	pubKeyPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "PUBLIC KEY",
		Bytes: pubKeyBytes,
	})

	log.Printf("✅ RSA key pair generated successfully")

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"private_key": string(privKeyPEM),
		"public_key":  string(pubKeyPEM),
		"key_size":    req.KeySize,
	})
}

// Get admin HTML page
func getAdminHTML() string {
	return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PassGFW 管理工具</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        h1 {
            color: white;
            text-align: center;
            margin-bottom: 30px;
            font-size: 2.5rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
        }
        
        .cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
            gap: 20px;
        }
        
        .card {
            background: white;
            border-radius: 12px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        
        .card h2 {
            color: #667eea;
            margin-bottom: 20px;
            font-size: 1.5rem;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        
        .form-group {
            margin-bottom: 15px;
        }
        
        label {
            display: block;
            margin-bottom: 5px;
            color: #333;
            font-weight: 500;
        }
        
        input, textarea, select {
            width: 100%;
            padding: 10px;
            border: 2px solid #e0e0e0;
            border-radius: 6px;
            font-size: 14px;
            transition: border-color 0.3s;
        }
        
        input:focus, textarea:focus, select:focus {
            outline: none;
            border-color: #667eea;
        }
        
        textarea {
            resize: vertical;
            font-family: 'Monaco', 'Menlo', 'Courier New', monospace;
        }
        
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 16px;
            font-weight: 500;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
        }
        
        button:active {
            transform: translateY(0);
        }
        
        .url-entry {
            display: flex;
            gap: 10px;
            margin-bottom: 10px;
            align-items: flex-start;
        }
        
        .url-entry select {
            flex: 0 0 100px;
        }
        
        .url-entry input {
            flex: 1;
        }
        
        .url-entry button {
            flex: 0 0 auto;
            padding: 10px 15px;
            background: #f44336;
        }
        
        .add-btn {
            background: #4caf50;
            margin-bottom: 15px;
        }
        
        .result {
            margin-top: 20px;
            padding: 15px;
            background: #f5f5f5;
            border-radius: 6px;
            display: none;
        }
        
        .result.show {
            display: block;
        }
        
        .result pre {
            background: #2d2d2d;
            color: #f8f8f2;
            padding: 15px;
            border-radius: 6px;
            overflow-x: auto;
            font-size: 13px;
            line-height: 1.5;
        }
        
        .copy-btn {
            background: #2196f3;
            margin-top: 10px;
        }
        
        .success {
            color: #4caf50;
            font-weight: bold;
        }
        
        .error {
            color: #f44336;
            font-weight: bold;
        }
        
        .info {
            background: #e3f2fd;
            padding: 15px;
            border-radius: 6px;
            margin-bottom: 20px;
            border-left: 4px solid #2196f3;
        }
        
        .key-size-group {
            display: flex;
            gap: 10px;
            align-items: center;
        }
        
        .key-size-group select {
            flex: 1;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔐 PassGFW 管理工具</h1>
        
        <div class="cards">
            <!-- URL 列表生成器 -->
            <div class="card">
                <h2>📋 URL 列表生成器</h2>
                <div class="info">
                    生成 <code>*PGFW*base64*PGFW*</code> 格式的URL列表，可嵌入到HTML、文本等任何地方。
                </div>
                
                <div id="url-entries">
                    <div class="url-entry">
                        <select class="method-select">
                            <option value="api">API</option>
                            <option value="file">File</option>
                            <option value="remove">Remove (删除)</option>
                        </select>
                        <input type="text" class="url-input" placeholder="https://example.com/passgfw" value="https://server1.example.com/passgfw">
                        <label style="display: flex; align-items: center; gap: 5px; white-space: nowrap;">
                            <input type="checkbox" class="store-checkbox">
                            <span>持久化</span>
                        </label>
                        <button onclick="removeURLEntry(this)">删除</button>
                    </div>
                </div>
                
                <button class="add-btn" onclick="addURLEntry()">➕ 添加URL</button>
                <button onclick="generateList()">🚀 生成列表</button>
                
                <div id="list-result" class="result">
                    <h3>生成结果：</h3>
                    <h4>*PGFW* 格式（可直接嵌入）：</h4>
                    <pre id="pgfw-output"></pre>
                    <button class="copy-btn" onclick="copyToClipboard('pgfw-output')">📋 复制</button>
                    
                    <h4 style="margin-top: 20px;">原始 JSON：</h4>
                    <pre id="json-output"></pre>
                    <button class="copy-btn" onclick="copyToClipboard('json-output')">📋 复制</button>
                </div>
            </div>
            
            <!-- RSA 密钥生成器 -->
            <div class="card">
                <h2>🔑 RSA 密钥生成器</h2>
                <div class="info">
                    生成新的 RSA 密钥对用于服务器签名和客户端验证。
                </div>
                
                <div class="form-group">
                    <label>密钥长度：</label>
                    <div class="key-size-group">
                        <select id="key-size">
                            <option value="2048" selected>2048 位（推荐）</option>
                            <option value="3072">3072 位（更安全）</option>
                            <option value="4096">4096 位（最安全）</option>
                        </select>
                    </div>
                </div>
                
                <button onclick="generateKeys()">🔐 生成密钥对</button>
                
                <div id="keys-result" class="result">
                    <h3>生成成功！</h3>
                    
                    <h4>私钥（Private Key）- 服务器使用：</h4>
                    <pre id="private-key-output"></pre>
                    <button class="copy-btn" onclick="copyToClipboard('private-key-output')">📋 复制私钥</button>
                    <button class="copy-btn" onclick="downloadKey('private-key-output', 'private_key.pem')">💾 下载私钥</button>
                    
                    <h4 style="margin-top: 20px;">公钥（Public Key）- 客户端使用：</h4>
                    <pre id="public-key-output"></pre>
                    <button class="copy-btn" onclick="copyToClipboard('public-key-output')">📋 复制公钥</button>
                    <button class="copy-btn" onclick="downloadKey('public-key-output', 'public_key.pem')">💾 下载公钥</button>
                    
                    <div style="margin-top: 15px; padding: 10px; background: #fff3cd; border-radius: 6px; border-left: 4px solid #ffc107;">
                        <strong>⚠️ 注意：</strong>请妥善保管私钥，不要泄露！公钥可以公开分发给客户端。
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        function addURLEntry() {
            const container = document.getElementById('url-entries');
            const entry = document.createElement('div');
            entry.className = 'url-entry';
            entry.innerHTML = ` + "`" + `
                <select class="method-select">
                    <option value="api">API</option>
                    <option value="file">File</option>
                    <option value="remove">Remove (删除)</option>
                </select>
                <input type="text" class="url-input" placeholder="https://example.com/passgfw">
                <label style="display: flex; align-items: center; gap: 5px; white-space: nowrap;">
                    <input type="checkbox" class="store-checkbox">
                    <span>持久化</span>
                </label>
                <button onclick="removeURLEntry(this)">删除</button>
            ` + "`" + `;
            container.appendChild(entry);
        }

        function removeURLEntry(btn) {
            const entries = document.querySelectorAll('.url-entry');
            if (entries.length > 1) {
                btn.parentElement.remove();
            } else {
                alert('至少需要保留一个URL！');
            }
        }

        async function generateList() {
            const entries = document.querySelectorAll('.url-entry');
            const urls = [];

            entries.forEach(entry => {
                const method = entry.querySelector('.method-select').value;
                const url = entry.querySelector('.url-input').value.trim();
                const storeChecked = entry.querySelector('.store-checkbox').checked;

                if (url) {
                    const urlEntry = { method, url };
                    // 只有当 store 被勾选且 method 不是 remove 时才添加 store 字段
                    if (storeChecked && method !== 'remove') {
                        urlEntry.store = true;
                    }
                    urls.push(urlEntry);
                }
            });

            if (urls.length === 0) {
                alert('请至少添加一个URL！');
                return;
            }

            try {
                const response = await fetch('/api/generate-list', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ urls })
                });

                const data = await response.json();
                
                if (data.success) {
                    document.getElementById('pgfw-output').textContent = data.pgfw_format;
                    document.getElementById('json-output').textContent = JSON.stringify(JSON.parse(data.json), null, 2);
                    document.getElementById('list-result').classList.add('show');
                } else {
                    alert('生成失败：' + (data.error || '未知错误'));
                }
            } catch (error) {
                alert('请求失败：' + error.message);
            }
        }

        async function generateKeys() {
            const keySize = parseInt(document.getElementById('key-size').value);
            
            if (!confirm(` + "`生成 ${keySize} 位密钥对？这可能需要几秒钟...`" + `)) {
                return;
            }

            try {
                const response = await fetch('/api/generate-keys', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ key_size: keySize })
                });

                const data = await response.json();
                
                if (data.success) {
                    document.getElementById('private-key-output').textContent = data.private_key;
                    document.getElementById('public-key-output').textContent = data.public_key;
                    document.getElementById('keys-result').classList.add('show');
                } else {
                    alert('生成失败：' + (data.error || '未知错误'));
                }
            } catch (error) {
                alert('请求失败：' + error.message);
            }
        }

        function copyToClipboard(elementId) {
            const element = document.getElementById(elementId);
            const text = element.textContent;
            
            navigator.clipboard.writeText(text).then(() => {
                alert('✅ 已复制到剪贴板！');
            }).catch(err => {
                alert('复制失败：' + err.message);
            });
        }

        function downloadKey(elementId, filename) {
            const element = document.getElementById(elementId);
            const text = element.textContent;
            const blob = new Blob([text], { type: 'text/plain' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            a.click();
            URL.revokeObjectURL(url);
        }
    </script>
</body>
</html>`
}
