#ifndef PASSGFW_FIREWALL_DETECTOR_H
#define PASSGFW_FIREWALL_DETECTOR_H

#include <string>
#include <vector>
#include "http_interface.h"

namespace passgfw {

/**
 * Firewall Detector
 * 
 * Core functionality:
 * 1. Detect built-in URL list in order
 * 2. For normal URL: POST encrypted data, verify server's signed response
 * 3. For special URL (ending with #): Get URL list, detect recursively
 * 4. Loop infinitely until finding an available server
 */
class FirewallDetector {
public:
    FirewallDetector();
    ~FirewallDetector();
    
    /**
     * Core function: Get final available server domain
     * 
     * Process:
     * 1. Iterate through built-in URL list
     * 2. Detect each URL:
     *    - If URL ends with #, get list and detect URLs in the list
     *    - Otherwise, POST encrypted data and verify signature
     * 3. If available server found, return its domain
     * 4. If all URLs fail, wait and retry
     * 5. Loop infinitely until success
     * 
     * @return Available server domain (e.g. "abc.com")
     */
    std::string GetFinalServer();
    
    /**
     * Set custom URL list (override built-in list)
     */
    void SetURLList(const std::vector<std::string>& urls);
    
    /**
     * Add URL to list
     */
    void AddURL(const std::string& url);
    
    /**
     * Get last error message
     */
    std::string GetLastError() const;
    
private:
    /**
     * Detect single URL
     * @param url URL to detect
     * @param domain Output parameter, store successful domain
     * @return true on success
     */
    bool CheckURL(const std::string& url, std::string& domain);
    
    /**
     * Detect normal URL (POST data, verify signature)
     * @param url URL to detect
     * @param domain Output parameter, store successful domain
     * @return true on success
     */
    bool CheckNormalURL(const std::string& url, std::string& domain);
    
    /**
     * Detect list URL (get URL list)
     * @param url URL to detect (ending with #)
     * @param domain Output parameter, store successful domain
     * @return true on success
     */
    bool CheckListURL(const std::string& url, std::string& domain);
    
    /**
     * Extract domain from URL
     * @param url Complete URL
     * @return Domain (e.g. "abc.com")
     */
    std::string ExtractDomain(const std::string& url);
    
    /**
     * Parse URL list text
     * @param content Text content (one URL per line)
     * @return URL list
     */
    std::vector<std::string> ParseURLList(const std::string& content);

private:
    std::vector<std::string> url_list_;
    INetworkClient* network_client_;  // Unified network client
    std::string last_error_;
};

} // namespace passgfw

#endif // PASSGFW_FIREWALL_DETECTOR_H
