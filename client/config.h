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
};

} // namespace passgfw

#endif // PASSGFW_CONFIG_H
