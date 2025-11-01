import Foundation

/// URL 状态枚举
enum URLStatus: String, Codable {
    case untested   // 未测试
    case success    // 成功
    case failed     // 失败
}

/// URL 元数据 - 包含 URL 信息和测试统计
struct URLMetadata: Codable {
    let method: String
    let url: String
    let store: Bool
    var status: URLStatus
    var successCount: Int
    var failureCount: Int
    var lastTested: TimeInterval?     // Unix timestamp
    var lastSuccess: TimeInterval?    // Unix timestamp

    init(from entry: URLEntry) {
        self.method = entry.method
        self.url = entry.url
        self.store = entry.store
        self.status = .untested
        self.successCount = 0
        self.failureCount = 0
        self.lastTested = nil
        self.lastSuccess = nil
    }

    /// 转换为 URLEntry
    func toURLEntry() -> URLEntry {
        return URLEntry(method: method, url: url, store: store)
    }

    /// 记录成功
    mutating func recordSuccess() {
        status = .success
        successCount += 1
        let now = Date().timeIntervalSince1970
        lastTested = now
        lastSuccess = now
    }

    /// 记录失败
    mutating func recordFailure() {
        status = .failed
        failureCount += 1
        lastTested = Date().timeIntervalSince1970
    }
}

/// URL 管理器 - 负责 URL 列表的持久化存储和优先级排序
/// URL Manager - Thread-safe using Actor
actor URLManager {
    private static let storageKey = "passgfw.urls"
    private let storage: SecureStorage

    init(storage: SecureStorage) {
        self.storage = storage
    }

    /// 初始化 URL 列表（仅首次启动时调用）
    /// - Parameter builtinURLs: 内置的 URL 列表
    /// - Returns: 是否成功初始化
    func initializeIfNeeded() -> Bool {
        // 检查是否已经初始化
        if let _ = loadURLs() {
            return true  // 已经初始化过了
        }

        // 首次启动，使用内置 URLs 初始化
        let builtinURLs = Config.getBuiltinURLs()
        let metadata = builtinURLs.map { URLMetadata(from: $0) }
        return saveURLs(metadata)
    }

    /// 获取排序后的 URL 列表
    /// - Returns: 按优先级排序的 URLEntry 数组
    func getSortedURLs() -> [URLEntry] {
        guard var metadata = loadURLs() else {
            // 如果加载失败，返回内置 URLs
            return Config.getBuiltinURLs()
        }

        // 排序逻辑
        metadata.sort { lhs, rhs in
            // 1. 首先按 status 排序：success > untested > failed
            if lhs.status != rhs.status {
                switch (lhs.status, rhs.status) {
                case (.success, _):
                    return true
                case (_, .success):
                    return false
                case (.untested, .failed):
                    return true
                case (.failed, .untested):
                    return false
                default:
                    return false
                }
            }

            // 2. 同一 status，按 successCount 降序
            if lhs.successCount != rhs.successCount {
                return lhs.successCount > rhs.successCount
            }

            // 3. successCount 相同，按 lastSuccess 降序
            switch (lhs.lastSuccess, rhs.lastSuccess) {
            case (.some(let l), .some(let r)):
                return l > r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return false
            }
        }

        return metadata.map { $0.toURLEntry() }
    }

    /// 记录 URL 检测成功
    /// - Parameter url: 成功的 URL
    func recordSuccess(url: String) {
        guard var metadata = loadURLs() else { return }

        if let index = metadata.firstIndex(where: { $0.url == url }) {
            metadata[index].recordSuccess()
            _ = saveURLs(metadata)
        }
    }

    /// 记录 URL 检测失败
    /// - Parameter url: 失败的 URL
    func recordFailure(url: String) {
        guard var metadata = loadURLs() else { return }

        if let index = metadata.firstIndex(where: { $0.url == url }) {
            metadata[index].recordFailure()
            _ = saveURLs(metadata)
        }
    }

    /// 添加新的 URL（通过 list# 或 file# 动态添加）
    /// - Parameter entry: 要添加的 URLEntry
    /// - Returns: 是否成功添加
    func addURL(_ entry: URLEntry) -> Bool {
        var metadata = loadURLs() ?? []

        // 检查是否已存在
        if metadata.contains(where: { $0.url == entry.url }) {
            return true  // 已存在，不重复添加
        }

        // 添加新 URL
        metadata.append(URLMetadata(from: entry))
        return saveURLs(metadata)
    }

    /// 删除 URL（明确删除操作）
    /// - Parameter url: 要删除的 URL
    /// - Returns: 是否成功删除
    func removeURL(url: String) -> Bool {
        guard var metadata = loadURLs() else { return false }

        metadata.removeAll { $0.url == url }
        return saveURLs(metadata)
    }

    /// 清空所有 URL 并重新初始化为内置列表
    /// - Returns: 是否成功重置
    func reset() -> Bool {
        let builtinURLs = Config.getBuiltinURLs()
        let metadata = builtinURLs.map { URLMetadata(from: $0) }
        return saveURLs(metadata)
    }

    // MARK: - Private Methods

    private func loadURLs() -> [URLMetadata]? {
        guard let data = storage.load(key: Self.storageKey) else {
            return nil
        }

        do {
            let metadata = try JSONDecoder().decode([URLMetadata].self, from: data)
            return metadata
        } catch {
            Logger.shared.error("Failed to decode URL metadata: \(error)")
            return nil
        }
    }

    private func saveURLs(_ metadata: [URLMetadata]) -> Bool {
        do {
            let data = try JSONEncoder().encode(metadata)
            return storage.save(data, forKey: Self.storageKey)
        } catch {
            Logger.shared.error("Failed to encode URL metadata: \(error)")
            return false
        }
    }
}
