import Foundation
import Security

/// 管理 URL 的持久化存储（使用 Keychain 加密存储）
class URLStorageManager {
    static let shared = URLStorageManager()

    // Keychain 配置
    private let service = "com.passgfw.urls"
    private let account = "stored_urls"

    // 旧版本文件路径（用于数据迁移）
    private let legacyFileName = "passgfw_urls.json"
    private var legacyFileURL: URL?

    private init() {
        setupLegacyFileURL()
        // 启动时自动迁移旧数据
        migrateFromLegacyStorage()
    }

    /// 设置旧版本文件 URL（用于数据迁移）
    private func setupLegacyFileURL() {
        #if os(macOS)
        // macOS: 使用 Application Support 目录
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = appSupport.appendingPathComponent("PassGFW", isDirectory: true)
            legacyFileURL = appDir.appendingPathComponent(legacyFileName)
        }
        #else
        // iOS: 使用 Documents 目录
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            legacyFileURL = documents.appendingPathComponent(legacyFileName)
        }
        #endif
    }

    /// 从本地 Keychain 加载存储的 URL
    func loadStoredURLs() -> [URLEntry] {
        // 从 Keychain 读取数据
        guard let data = KeychainHelper.load(service: service, account: account) else {
            Logger.shared.debug("Keychain 中没有存储的 URL 数据")
            return []
        }

        do {
            let entries = try JSONDecoder().decode([URLEntry].self, from: data)
            Logger.shared.info("从 Keychain 加载了 \(entries.count) 个存储的 URL")
            return entries
        } catch {
            Logger.shared.error("从 Keychain 解析 URL 失败: \(error.localizedDescription)")
            return []
        }
    }

    /// 保存 URL 到 Keychain
    private func saveURLs(_ entries: [URLEntry]) -> Bool {
        do {
            let data = try JSONEncoder().encode(entries)

            if KeychainHelper.save(service: service, account: account, data: data) {
                Logger.shared.info("成功保存 \(entries.count) 个 URL 到 Keychain")
                return true
            } else {
                Logger.shared.error("保存 URL 到 Keychain 失败")
                return false
            }
        } catch {
            Logger.shared.error("编码 URL 失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 添加 URL 到存储（如果不存在）
    func addURL(_ entry: URLEntry) -> Bool {
        var entries = loadStoredURLs()

        // 检查是否已存在
        if entries.contains(where: { $0.url == entry.url }) {
            Logger.shared.debug("URL 已存在于存储中: \(entry.url)")
            return true // 已存在，视为成功
        }

        // 添加新条目
        entries.append(entry)
        Logger.shared.info("添加 URL 到存储: \(entry.url) (方法: \(entry.method))")

        return saveURLs(entries)
    }

    /// 从存储中删除 URL
    func removeURL(_ url: String) -> Bool {
        var entries = loadStoredURLs()
        let originalCount = entries.count

        // 删除匹配的 URL
        entries.removeAll { $0.url == url }

        if entries.count < originalCount {
            Logger.shared.info("从存储中删除 URL: \(url)")
            return saveURLs(entries)
        } else {
            Logger.shared.debug("URL 未在存储中找到: \(url)")
            return true // 未找到，但不算错误
        }
    }

    /// 清空所有存储的 URL
    func clearAll() -> Bool {
        Logger.shared.info("清空所有存储的 URL")

        // 从 Keychain 删除
        if KeychainHelper.delete(service: service, account: account) {
            return true
        } else {
            // 如果删除失败（可能是因为不存在），保存空数组
            return saveURLs([])
        }
    }

    /// 获取存储的 URL 数量
    func getCount() -> Int {
        return loadStoredURLs().count
    }

    // MARK: - 数据迁移

    /// 从旧版本的文件存储迁移到 Keychain
    private func migrateFromLegacyStorage() {
        // 检查 Keychain 是否已有数据
        if KeychainHelper.load(service: service, account: account) != nil {
            Logger.shared.debug("Keychain 已有数据，跳过迁移")
            // Keychain 已有数据，检查是否需要删除旧文件
            deleteLegacyFile()
            return
        }

        // 检查旧文件是否存在
        guard let fileURL = legacyFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            Logger.shared.debug("未找到旧版本存储文件，无需迁移")
            return
        }

        Logger.shared.info("检测到旧版本存储文件，开始数据迁移...")

        do {
            // 读取旧文件
            let data = try Data(contentsOf: fileURL)
            let entries = try JSONDecoder().decode([URLEntry].self, from: data)

            Logger.shared.info("从旧文件读取了 \(entries.count) 个 URL")

            // 保存到 Keychain
            if saveURLs(entries) {
                Logger.shared.info("✅ 数据迁移成功，已保存到 Keychain")

                // 验证迁移结果
                let verifyEntries = loadStoredURLs()
                if verifyEntries.count == entries.count {
                    Logger.shared.info("✅ 迁移验证成功")
                    // 删除旧文件
                    deleteLegacyFile()
                } else {
                    Logger.shared.error("⚠️ 迁移验证失败，保留旧文件以防数据丢失")
                }
            } else {
                Logger.shared.error("❌ 迁移失败，保留旧文件")
            }
        } catch {
            Logger.shared.error("读取旧文件失败: \(error.localizedDescription)")
        }
    }

    /// 删除旧版本的存储文件
    private func deleteLegacyFile() {
        guard let fileURL = legacyFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
            Logger.shared.info("已删除旧版本存储文件")
        } catch {
            Logger.shared.warning("删除旧文件失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - Keychain 辅助类

/// Keychain 操作辅助类
private class KeychainHelper {

    /// 保存数据到 Keychain
    /// - Parameters:
    ///   - service: 服务名称
    ///   - account: 账户名称
    ///   - data: 要保存的数据
    /// - Returns: 是否成功
    static func save(service: String, account: String, data: Data) -> Bool {
        // 先尝试更新
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        // 如果更新失败（可能是因为不存在），尝试添加
        if updateStatus == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        return false
    }

    /// 从 Keychain 加载数据
    /// - Parameters:
    ///   - service: 服务名称
    ///   - account: 账户名称
    /// - Returns: 数据，如果不存在则返回 nil
    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            return result as? Data
        }

        return nil
    }

    /// 从 Keychain 删除数据
    /// - Parameters:
    ///   - service: 服务名称
    ///   - account: 账户名称
    /// - Returns: 是否成功
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        // errSecItemNotFound 表示项不存在，也视为成功
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
