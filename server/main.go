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

// Built-in private key (matches keys/public_key.pem)
// This allows the server to run without external key files
const builtinPrivateKey = `-----BEGIN PRIVATE KEY-----
MIIEuwIBADANBgkqhkiG9w0BAQEFAASCBKUwggShAgEAAoIBAQDLBduwdo/D0VYV
BdXKzhrEAHB4RPqGJvPMC6n7zgNpx/eZR8YVi7oIFO5ieL/Hiv5Z6KySItAlKbUG
TzS5aec5dw1EDv8uvGFc73UD67BGAHI7c+2RI4Ob0wAWFIIP4dQx2Utp6iRB8r4F
IvE8H0o3ORTseZ0BWYuSqTIvHNcyDoFIr10WhpiFr/PPZmm6MK0ZuTYU5JgFr7rM
sUKdh6tRGviVH/0oBczQmNtz/pB0CgZwJKkUMxYkQUDA88EBii3xeeq55Ndh/0FE
kdU8+P9/14aY83p50V2fB1l6/RrsqXGGA8gfZ0GeD2s+sbXS9xux/TDX7QlgjneN
AHy+CUavAgMBAAECgf8HVJXl+ewgS0TD9aBrT6IbT6BBGx8Je8/XW0CillIzI9JB
fxDWVysCXyCE2CsbULQ2teQWPDAV7smZWzLqKxu0+tyOfDcJ0nHjW43syUnf9vJR
uOOBisWYSJ79RgaFGwKYk82MWmorGWWuo0hz9EUOsFOg7/dI4jfpmoYo4o8CSdAc
r99wGo1p/o6b6NXV2NFKqfpCgqCHtMrs/s1Nws1PVa//NNbg9AXcAVF7tEaGdmGa
FvEzz87TH146jcMsesqUtABX2xQsAvHGh5ENup+XYfivwX1xLd/KGe8m85ixzQTd
BGDZcnNMUgbpjmz+iAZItQrN00YmMAqPvGdUuD0CgYEA/gqcalYGiv4BsYcbxefs
qv8YsCmO4wT3L6b3L5Arx33EVGA+O7LdyYmdQhNG7d12nNYC7UwG9h+fT0SX7WO9
nFzf4sGqkKrm2ebvd02yoVP127LChiOXsReyY8PKunNsg8Dt5WASm42Cqf6AXO2w
MsTK225PfLJ2vnSr4NXK4G0CgYEAzJaN6gXmKF2zOcgs7sdWE9Vo59yZLVQirN5k
2OSGLlUgyw+AsvfGnflemPbzA0ubBsNg+LA6TOPg3NnSFb2TNB3igfgErZ9k1iom
T3+ohs7x0igzLCDjV502Ikm9sH6nwgHZZQkJrjl0rVMVuWicDI3umVxftVZuHS2y
V+Em6gsCgYAJH/RyVViy0WDaMZIrz6LOmY8XdMavHNSMH6EtUi5gYgIVTceueURC
IvFFGFAp5xSFmaJNR7fQS157iGk0m6qJ3UQlbvNjcuAL36GmVWIfLVbdZ1RZYRnn
wIQl1TiI7fBt4xYocQT6FWEmHgAaVmdHy43Fx/aO8hIV0TcDQmqhGQKBgQCJg80B
91Mb4Nd+SEnDeeMm07R+3O1s5XelQJsCmqCCdh/jvZjhMuCjAKIQKTVxCpm6cws0
PagCVM2pRRQMHu/aARhmCeKDHXd26L/1gbYyXtl2TCURTU3ibz6az3wcLRXvtrR8
UBXcsKv3cLhSdrklSyWMmeWPCvhazoNoxGMWvwKBgCv8ypGup/vzNk3A3l6U1yVo
5WMnSP21mVpLsZRzJTHfzxTtZ2HyP3vPj0i6EluusL2vZUqNjJRMMqAamoqjS+Tg
Pdvt4pzoPrjvoOYAL+fF29wJ1N0WsZ8nrIEbszTXn05JhEPRO0kZVLhol8e1IhTA
zXXmspEHqYCidbvAoL3Z
-----END PRIVATE KEY-----`

type URLEntry struct {
	Method string `json:"method"`
	URL    string `json:"url"`
	Store  bool   `json:"store,omitempty"`
}

type ClientPayload struct {
	Nonce string `json:"nonce"`
	OS    string `json:"os"`
	App   string `json:"app"`
	Data  string `json:"data"`
}

type PassGFWResponse struct {
	Nonce     []byte     `json:"nonce"`
	Data      []byte     `json:"data"`
	URLs      []URLEntry `json:"urls,omitempty"`
	Signature []byte     `json:"signature"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

func main() {
	privateKeyPath := flag.String("private-key", "", "Path to private key")
	flag.StringVar(&port, "port", "8080", "Server port")
	flag.StringVar(&serverDomain, "domain", "", "Server domain")
	flag.StringVar(&adminUser, "admin-user", "", "Admin username")
	flag.StringVar(&adminPass, "admin-pass", "", "Admin password")
	flag.BoolVar(&adminLocal, "admin-local", false, "Localhost only")
	debug := flag.Bool("debug", false, "Debug mode")
	flag.Parse()

	if err := loadPrivateKey(*privateKeyPath); err != nil {
		log.Fatalf("Failed to load key: %v", err)
	}

	if !*debug {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.Default()
	router.POST("/passgfw", handlePassGFW)
	router.GET("/health", handleHealth)
	router.GET("/admin", adminAuth(), handleAdminPage)
	router.POST("/api/generate-list", adminAuth(), handleGenerateList)
	router.POST("/api/generate-keys", adminAuth(), handleGenerateKeys)

	log.Printf("Server: :%s | Domain: %s | Auth: %v", port, serverDomain, adminUser != "")
	router.Run(":" + port)
}

func adminAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		if adminLocal {
			ip := c.ClientIP()
			if ip != "127.0.0.1" && ip != "::1" && ip != "localhost" {
				c.JSON(http.StatusForbidden, ErrorResponse{Error: "Localhost only"})
				c.Abort()
				return
			}
		}

		if adminUser != "" && adminPass != "" {
			user, pass, hasAuth := c.Request.BasicAuth()
			if !hasAuth || user != adminUser || pass != adminPass {
				c.Header("WWW-Authenticate", `Basic realm="PassGFW"`)
				c.JSON(http.StatusUnauthorized, ErrorResponse{Error: "Auth required"})
				c.Abort()
				return
			}
		}
		c.Next()
	}
}

func loadPrivateKey(path string) error {
	data := []byte(builtinPrivateKey)
	if path != "" {
		var err error
		data, err = os.ReadFile(path)
		if err != nil {
			return err
		}
	}

	block, _ := pem.Decode(data)
	if block == nil {
		return fmt.Errorf("invalid PEM")
	}

	key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return err
		}
		key = parsed.(*rsa.PrivateKey)
	}

	privateKey = key
	return nil
}

// Handle /passgfw endpoint
func handlePassGFW(c *gin.Context) {
	// Read and decrypt request
	encryptedData, err := c.GetRawData()
	if err != nil || len(encryptedData) == 0 {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Invalid request body"})
		return
	}

	decryptedData, err := rsa.DecryptOAEP(sha256.New(), rand.Reader, privateKey, encryptedData, nil)
	if err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Decryption failed"})
		return
	}

	// Parse payload
	var payload ClientPayload
	if err := json.Unmarshal(decryptedData, &payload); err != nil || payload.Nonce == "" {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Invalid payload"})
		return
	}

	// Build response data
	domain := serverDomain
	if domain == "" {
		domain = c.Request.Host
	}
	responseData := buildResponseData(domain, payload.OS, payload.App, payload.Data)

	// Decode nonce from base64
	nonceBytes, err := base64.StdEncoding.DecodeString(payload.Nonce)
	if err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Invalid nonce"})
		return
	}

	// Marshal response data to JSON bytes
	dataBytes, err := json.Marshal(responseData)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Failed to marshal data"})
		return
	}

	// Build response for signing (without signature field)
	responseForSigning := PassGFWResponse{
		Nonce: nonceBytes,
		Data:  dataBytes,
		URLs:  nil, // Add URLs here if needed
	}

	// Marshal the response to get signing bytes
	signBytes, err := json.Marshal(responseForSigning)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Failed to marshal for signing"})
		return
	}

	// Sign the marshaled response
	hashed := sha256.Sum256(signBytes)
	signature, err := rsa.SignPSS(rand.Reader, privateKey, crypto.SHA256, hashed[:], nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: "Signing failed"})
		return
	}

	// Return response with signature
	c.JSON(http.StatusOK, PassGFWResponse{
		Nonce:     nonceBytes,
		Data:      dataBytes,
		URLs:      nil, // Add URLs here if needed
		Signature: signature,
	})
}

// Build response data - customize based on OS/App/Data
func buildResponseData(domain, os, app, clientData string) any {
	data := map[string]any{
		"domain":  domain,
		"version": "2.2",
	}

	// Custom routing examples
	switch clientData {
	case "cdn":
		data["domain"] = "cdn.example.com:443"
	case "mobile":
		data["domain"] = "mobile.example.com:443"
	}

	return data
}

func handleHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func handleAdminPage(c *gin.Context) {
	c.Header("Content-Type", "text/html; charset=utf-8")
	c.String(http.StatusOK, getAdminHTML())
}

func handleGenerateList(c *gin.Context) {
	var req struct {
		URLs []URLEntry `json:"urls" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	jsonData, _ := json.Marshal(req.URLs)
	b64 := base64.StdEncoding.EncodeToString(jsonData)

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"json":        string(jsonData),
		"base64":      b64,
		"pgfw_format": fmt.Sprintf("*PGFW*%s*PGFW*", b64),
	})
}

func handleGenerateKeys(c *gin.Context) {
	var req struct {
		KeySize int `json:"key_size"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.KeySize == 0 {
		req.KeySize = 2048
	}
	if req.KeySize < 1024 || req.KeySize > 8192 {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: "Invalid key size"})
		return
	}

	privKey, err := rsa.GenerateKey(rand.Reader, req.KeySize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	privKeyPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(privKey),
	})

	pubKeyBytes, _ := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
	pubKeyPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "PUBLIC KEY",
		Bytes: pubKeyBytes,
	})

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
                            <option value="navigate">Navigate (导航)</option>
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
                    <option value="navigate">Navigate (导航)</option>
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
                    // 只有当 store 被勾选且 method 是 api 或 file 时才添加 store 字段
                    if (storeChecked && (method === 'api' || method === 'file')) {
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
