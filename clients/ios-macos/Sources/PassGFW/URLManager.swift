import Foundation

/// URL 管理器 - 负责 URL 列表的持久化存储
/// URL Manager - Thread-safe using Actor
actor URLManager {
    private static let storageKey = "passgfw.urls"
    private let storage: SecureStorage

    init(storage: SecureStorage) {
        self.storage = storage
    }

    /// 初始化 URL 列表（仅首次启动时调用）
    /// - Returns: 是否成功初始化
    func initializeIfNeeded() -> Bool {
        // 检查是否已经初始化
        if let _ = loadURLs() {
            return true  // 已经初始化过了
        }

        // 首次启动，使用内置 URLs 初始化
        let builtinURLs = Config.getBuiltinURLs()
        return saveURLs(builtinURLs)
    }

    /// 获取 URL 列表（按存储顺序）
    /// - Returns: URLEntry 数组
    func getURLs() -> [URLEntry] {
        guard let urls = loadURLs() else {
            // 如果加载失败，返回内置 URLs
            return Config.getBuiltinURLs()
        }
        return urls
    }

    /// 添加新的 URL（通过动态添加，store=true）
    /// - Parameter entry: 要添加的 URLEntry
    /// - Returns: 是否成功添加
    func addURL(_ entry: URLEntry) -> Bool {
        var urls = loadURLs() ?? []

        // 检查是否已存在
        if urls.contains(where: { $0.url == entry.url }) {
            return true  // 已存在，不重复添加
        }

        // 添加新 URL
        urls.append(entry)
        return saveURLs(urls)
    }

    /// 删除 URL（remove 方法）
    /// - Parameter url: 要删除的 URL
    /// - Returns: 是否成功删除
    func removeURL(url: String) -> Bool {
        guard var urls = loadURLs() else { return false }

        urls.removeAll { $0.url == url }
        return saveURLs(urls)
    }

    /// 清空所有 URL 并重新初始化为内置列表
    /// - Returns: 是否成功重置
    func reset() -> Bool {
        let builtinURLs = Config.getBuiltinURLs()
        return saveURLs(builtinURLs)
    }

    // MARK: - Private Methods

    private func loadURLs() -> [URLEntry]? {
        guard let data = storage.load(key: Self.storageKey) else {
            return nil
        }

        do {
            let urls = try JSONDecoder().decode([URLEntry].self, from: data)
            return urls
        } catch {
            Logger.shared.error("Failed to decode URLs: \(error)")
            return nil
        }
    }

    private func saveURLs(_ urls: [URLEntry]) -> Bool {
        do {
            let data = try JSONEncoder().encode(urls)
            return storage.save(data, forKey: Self.storageKey)
        } catch {
            Logger.shared.error("Failed to encode URLs: \(error)")
            return false
        }
    }
}
