/**
 * Swift Usage Example
 */

import Foundation

class PassGFWManager {
    private var detector: OpaquePointer?
    
    init() {
        detector = passgfw_create()
    }
    
    deinit {
        if let detector = detector {
            passgfw_destroy(detector)
        }
    }
    
    /// Get available server (blocking call, run in background thread)
    func getFinalServer() -> String? {
        guard let detector = detector else { return nil }
        
        var domain = [CChar](repeating: 0, count: 256)
        
        if passgfw_get_final_server(detector, &domain, Int32(domain.count)) == 0 {
            return String(cString: domain)
        }
        
        return nil
    }
    
    /// Add custom URL
    func addURL(_ url: String) -> Bool {
        guard let detector = detector else { return false }
        return passgfw_add_url(detector, url) == 0
    }
    
    /// Get last error
    func getLastError() -> String? {
        guard let detector = detector else { return nil }
        
        var error = [CChar](repeating: 0, count: 256)
        
        if passgfw_get_last_error(detector, &error, Int32(error.count)) == 0 {
            return String(cString: error)
        }
        
        return nil
    }
    
    /// Get available server asynchronously
    func getFinalServerAsync(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let domain = self.getFinalServer()
            DispatchQueue.main.async {
                completion(domain)
            }
        }
    }
}

// Usage Example
func exampleUsage() {
    let manager = PassGFWManager()
    
    // Optional: Add custom URL
    // _ = manager.addURL("https://custom.example.com/check")
    
    print("Starting server detection...")
    
    // Async fetch
    manager.getFinalServerAsync { domain in
        if let domain = domain {
            print("✅ Found available server: \(domain)")
        } else {
            if let error = manager.getLastError() {
                print("❌ Detection failed: \(error)")
            }
        }
    }
}
