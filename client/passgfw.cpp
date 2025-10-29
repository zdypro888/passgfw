#include "passgfw.h"
#include "firewall_detector.h"
#include <cstring>

using namespace passgfw;

PassGFWDetector passgfw_create() {
    try {
        FirewallDetector* detector = new FirewallDetector();
        return static_cast<PassGFWDetector>(detector);
    } catch (...) {
        return nullptr;
    }
}

void passgfw_destroy(PassGFWDetector detector) {
    if (detector) {
        FirewallDetector* d = static_cast<FirewallDetector*>(detector);
        delete d;
    }
}

int passgfw_get_final_server(PassGFWDetector detector, 
                             char* out_domain, 
                             int domain_size) {
    if (!detector || !out_domain || domain_size <= 0) {
        return -1;
    }
    
    try {
        FirewallDetector* d = static_cast<FirewallDetector*>(detector);
        std::string domain = d->GetFinalServer();
        
        // Copy to output buffer
        size_t len = domain.length();
        if (len >= static_cast<size_t>(domain_size)) {
            len = domain_size - 1;
        }
        
        memcpy(out_domain, domain.c_str(), len);
        out_domain[len] = '\0';
        
        return 0;
    } catch (...) {
        return -1;
    }
}

int passgfw_set_url_list(PassGFWDetector detector, 
                        const char** urls, 
                        int count) {
    if (!detector || !urls || count <= 0) {
        return -1;
    }
    
    try {
        FirewallDetector* d = static_cast<FirewallDetector*>(detector);
        
        std::vector<std::string> url_list;
        for (int i = 0; i < count; i++) {
            if (urls[i]) {
                url_list.push_back(urls[i]);
            }
        }
        
        d->SetURLList(url_list);
        return 0;
    } catch (...) {
        return -1;
    }
}

int passgfw_add_url(PassGFWDetector detector, const char* url) {
    if (!detector || !url) {
        return -1;
    }
    
    try {
        FirewallDetector* d = static_cast<FirewallDetector*>(detector);
        d->AddURL(url);
        return 0;
    } catch (...) {
        return -1;
    }
}

int passgfw_get_last_error(PassGFWDetector detector, 
                           char* out_error, 
                           int error_size) {
    if (!detector || !out_error || error_size <= 0) {
        return -1;
    }
    
    try {
        FirewallDetector* d = static_cast<FirewallDetector*>(detector);
        std::string error = d->GetLastError();
        
        // Copy to output buffer
        size_t len = error.length();
        if (len >= static_cast<size_t>(error_size)) {
            len = error_size - 1;
        }
        
        memcpy(out_error, error.c_str(), len);
        out_error[len] = '\0';
        
        return 0;
    } catch (...) {
        return -1;
    }
}
