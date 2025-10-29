#ifndef PASSGFW_HTTP_INTERFACE_H
#define PASSGFW_HTTP_INTERFACE_H

#include <string>
#include <map>
#include <vector>

namespace passgfw {

/**
 * HTTP Response Structure
 */
struct HttpResponse {
    bool success;           // Request succeeded or not
    int status_code;        // HTTP status code
    std::string body;       // Response body
    std::string error_msg;  // Error message
    
    HttpResponse() : success(false), status_code(0) {}
};

/**
 * Network Client Abstract Interface (Atomic Operations)
 * 
 * Platform layer only provides basic atomic operations, no business logic
 * C++ layer is responsible for composing these atomic operations 
 * to implement complete verification flow
 */
class INetworkClient {
public:
    virtual ~INetworkClient() {}
    
    // ==================== Configuration Interface ====================
    
    /**
     * Set public key (PEM format)
     * @param public_key_pem Public key string
     * @return true on success
     */
    virtual bool SetPublicKey(const std::string& public_key_pem) = 0;
    
    /**
     * Set timeout (seconds)
     */
    virtual void SetTimeout(int timeout_sec) = 0;
    
    // ==================== HTTP Interface ====================
    
    /**
     * POST request (send JSON)
     * @param url Target URL
     * @param json_body JSON string
     * @return HTTP response
     */
    virtual HttpResponse Post(const std::string& url, 
                             const std::string& json_body) = 0;
    
    /**
     * GET request
     * @param url Target URL
     * @return HTTP response
     */
    virtual HttpResponse Get(const std::string& url) = 0;
    
    // ==================== Encryption Interface ====================
    
    /**
     * Generate random string
     * @param length Length
     * @return Random string (Base64 encoded)
     */
    virtual std::string GenerateRandom(int length) = 0;
    
    /**
     * Encrypt data with public key
     * @param data Data to encrypt
     * @return Base64 encoded encrypted data
     */
    virtual std::string EncryptWithPublicKey(const std::string& data) = 0;
    
    /**
     * Verify signature
     * @param data Original data
     * @param signature Base64 encoded signature
     * @return true if verification succeeds
     */
    virtual bool VerifySignature(const std::string& data, 
                                 const std::string& signature) = 0;
    
    // ==================== JSON Interface ====================
    
    /**
     * Parse JSON string
     * @param json_str JSON string
     * @return Key-value map (string type only)
     */
    virtual std::map<std::string, std::string> ParseJson(
        const std::string& json_str) = 0;
    
    /**
     * Generate JSON string
     * @param data Key-value map
     * @return JSON string
     */
    virtual std::string ToJson(
        const std::map<std::string, std::string>& data) = 0;
};

/**
 * Create platform-specific network client instance
 * This function is implemented by each platform
 */
INetworkClient* CreatePlatformNetworkClient();

} // namespace passgfw

#endif // PASSGFW_HTTP_INTERFACE_H
