// C++ API Usage Example
#include "passgfw.h"
#include <iostream>

int main() {
    std::cout << "PassGFW Detector Example" << std::endl;
    std::cout << "========================" << std::endl;
    
    // Method 1: Use C API (Recommended)
    PassGFWDetector* detector = passgfw_create();
    if (!detector) {
        std::cout << "Failed to create detector" << std::endl;
        return 1;
    }
    
    std::cout << "Starting server detection..." << std::endl;
    
    char domain[256];
    if (passgfw_get_final_server(detector, domain, sizeof(domain)) == 0) {
        std::cout << "Success! Available server: " << domain << std::endl;
    } else {
        char error[256];
        passgfw_get_last_error(detector, error, sizeof(error));
        std::cout << "Failed: " << error << std::endl;
    }
    
    passgfw_destroy(detector);
    
    return 0;
}

/*
// Method 2: Use C++ class directly (Not recommended for cross-language)
#include "firewall_detector.h"

int main() {
    std::cout << "PassGFW Detector Example" << std::endl;
    std::cout << "========================" << std::endl;
    
    // Create detector
    passgfw::FirewallDetector detector;
    
    // Optional: Add custom URL
    // detector.AddURL("https://custom.example.com/api");
    
    std::cout << "Starting server detection..." << std::endl;
    
    // Get available server domain (blocking until found)
    std::string domain = detector.GetFinalServer();
    
    std::cout << "Success! Available server: " << domain << std::endl;
    
    return 0;
}
*/
