#include "firewall_detector.h"
#include "config.h"
#include "logger.h"
#include <thread>
#include <chrono>
#include <sstream>

namespace passgfw {

FirewallDetector::FirewallDetector() {
    // Load built-in URL list
    url_list_ = Config::GetBuiltinURLs();
    
    // Create platform-specific network client
    network_client_ = CreatePlatformNetworkClient();
    
    // Set public key and timeout
    if (network_client_) {
        network_client_->SetPublicKey(Config::GetPublicKey());
        network_client_->SetTimeout(Config::REQUEST_TIMEOUT);
    }
}

FirewallDetector::~FirewallDetector() {
    if (network_client_) {
        delete network_client_;
        network_client_ = nullptr;
    }
}

std::string FirewallDetector::GetFinalServer(const std::string& custom_data) {
    LOG_DEBUGF("GetFinalServer() called with custom_data: %s", custom_data.c_str());
    LOG_DEBUGF("URL list size: %zu", url_list_.size());
    
    // Loop infinitely until finding an available server
    while (true) {
        LOG_DEBUG("Starting URL iteration...");
        // Iterate through URL list
        for (const auto& url : url_list_) {
            LOG_DEBUGF("Checking URL: %s", url.c_str());
            std::string domain;
            
            // Try to detect this URL
            if (CheckURL(url, custom_data, domain)) {
                // Success! Return domain
                LOG_INFOF("Found available server: %s", domain.c_str());
                return domain;
            }
            
            // Failed, wait a moment before continuing
            std::this_thread::sleep_for(std::chrono::milliseconds(Config::URL_INTERVAL));
        }
        
        // All URLs failed, wait and restart
        last_error_ = "All URL detection failed, retrying...";
        LOG_WARNING(last_error_);
        std::this_thread::sleep_for(std::chrono::seconds(Config::RETRY_INTERVAL));
    }
    
    // Never reach here
    return "";
}

void FirewallDetector::SetURLList(const std::vector<std::string>& urls) {
    url_list_ = urls;
}

void FirewallDetector::AddURL(const std::string& url) {
    url_list_.push_back(url);
}

std::string FirewallDetector::GetLastError() const {
    return last_error_;
}

bool FirewallDetector::CheckURL(const std::string& url, const std::string& custom_data, std::string& domain, int recursion_depth) {
    last_error_.clear();
    
    // Check recursion depth limit
    if (recursion_depth > Config::MAX_LIST_RECURSION_DEPTH) {
        last_error_ = "Maximum list recursion depth exceeded: " + url;
        LOG_ERRORF("Recursion depth limit reached (%d) for URL: %s", recursion_depth, url.c_str());
        return false;
    }
    
    // Check if it's a special URL (ending with #)
    if (!url.empty() && url.back() == '#') {
        return CheckListURL(url, custom_data, domain, recursion_depth);
    } else {
        return CheckNormalURL(url, custom_data, domain);
    }
}

bool FirewallDetector::CheckNormalURL(const std::string& url, const std::string& custom_data, std::string& domain) {
    LOG_DEBUGF("CheckNormalURL() called for: %s with custom_data: %s", url.c_str(), custom_data.c_str());
    
    // Validate input
    if (url.empty()) {
        last_error_ = "Empty URL provided";
        return false;
    }
    
    if (!network_client_) {
        last_error_ = "Network client not initialized";
        LOG_ERROR("Network client not initialized!");
        return false;
    }
    
    // Retry loop
    for (int attempt = 1; attempt <= Config::MAX_RETRIES; ++attempt) {
        LOG_DEBUGF("Attempt %d/%d for URL: %s", attempt, Config::MAX_RETRIES, url.c_str());
        
        if (CheckNormalURLOnce(url, custom_data, domain)) {
            LOG_INFOF("Successfully verified URL: %s on attempt %d", url.c_str(), attempt);
            return true;
        }
        
        // If this was the last attempt, give up
        if (attempt == Config::MAX_RETRIES) {
            LOG_WARNINGF("All %d attempts failed for URL: %s. Last error: %s", 
                        Config::MAX_RETRIES, url.c_str(), last_error_.c_str());
            return false;
        }
        
        // Wait before retry
        LOG_DEBUGF("Waiting %dms before retry...", Config::RETRY_DELAY_MS);
        std::this_thread::sleep_for(std::chrono::milliseconds(Config::RETRY_DELAY_MS));
    }
    
    return false;
}

bool FirewallDetector::CheckNormalURLOnce(const std::string& url, const std::string& custom_data, std::string& domain) {
    LOG_DEBUG("Network client OK, generating random data...");
    
    // ==================== C++ layer implements complete verification logic ====================
    
    // 1. Generate random data (nonce)
    std::string random_data;
    try {
        random_data = network_client_->GenerateRandom(Config::NONCE_SIZE);
        LOG_DEBUGF("Generated random data: %zu bytes", random_data.length());
        if (random_data.empty()) {
            last_error_ = "Failed to generate random data: " + url;
            return false;
        }
    } catch (...) {
        last_error_ = "Exception generating random data: " + url;
        return false;
    }
    
    // Validate and truncate client_data if too long (RSA encryption limit)
    std::string truncated_custom_data = custom_data;
    if (truncated_custom_data.length() > Config::MAX_CLIENT_DATA_SIZE) {
        LOG_WARNINGF("client_data truncated from %zu to %d bytes", 
                    truncated_custom_data.length(), Config::MAX_CLIENT_DATA_SIZE);
        truncated_custom_data = truncated_custom_data.substr(0, Config::MAX_CLIENT_DATA_SIZE);
    }
    
    // 2. Build JSON with random and custom data
    std::map<std::string, std::string> payload;
    payload["nonce"] = random_data;
    payload["client_data"] = truncated_custom_data;
    
    std::string payload_json;
    try {
        payload_json = network_client_->ToJson(payload);
        LOG_DEBUGF("Payload JSON: %s", payload_json.c_str());
    } catch (...) {
        last_error_ = "Failed to construct payload JSON: " + url;
        return false;
    }
    
    // 3. Encrypt payload JSON with public key
    LOG_DEBUG("Encrypting payload...");
    std::string encrypted_data;
    try {
        encrypted_data = network_client_->EncryptWithPublicKey(payload_json);
        LOG_DEBUGF("Encrypted data: %zu bytes", encrypted_data.length());
        if (encrypted_data.empty()) {
            last_error_ = "Failed to encrypt data: " + url;
            return false;
        }
    } catch (...) {
        last_error_ = "Exception encrypting data: " + url;
        return false;
    }
    
    // 4. Construct POST request JSON
    LOG_DEBUG("Constructing JSON request...");
    std::map<std::string, std::string> request_data;
    request_data["data"] = encrypted_data;
    
    std::string request_json;
    try {
        request_json = network_client_->ToJson(request_data);
        LOG_DEBUGF("JSON request: %s", request_json.c_str());
    } catch (...) {
        last_error_ = "Failed to construct request JSON: " + url;
        return false;
    }
    
    // 5. POST request to server
    HttpResponse response;
    try {
        response = network_client_->Post(url, request_json);
    } catch (...) {
        last_error_ = "POST request exception: " + url;
        return false;
    }
    
    if (!response.success) {
        last_error_ = "POST request failed: " + url + " - " + response.error_msg;
        return false;
    }
    
    // 6. Parse server response JSON
    std::map<std::string, std::string> response_data;
    try {
        response_data = network_client_->ParseJson(response.body);
    } catch (...) {
        last_error_ = "Failed to parse response JSON: " + url;
        return false;
    }
    
    // 7. Check if JSON contains required fields
    if (response_data.find("data") == response_data.end() ||
        response_data.find("signature") == response_data.end()) {
        last_error_ = "Response JSON missing required fields: " + url;
        return false;
    }
    
    std::string server_response_json = response_data["data"];
    std::string signature = response_data["signature"];
    
    LOG_DEBUGF("Server response JSON: %s", server_response_json.c_str());
    
    // 8. Verify signature
    bool signature_valid = false;
    try {
        signature_valid = network_client_->VerifySignature(server_response_json, signature);
    } catch (...) {
        last_error_ = "Signature verification exception: " + url;
        return false;
    }
    
    if (!signature_valid) {
        last_error_ = "Signature verification failed: " + url;
        return false;
    }
    
    // 9. Parse server response JSON
    std::map<std::string, std::string> server_payload;
    try {
        server_payload = network_client_->ParseJson(server_response_json);
    } catch (...) {
        last_error_ = "Failed to parse server response JSON: " + url;
        return false;
    }
    
    // 10. Check required fields in response
    if (server_payload.find("nonce") == server_payload.end() ||
        server_payload.find("server_domain") == server_payload.end()) {
        last_error_ = "Server response missing required fields: " + url;
        return false;
    }
    
    std::string returned_nonce = server_payload["nonce"];
    std::string returned_domain = server_payload["server_domain"];
    
    LOG_DEBUGF("Returned nonce: %s", returned_nonce.c_str());
    LOG_DEBUGF("Returned domain: %s", returned_domain.c_str());
    
    // 11. Verify nonce matches
    if (returned_nonce != random_data) {
        // Safe substr with length check
        size_t expected_len = std::min(random_data.length(), size_t(10));
        size_t actual_len = std::min(returned_nonce.length(), size_t(10));
        last_error_ = "Nonce mismatch: " + url + 
                     " (expected: " + random_data.substr(0, expected_len) + 
                     "..., actual: " + returned_nonce.substr(0, actual_len) + "...)";
        return false;
    }
    
    // 12. All verification passed, use server-provided domain
    domain = returned_domain;
    LOG_DEBUGF("Verification successful! Using domain: %s", domain.c_str());
    return true;
}

bool FirewallDetector::CheckListURL(const std::string& url, const std::string& custom_data, std::string& domain, int recursion_depth) {
    LOG_DEBUGF("CheckListURL() called for: %s (depth: %d)", url.c_str(), recursion_depth);
    
    // Validate input
    if (url.empty() || url.length() < 2) {
        last_error_ = "Invalid list URL: too short";
        return false;
    }
    
    if (!network_client_) {
        last_error_ = "Network client not initialized";
        return false;
    }
    
    // Remove trailing # character
    std::string actual_url = url.substr(0, url.length() - 1);
    
    // Validate actual URL is not empty
    if (actual_url.empty()) {
        last_error_ = "Empty URL after removing #";
        return false;
    }
    
    // ==================== Fetch sub-list and check each URL ====================
    
    // 1. GET request to fetch list file content
    LOG_DEBUGF("Fetching sub-list from: %s", actual_url.c_str());
    HttpResponse response;
    try {
        response = network_client_->Get(actual_url);
    } catch (...) {
        last_error_ = "GET request exception: " + actual_url;
        return false;
    }
    
    if (!response.success) {
        last_error_ = "GET request failed: " + actual_url + " - " + response.error_msg;
        return false;
    }
    
    // 2. Parse text content into URL list
    std::vector<std::string> sub_urls = ParseURLList(response.body);
    
    if (sub_urls.empty()) {
        last_error_ = "Sub-list empty or parse failed: " + actual_url;
        return false;
    }
    
    LOG_DEBUGF("Fetched %zu URLs from sub-list, checking each one...", sub_urls.size());
    
    // 3. Check each URL in the sub-list
    // Important: Check immediately, don't add to main list
    for (const auto& sub_url : sub_urls) {
        LOG_DEBUGF("Checking sub-list URL: %s", sub_url.c_str());
        
        std::string sub_domain;
        // Recursively check (supports nested list#), increment depth
        if (CheckURL(sub_url, custom_data, sub_domain, recursion_depth + 1)) {
            // Success! Return this domain
            LOG_INFOF("Sub-list URL succeeded: %s -> %s", sub_url.c_str(), sub_domain.c_str());
            domain = sub_domain;
            return true;
        }
        
        // Failed, try next URL in sub-list
        LOG_DEBUGF("Sub-list URL failed: %s, trying next...", sub_url.c_str());
        
        // Short delay before next URL
        std::this_thread::sleep_for(std::chrono::milliseconds(Config::URL_INTERVAL));
    }
    
    // All URLs in sub-list failed
    LOG_DEBUG("All URLs in sub-list failed");
    last_error_ = "All URLs in sub-list failed: " + actual_url;
    return false;
}

std::vector<std::string> FirewallDetector::ParseURLList(const std::string& content) {
    std::vector<std::string> urls;
    
    // Try to extract content between *GFW* markers
    const std::string marker = "*GFW*";
    size_t start_pos = content.find(marker);
    
    if (start_pos != std::string::npos) {
        // Found start marker, find end marker
        start_pos += marker.length();
        size_t end_pos = content.find(marker, start_pos);
        
        if (end_pos != std::string::npos) {
            // Extract content between markers
            std::string gfw_content = content.substr(start_pos, end_pos - start_pos);
            
            // Trim whitespace
            size_t trim_start = gfw_content.find_first_not_of(" \t\r\n");
            size_t trim_end = gfw_content.find_last_not_of(" \t\r\n");
            
            if (trim_start != std::string::npos && trim_end != std::string::npos) {
                gfw_content = gfw_content.substr(trim_start, trim_end - trim_start + 1);
                
                // Split by | delimiter
                size_t pos = 0;
                while (pos < gfw_content.length()) {
                    size_t delim_pos = gfw_content.find('|', pos);
                    std::string url;
                    
                    if (delim_pos == std::string::npos) {
                        url = gfw_content.substr(pos);
                        pos = gfw_content.length();
                    } else {
                        url = gfw_content.substr(pos, delim_pos - pos);
                        pos = delim_pos + 1;
                    }
                    
                    // Trim each URL
                    size_t url_start = url.find_first_not_of(" \t\r\n");
                    size_t url_end = url.find_last_not_of(" \t\r\n");
                    
                    if (url_start != std::string::npos && url_end != std::string::npos) {
                        url = url.substr(url_start, url_end - url_start + 1);
                        
                        // Validate URL
                        if (url.find("http://") == 0 || url.find("https://") == 0) {
                            urls.push_back(url);
                        }
                    }
                }
                
                return urls;
            }
        }
    }
    
    // Fallback: Parse line by line (backward compatibility)
    std::string line;
    std::stringstream stream(content);
    
    while (std::getline(stream, line)) {
        // Trim leading/trailing whitespace
        size_t start = line.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) {
            continue; // Empty line
        }
        
        size_t end = line.find_last_not_of(" \t\r\n");
        line = line.substr(start, end - start + 1);
        
        // Ignore comment lines and empty lines
        if (line.empty() || line[0] == '#') {
            continue;
        }
        
        // Check if it's a valid URL (simple check)
        if (line.find("http://") == 0 || line.find("https://") == 0) {
            urls.push_back(line);
        }
    }
    
    return urls;
}

std::string FirewallDetector::ExtractDomain(const std::string& url) {
    // Validate input
    if (url.empty()) {
        return "";
    }
    
    // Find protocol end position
    size_t proto_end = url.find("://");
    if (proto_end == std::string::npos) {
        return "";
    }
    
    size_t domain_start = proto_end + 3;
    
    // Check if domain_start is valid
    if (domain_start >= url.length()) {
        return "";
    }
    
    // Find path start position (include port if present)
    // Extract host:port, not just host
    size_t path_start = url.find("/", domain_start);
    
    if (path_start == std::string::npos) {
        // No path, return everything after protocol
        return url.substr(domain_start);
    } else {
        // Return host:port (everything before path)
        return url.substr(domain_start, path_start - domain_start);
    }
}

} // namespace passgfw
