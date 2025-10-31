import Foundation

/// Manages persistent storage of URLs locally
class URLStorageManager {
    static let shared = URLStorageManager()
    
    private let fileName = "passgfw_urls.json"
    private var fileURL: URL?
    
    private init() {
        setupFileURL()
    }
    
    /// Setup file URL for storing URLs
    private func setupFileURL() {
        #if os(macOS)
        // macOS: Use Application Support directory
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = appSupport.appendingPathComponent("PassGFW", isDirectory: true)
            
            // Create directory if needed
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            
            fileURL = appDir.appendingPathComponent(fileName)
        }
        #else
        // iOS: Use Documents directory
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            fileURL = documents.appendingPathComponent(fileName)
        }
        #endif
        
        Logger.shared.debug("URL storage file: \(fileURL?.path ?? "not set")")
    }
    
    /// Load stored URLs from local file
    func loadStoredURLs() -> [URLEntry] {
        guard let fileURL = fileURL else {
            Logger.shared.debug("File URL not set, returning empty list")
            return []
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Logger.shared.debug("Storage file does not exist yet")
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let entries = try JSONDecoder().decode([URLEntry].self, from: data)
            Logger.shared.info("Loaded \(entries.count) stored URLs from local file")
            return entries
        } catch {
            Logger.shared.error("Failed to load stored URLs: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Save URLs to local file
    private func saveURLs(_ entries: [URLEntry]) -> Bool {
        guard let fileURL = fileURL else {
            Logger.shared.error("File URL not set, cannot save")
            return false
        }
        
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
            Logger.shared.info("Saved \(entries.count) URLs to local file")
            return true
        } catch {
            Logger.shared.error("Failed to save URLs: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Add a URL to storage (if not already exists)
    func addURL(_ entry: URLEntry) -> Bool {
        var entries = loadStoredURLs()
        
        // Check if already exists
        if entries.contains(where: { $0.url == entry.url }) {
            Logger.shared.debug("URL already exists in storage: \(entry.url)")
            return true // Already exists, consider it success
        }
        
        // Add new entry
        entries.append(entry)
        Logger.shared.info("Adding URL to storage: \(entry.url) (method: \(entry.method))")
        
        return saveURLs(entries)
    }
    
    /// Remove a URL from storage
    func removeURL(_ url: String) -> Bool {
        var entries = loadStoredURLs()
        let originalCount = entries.count
        
        // Remove matching URL
        entries.removeAll { $0.url == url }
        
        if entries.count < originalCount {
            Logger.shared.info("Removed URL from storage: \(url)")
            return saveURLs(entries)
        } else {
            Logger.shared.debug("URL not found in storage: \(url)")
            return true // Not found, but not an error
        }
    }
    
    /// Clear all stored URLs
    func clearAll() -> Bool {
        Logger.shared.info("Clearing all stored URLs")
        return saveURLs([])
    }
    
    /// Get count of stored URLs
    func getCount() -> Int {
        return loadStoredURLs().count
    }
}

