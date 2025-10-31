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
)

// Request structure
type PassGFWRequest struct {
	Data string `json:"data" binding:"required"` // Base64 encoded encrypted data
}

// URL Entry structure
type URLEntry struct {
	Method string `json:"method"` // "api" or "file"
	URL    string `json:"url"`    // URL string
}

// Response structure
// Signature is calculated on the JSON of this struct WITHOUT the signature field
// IMPORTANT: domain must not use omitempty to ensure consistent JSON structure for signature verification
type PassGFWResponse struct {
	Random    string     `json:"random"`           // Echoed nonce from client
	Domain    string     `json:"domain"`           // Server domain (for API response) - MUST be present
	URLs      []URLEntry `json:"urls,omitempty"`   // URL list (for file response)
	Signature string     `json:"signature"`        // Base64 encoded RSA-SHA256 signature
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

	// Start server
	addr := ":" + port
	log.Printf("")
	log.Printf("🌐 Server listening on %s", addr)
	log.Printf("   Endpoints:")
	log.Printf("   - POST http://localhost:%s/passgfw", port)
	log.Printf("   - GET  http://localhost:%s/health", port)
	log.Printf("")

	if err := router.Run(addr); err != nil {
		log.Fatalf("❌ Server error: %v", err)
	}
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
