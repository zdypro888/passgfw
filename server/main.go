package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

var (
	privateKey *rsa.PrivateKey
	port       string
)

// Request structure
type PassGFWRequest struct {
	Data string `json:"data" binding:"required"` // Base64 encoded encrypted data
}

// Response structure
type PassGFWResponse struct {
	Data      string `json:"data"`      // Decrypted data
	Signature string `json:"signature"` // Base64 encoded signature
}

// Error response structure
type ErrorResponse struct {
	Error string `json:"error"`
}

func main() {
	// Parse command line flags
	privateKeyPath := flag.String("private-key", "../client/keys/private_key.pem", "Path to private key")
	flag.StringVar(&port, "port", "8080", "Server port")
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
	log.Printf("✅ Decrypted: %s", decryptedStr)

	// Sign the decrypted data
	hashed := sha256.Sum256([]byte(decryptedStr))
	signature, err := rsa.SignPKCS1v15(rand.Reader, privateKey, crypto.SHA256, hashed[:])
	if err != nil {
		log.Printf("❌ Signing failed: %v", err)
		c.JSON(http.StatusInternalServerError, ErrorResponse{
			Error: "Signing failed",
		})
		return
	}

	signatureBase64 := base64.StdEncoding.EncodeToString(signature)

	// Send response
	resp := PassGFWResponse{
		Data:      decryptedStr,
		Signature: signatureBase64,
	}

	c.JSON(http.StatusOK, resp)
	log.Printf("📤 Response sent successfully")
}

// Handle /health endpoint
func handleHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"server":  "PassGFW Server",
		"version": "1.0.1",
	})
}
