#include "firewall_detector.h"
#include "config.h"
#include <thread>
#include <chrono>
#include <sstream>
#include <algorithm>

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

std::string FirewallDetector::GetFinalServer() {
    printf("[DEBUG] GetFinalServer() called\n"); fflush(stdout);
    printf("[DEBUG] URL list size: %zu\n", url_list_.size()); fflush(stdout);
    
    // Loop infinitely until finding an available server
    while (true) {
        printf("[DEBUG] Starting URL iteration...\n"); fflush(stdout);
        // Iterate through URL list
        for (const auto& url : url_list_) {
            printf("[DEBUG] Checking URL: %s\n", url.c_str()); fflush(stdout);
            std::string domain;
            
            // Try to detect this URL
            if (CheckURL(url, domain)) {
                // Success! Return domain
                return domain;
            }
            
            // Failed, wait a moment before continuing
            std::this_thread::sleep_for(std::chrono::milliseconds(Config::URL_INTERVAL));
        }
        
        // All URLs failed, wait and restart
        last_error_ = "All URL detection failed, retrying...";
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

bool FirewallDetector::CheckURL(const std::string& url, std::string& domain) {
    last_error_.clear();
    
    // Check if it's a special URL (ending with #)
    if (!url.empty() && url.back() == '#') {
        return CheckListURL(url, domain);
    } else {
        return CheckNormalURL(url, domain);
    }
}

bool FirewallDetector::CheckNormalURL(const std::string& url, std::string& domain) {
    printf("[DEBUG] CheckNormalURL() called for: %s\n", url.c_str());
    
    if (!network_client_) {
        last_error_ = "Network client not initialized";
        printf("[DEBUG] ERROR: Network client not initialized!\n");
        return false;
    }
    
    printf("[DEBUG] Network client OK, generating random data...\n");
    
    // ==================== C++ layer implements complete verification logic ====================
    
    // 1. Generate random data (32 bytes)
    std::string random_data;
    try {
        random_data = network_client_->GenerateRandom(32);
        printf("[DEBUG] Generated random data: %zu bytes\n", random_data.length());
        if (random_data.empty()) {
            last_error_ = "Failed to generate random data: " + url;
            return false;
        }
    } catch (...) {
        last_error_ = "Exception generating random data: " + url;
        return false;
    }
    
    // 2. Encrypt random data with public key
    printf("[DEBUG] Encrypting data...\n");
    std::string encrypted_data;
    try {
        encrypted_data = network_client_->EncryptWithPublicKey(random_data);
        printf("[DEBUG] Encrypted data: %zu bytes\n", encrypted_data.length());
        if (encrypted_data.empty()) {
            last_error_ = "Failed to encrypt data: " + url;
            return false;
        }
    } catch (...) {
        last_error_ = "Exception encrypting data: " + url;
        return false;
    }
    
    // 3. Construct POST request JSON
    printf("[DEBUG] Constructing JSON request...\n");
    std::map<std::string, std::string> request_data;
    request_data["data"] = encrypted_data;
    
    std::string request_json;
    try {
        request_json = network_client_->ToJson(request_data);
        printf("[DEBUG] JSON request: %s\n", request_json.c_str());
    } catch (...) {
        last_error_ = "Failed to construct request JSON: " + url;
        return false;
    }
    
    // 4. POST request to server
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
    
    // 5. Parse server response JSON
    std::map<std::string, std::string> response_data;
    try {
        response_data = network_client_->ParseJson(response.body);
    } catch (...) {
        last_error_ = "Failed to parse response JSON: " + url;
        return false;
    }
    
    // 6. Check if JSON contains required fields
    if (response_data.find("data") == response_data.end() ||
        response_data.find("signature") == response_data.end()) {
        last_error_ = "Response JSON missing required fields: " + url;
        return false;
    }
    
    std::string decrypted_data = response_data["data"];
    std::string signature = response_data["signature"];
    
    // 7. Verify signature
    bool signature_valid = false;
    try {
        signature_valid = network_client_->VerifySignature(decrypted_data, signature);
    } catch (...) {
        last_error_ = "Signature verification exception: " + url;
        return false;
    }
    
    if (!signature_valid) {
        last_error_ = "Signature verification failed: " + url;
        return false;
    }
    
    // 8. Verify decrypted data matches original random data
    if (decrypted_data != random_data) {
        last_error_ = "Data mismatch: " + url + " (expected: " + random_data.substr(0, 10) + 
                     "..., actual: " + decrypted_data.substr(0, 10) + "...)";
        return false;
    }
    
    // 9. All verification passed, extract domain
    domain = ExtractDomain(url);
    return true;
}

bool FirewallDetector::CheckListURL(const std::string& url, std::string& domain) {
    printf("[DEBUG] CheckListURL() called for: %s\n", url.c_str()); fflush(stdout);
    
    if (!network_client_) {
        last_error_ = "Network client not initialized";
        return false;
    }
    
    // Remove trailing # character
    std::string actual_url = url.substr(0, url.length() - 1);
    
    // ==================== C++ layer implements list fetch logic ====================
    
    // 1. GET request to fetch list file content
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
    std::vector<std::string> addon_urls = ParseURLList(response.body);
    
    if (addon_urls.empty()) {
        last_error_ = "List empty or parse failed: " + actual_url;
        return false;
    }
    
    printf("[DEBUG] Fetched %zu URLs from list, adding to main URL list\n", addon_urls.size()); fflush(stdout);
    
    // 3. Add all URLs from list to the main URL list
    // Important: Don't recursively check here!
    // Let the main loop restart and check all URLs from beginning
    for (const auto& addon_url : addon_urls) {
        // Avoid duplicates
        if (std::find(url_list_.begin(), url_list_.end(), addon_url) == url_list_.end()) {
            printf("[DEBUG] Adding new URL: %s\n", addon_url.c_str()); fflush(stdout);
            url_list_.push_back(addon_url);
        }
    }
    
    // Return false to let the main loop continue
    // The main loop will restart from beginning and check all URLs (including newly added ones)
    last_error_ = "Added URLs from list: " + actual_url + ", restarting detection from beginning";
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
    // Find protocol end position
    size_t proto_end = url.find("://");
    if (proto_end == std::string::npos) {
        return "";
    }
    
    size_t domain_start = proto_end + 3;
    
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
