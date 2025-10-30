#ifndef PASSGFW_CONFIG_H
#define PASSGFW_CONFIG_H

#include <vector>
#include <string>

namespace passgfw {

/**
 * Configuration Class
 * Contains built-in URLs and public key for verification
 */
class Config {
public:
    /**
     * Get built-in URL list
     */
    static std::vector<std::string> GetBuiltinURLs();
    
    /**
     * Get embedded public key (PEM format)
     * This key is auto-generated during build
     */
    static const char* GetPublicKey();
    
    // Timeout settings (seconds)
    static constexpr int REQUEST_TIMEOUT = 10;  // HTTP request timeout
    static constexpr int RETRY_INTERVAL = 2;    // Retry interval when all URLs fail
    static constexpr int URL_INTERVAL = 500;    // Interval between URL checks (milliseconds)
    
    // Retry settings
    static constexpr int MAX_RETRIES = 3;       // Maximum number of retries per URL
    static constexpr int RETRY_DELAY_MS = 1000; // Delay between retries (milliseconds)
    
    // Security limits
    static constexpr int MAX_LIST_RECURSION_DEPTH = 5;  // Maximum nested list# depth
    static constexpr int NONCE_SIZE = 32;  // Random nonce size in bytes
    static constexpr int MAX_CLIENT_DATA_SIZE = 200;  // Maximum client_data length (RSA 2048 limit ~245 bytes for payload)
};

} // namespace passgfw

#endif // PASSGFW_CONFIG_H
