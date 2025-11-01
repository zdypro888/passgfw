import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Actor for thread-safe management of opened navigate URLs
private actor NavigateURLTracker {
    private var openedURLs: Set<String> = []

    func contains(_ url: String) -> Bool {
        return openedURLs.contains(url)
    }

    func insert(_ url: String) {
        openedURLs.insert(url)
    }
}

/// Actor for thread-safe cache and detection state management
private actor DetectionState {
    private var cachedDomain: String?
    private var cacheTimestamp: TimeInterval = 0
    private let cacheDuration: TimeInterval = 5 * 60 // 5分钟
    private var ongoingDetection: Task<String?, Never>?

    // 自动检测状态
    private var isAutoDetectionEnabled = false
    private var autoDetectionTask: Task<Void, Never>?

    func getCachedDomain() -> String? {
        guard let domain = cachedDomain else { return nil }
        let now = Date().timeIntervalSince1970
        if (now - cacheTimestamp) < cacheDuration {
            return domain
        }
        return nil
    }

    func getCachedDomainRaw() -> String? {
        return cachedDomain
    }

    func getRemainingCacheTime() -> Int {
        guard cachedDomain != nil else { return 0 }
        let now = Date().timeIntervalSince1970
        return Int(cacheDuration - (now - cacheTimestamp))
    }

    func setCachedDomain(_ domain: String) {
        cachedDomain = domain
        cacheTimestamp = Date().timeIntervalSince1970
    }

    func getOngoingDetection() -> Task<String?, Never>? {
        return ongoingDetection
    }

    func setOngoingDetection(_ task: Task<String?, Never>?) {
        ongoingDetection = task
    }

    // 自动检测相关方法
    func getIsAutoDetectionEnabled() -> Bool {
        return isAutoDetectionEnabled
    }

    func setAutoDetectionEnabled(_ enabled: Bool) {
        isAutoDetectionEnabled = enabled
    }

    func getAutoDetectionTask() -> Task<Void, Never>? {
        return autoDetectionTask
    }

    func setAutoDetectionTask(_ task: Task<Void, Never>?) {
        autoDetectionTask = task
    }

    // 原子操作：检查并启动自动检测
    func tryStartAutoDetection() -> Bool {
        if isAutoDetectionEnabled {
            return false  // 已经启动，返回false
        }
        isAutoDetectionEnabled = true
        return true  // 成功启动，返回true
    }

    // 原子操作：检查并停止自动检测
    func tryStopAutoDetection() -> Task<Void, Never>? {
        if !isAutoDetectionEnabled {
            return nil  // 未启动，返回nil
        }
        isAutoDetectionEnabled = false
        let task = autoDetectionTask
        autoDetectionTask = nil
        return task  // 返回需要取消的任务
    }

    // 原子操作：检查并获取或设置正在进行的检测
    // 返回值：如果已有检测任务，返回 (task, false)；如果设置了新任务，返回 (task, true)
    func getOrSetOngoingDetection(_ newTask: Task<String?, Never>) -> (task: Task<String?, Never>, isNew: Bool) {
        if let existing = ongoingDetection {
            return (existing, false)  // 已有检测任务，返回现有的
        }
        ongoingDetection = newTask
        return (newTask, true)  // 设置了新任务
    }

    // 清理正在进行的检测
    // 注意：调用者必须确保只有创建任务的线程才调用此方法
    func clearOngoingDetection() {
        ongoingDetection = nil
    }
}

/// Firewall Detector - Core detection logic
class FirewallDetector {
    private let networkClient: NetworkClient
    private let cryptoHelper: CryptoHelper
    private let urlManager: URLManager

    // 线程安全的错误信息存储
    private var _lastError: String?
    private let errorLock = NSLock()

    // 记录已打开的 navigate URLs，避免重复打开（使用 actor 确保线程安全）
    private let navigateTracker = NavigateURLTracker()

    // ========== 缓存机制 + 多线程调用保护（使用 Actor 确保 async-safe）==========
    private let detectionState = DetectionState()

    // 线程安全的访问器
    private var lastError: String? {
        get {
            errorLock.lock()
            defer { errorLock.unlock() }
            return _lastError
        }
        set {
            errorLock.lock()
            defer { errorLock.unlock() }
            _lastError = newValue
        }
    }

    init() {
        self.networkClient = NetworkClient()
        self.cryptoHelper = CryptoHelper()

        // Initialize URLManager with secure storage
        let storage = KeychainStorage()
        self.urlManager = URLManager(storage: storage)

        // Initialize crypto with public key
        _ = cryptoHelper.setPublicKey(pem: Config.getPublicKey())

        Logger.shared.info("FirewallDetector initialized")
    }
    
    /// Get final server domain (main entry point)
    ///
    /// 特性：
    /// 1. 缓存机制：5分钟内返回缓存结果
    /// 2. 多线程保护：多个线程调用时，只执行一次检测，其它等待
    /// 3. 立即返回：找到可用domain立即返回，后台异步记录
    /// 4. 自动检测模式：如果开启自动检测，优先返回缓存（后台自动更新）
    func getFinalServer(customData: String?) async -> String? {
        let isAutoEnabled = await detectionState.getIsAutoDetectionEnabled()
        Logger.shared.debug("getFinalServer() called with customData: \(customData ?? "nil"), autoDetection: \(isAutoEnabled)")

        // Initialize URL list if needed
        _ = await urlManager.initializeIfNeeded()

        // 自动检测模式：总是快速返回缓存（不管是否过期）或nil
        if isAutoEnabled {
            let cached = await detectionState.getCachedDomainRaw()
            if let cached = cached {
                Logger.shared.debug("自动检测模式：返回缓存的domain: \(cached)（后台自动更新中）")
                return cached
            } else {
                Logger.shared.debug("自动检测模式：缓存为空，返回nil（后台检测中）")
                return nil
            }
        }

        // 手动检测模式：检查有效缓存或执行检测
        if let validCache = await detectionState.getCachedDomain() {
            let remainingTime = await detectionState.getRemainingCacheTime()
            Logger.shared.debug("返回有效缓存的domain: \(validCache) (缓存还有 \(remainingTime)秒有效)")
            return validCache
        }

        // 需要执行检测：多线程调用保护
        // 双重检查：可能其它线程已经更新了缓存
        if let recheckCache = await detectionState.getCachedDomain() {
            Logger.shared.debug("其它线程已更新缓存: \(recheckCache)")
            return recheckCache
        }

        // 原子操作：检查并获取或创建检测任务
        let task = Task {
            await self.doDetection(customData: customData)
        }
        let (taskToWait, isNew) = await detectionState.getOrSetOngoingDetection(task)

        if !isNew {
            Logger.shared.debug("检测到正在进行的检测，等待其完成...")
            // 取消我们刚创建的任务（因为已有检测在进行）
            task.cancel()
        } else {
            Logger.shared.debug("开始新的检测流程")
        }

        // 在 Actor 外等待检测完成（不阻塞其他线程）
        let result = await taskToWait.value

        // 只有创建任务的线程才负责清理和更新缓存
        if isNew {
            await detectionState.clearOngoingDetection()

            if let result = result {
                // 更新缓存
                await detectionState.setCachedDomain(result)
                Logger.shared.info("检测成功，已缓存domain: \(result)")
            }
        }

        return result
    }

    /// 开启自动检测模式
    ///
    /// 开启后会每隔 intervalMinutes 分钟在后台自动检测一次，保持缓存始终有效
    /// getFinalServer() 调用将始终快速返回缓存结果
    ///
    /// - Parameters:
    ///   - customData: 自定义数据（传递给服务器）
    ///   - intervalMinutes: 检测间隔（分钟），默认4分钟
    func startAutoDetection(customData: String? = nil, intervalMinutes: Int = 4) {
        Task {
            // 原子检查并启动
            let canStart = await detectionState.tryStartAutoDetection()
            if !canStart {
                Logger.shared.debug("自动检测已经开启，忽略重复调用")
                return
            }

            Logger.shared.info("开启自动检测模式：间隔=\(intervalMinutes)分钟, customData=\(customData ?? "nil")")

            let intervalSeconds = TimeInterval(intervalMinutes * 60)

            // 启动定时检测任务
            let task = Task {
                // 立即执行一次检测（如果没有缓存）
                let cached = await self.detectionState.getCachedDomainRaw()
                if cached == nil {
                    Logger.shared.debug("首次自动检测...")
                    if let result = await self.doDetectionOnce(customData: customData) {
                        await self.detectionState.setCachedDomain(result)
                        Logger.shared.info("首次自动检测成功: \(result)")
                    } else {
                        Logger.shared.warning("首次自动检测失败，等待下次定时检测")
                    }
                }

                // 定时检测
                while await self.detectionState.getIsAutoDetectionEnabled() {
                    try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))

                    let isStillEnabled = await self.detectionState.getIsAutoDetectionEnabled()
                    if !isStillEnabled { break }

                    Logger.shared.debug("定时自动检测...")
                    if let result = await self.doDetectionOnce(customData: customData) {
                        await self.detectionState.setCachedDomain(result)
                        Logger.shared.info("自动检测成功: \(result)")
                    } else {
                        Logger.shared.warning("自动检测失败，保持旧缓存，等待下次检测")
                    }
                }
            }

            await detectionState.setAutoDetectionTask(task)
        }
    }

    /// 关闭自动检测模式
    ///
    /// 关闭后 getFinalServer() 恢复为手动检测模式（调用时才检测）
    func stopAutoDetection() {
        Task {
            // 原子检查并停止
            if let task = await detectionState.tryStopAutoDetection() {
                Logger.shared.info("关闭自动检测模式")
                task.cancel()
            } else {
                Logger.shared.debug("自动检测未开启，无需关闭")
            }
        }
    }

    /// 检查是否开启了自动检测模式
    func isAutoDetectionEnabled() async -> Bool {
        return await detectionState.getIsAutoDetectionEnabled()
    }

    /// 执行实际的检测逻辑（无限循环直到找到可用服务器）
    /// 用于手动检测模式
    private func doDetection(customData: String?) async -> String? {
        while true {
            let urls = await urlManager.getSortedURLs()
            Logger.shared.debug("Starting URL iteration with \(urls.count) sorted URLs")

            let domain: String? = if Config.enableConcurrentCheck {
                await checkURLsConcurrently(entries: urls, customData: customData, batchSize: Config.concurrentCheckCount)
            } else {
                await checkURLsSequentially(entries: urls, customData: customData)
            }

            if let domain = domain {
                return domain
            }

            lastError = "All URL detection failed, retrying..."
            Logger.shared.warning(lastError!)
            try? await Task.sleep(nanoseconds: UInt64(Config.retryInterval * 1_000_000_000))
        }
    }

    /// 执行一次检测（不重试）
    /// 用于自动检测模式
    private func doDetectionOnce(customData: String?) async -> String? {
        let urls = await urlManager.getSortedURLs()
        Logger.shared.debug("Starting URL detection (once) with \(urls.count) sorted URLs")

        let domain: String? = if Config.enableConcurrentCheck {
            await checkURLsConcurrently(entries: urls, customData: customData, batchSize: Config.concurrentCheckCount)
        } else {
            await checkURLsSequentially(entries: urls, customData: customData)
        }

        if let domain = domain {
            Logger.shared.info("Detection succeeded: \(domain)")
            return domain
        } else {
            Logger.shared.warning("Detection failed (all URLs failed)")
            return nil
        }
    }

    /// 串行检测 URLs（原逻辑）
    /// - Parameter recursionDepth: 递归深度（用于 file 方法递归调用）
    private func checkURLsSequentially(entries: [URLEntry], customData: String?, recursionDepth: Int = 0) async -> String? {
        for entry in entries {
            Logger.shared.debug("Checking URL: \(entry.url) (method: \(entry.method), depth: \(recursionDepth))")

            if let domain = await checkURLEntry(entry, customData: customData, recursionDepth: recursionDepth) {
                Logger.shared.info("Found available server: \(domain)")
                // 异步记录成功，不阻塞返回
                Task {
                    await self.urlManager.recordSuccess(url: entry.url)
                }
                return domain
            }

            // 异步记录失败，不阻塞下一个URL的检测
            Task {
                await self.urlManager.recordFailure(url: entry.url)
            }
            // 立即尝试下一个URL（无delay，追求最快响应）
        }
        return nil
    }

    /// 并发检测 URLs（批次间串行，批次内并发）
    /// 确保线程安全和顺序处理
    ///
    /// 重要：navigate、remove 等特殊方法始终串行执行
    /// 如果配置禁止 file 方法并发，file 也会串行执行
    ///
    /// - Parameter recursionDepth: 递归深度（用于 file 方法递归调用）
    private func checkURLsConcurrently(entries: [URLEntry], customData: String?, batchSize: Int, recursionDepth: Int = 0) async -> String? {
        // 边界检查：batchSize 必须 >= 1
        let safeBatchSize = max(1, batchSize)
        if batchSize <= 0 {
            Logger.shared.warning("并发批次大小无效 (\(batchSize))，已自动调整为 1")
        }

        // 分离特殊方法和普通方法
        // 特殊方法：navigate, remove 始终串行
        // 如果配置禁止 file 并发，file 也归入特殊方法
        var specialMethodsSet = Set(["navigate", "remove"])
        if !Config.fileMethodConcurrent {
            specialMethodsSet.insert("file")
        }

        let specialEntries = entries.filter { specialMethodsSet.contains($0.method.lowercased()) }
        let normalEntries = entries.filter { !specialMethodsSet.contains($0.method.lowercased()) }

        // 1. 先串行处理特殊方法（navigate, remove, file[如果禁止并发]）
        if !specialEntries.isEmpty {
            Logger.shared.debug("串行处理 \(specialEntries.count) 个特殊方法 URL（深度: \(recursionDepth)）")
            for entry in specialEntries {
                Logger.shared.debug("串行检测: \(entry.url) (method: \(entry.method), depth: \(recursionDepth))")

                if let domain = await checkURLEntry(entry, customData: customData, recursionDepth: recursionDepth) {
                    Logger.shared.info("Found available server: \(domain) (from \(entry.url))")
                    // 异步记录成功，立即返回
                    Task {
                        await self.urlManager.recordSuccess(url: entry.url)
                    }
                    return domain
                } else {
                    // 异步记录失败
                    Task {
                        await self.urlManager.recordFailure(url: entry.url)
                    }
                }
            }
        }

        // 2. 再并发处理普通方法（api, file）
        if normalEntries.isEmpty {
            return nil
        }

        Logger.shared.debug("并发处理 \(normalEntries.count) 个普通方法 URL（批次大小: \(safeBatchSize)）")

        // 按批次处理
        for batchStart in stride(from: 0, to: normalEntries.count, by: safeBatchSize) {
            let batchEnd = min(batchStart + safeBatchSize, normalEntries.count)
            let batch = Array(normalEntries[batchStart..<batchEnd])

            Logger.shared.debug("并发检测批次: [\(batchStart)..\(batchEnd-1)], 共 \(batch.count) 个 URL（深度: \(recursionDepth)）")

            // 批次内并发检测（竞赛模式：一旦有成功立即返回）
            let domain: String? = await withTaskGroup(of: (URLEntry, String?).self, returning: String?.self) { group in
                for entry in batch {
                    group.addTask {
                        let domain = await self.checkURLEntry(entry, customData: customData, recursionDepth: recursionDepth)
                        return (entry, domain)
                    }
                }

                // 竞赛模式：按完成顺序处理结果，找到成功后继续统计剩余结果
                var successDomain: String? = nil

                for await result in group {
                    let (entry, domain) = result

                    if let domain = domain {
                        if successDomain == nil {
                            // 第一个成功：立即取消未开始的任务
                            successDomain = domain
                            Logger.shared.info("Found available server: \(domain) (from \(entry.url))")
                            group.cancelAll()
                        }
                        // 记录成功（包括第一个和后续已完成的）
                        Task {
                            await self.urlManager.recordSuccess(url: entry.url)
                            Logger.shared.debug("统计：\(entry.url) 成功")
                        }
                    } else {
                        // 记录失败
                        Task {
                            await self.urlManager.recordFailure(url: entry.url)
                            Logger.shared.debug("统计：\(entry.url) 失败")
                        }
                    }
                }

                // 返回第一个成功的结果（如果有）
                return successDomain
            }

            if let domain = domain {
                return domain
            }
            // 批次失败，立即尝试下一批次（无delay，追求最快响应）
        }

        return nil
    }

    /// Add URL to list and persist to storage
    /// 重要：URL 会被持久化到 URLManager，确保重启后仍然可用
    func addURL(method: String, url: String) {
        let entry = URLEntry(method: method, url: url, store: false)
        Task {
            if await urlManager.addURL(entry) {
                Logger.shared.info("成功添加 URL 到存储: \(url)")
            } else {
                Logger.shared.error("添加 URL 失败: \(url)")
            }
        }
    }
    
    /// Get last error
    func getLastError() -> String? {
        return lastError
    }
    
    // MARK: - Private Methods
    
    /// Check a single URL entry
    private func checkURLEntry(_ entry: URLEntry, customData: String?, recursionDepth: Int) async -> String? {
        lastError = nil

        // Check recursion depth limit
        guard recursionDepth < Config.maxListRecursionDepth else {
            lastError = "Maximum list recursion depth exceeded: \(entry.url)"
            Logger.shared.error("Recursion depth limit reached (\(recursionDepth)) for URL: \(entry.url)")
            return nil
        }

        // Handle "remove" method - 从存储中删除 URL
        if entry.method.lowercased() == "remove" {
            Logger.shared.info("删除本地存储中的 URL: \(entry.url)")
            if await urlManager.removeURL(url: entry.url) {
                Logger.shared.info("成功删除 URL: \(entry.url)")
            } else {
                Logger.shared.warning("删除失败（URL 可能不存在）: \(entry.url)")
            }
            // 不检查此 URL，直接跳过
            return nil
        }

        // Handle "navigate" method - 打开浏览器
        if entry.method.lowercased() == "navigate" {
            // 检查是否已经打开过，避免重复打开（使用 actor 确保线程安全）
            let alreadyOpened = await navigateTracker.contains(entry.url)

            if alreadyOpened {
                Logger.shared.debug("Navigate URL 已打开过，跳过: \(entry.url)")
                return nil
            }

            Logger.shared.info("打开浏览器导航到: \(entry.url)")

            // 尝试打开浏览器
            if let url = URL(string: entry.url) {
                #if canImport(UIKit)
                // iOS
                UIApplication.shared.open(url)
                Logger.shared.info("已在 iOS 默认浏览器中打开: \(entry.url)")
                #elseif canImport(AppKit)
                // macOS
                NSWorkspace.shared.open(url)
                Logger.shared.info("已在 macOS 默认浏览器中打开: \(entry.url)")
                #endif

                // 记录已打开（使用 actor 确保线程安全）
                await navigateTracker.insert(entry.url)
            } else {
                Logger.shared.error("Navigate URL 格式无效: \(entry.url)")
            }

            // 打开浏览器后继续检测下一个 URL
            return nil
        }

        // Dispatch based on method
        var result: String? = nil

        switch entry.method.lowercased() {
        case "api":
            result = await checkAPIURL(entry.url, customData: customData, recursionDepth: recursionDepth)
        case "file":
            result = await checkFileURL(entry.url, customData: customData, recursionDepth: recursionDepth)
        default:
            lastError = "Unknown method: \(entry.method)"
            Logger.shared.error("未知的 method '\(entry.method)' for URL: \(entry.url)")
            return nil
        }

        // 如果检查成功且 store=true，则异步持久化存储此 URL（不阻塞返回）
        if result != nil, entry.store == true {
            let storedEntry = URLEntry(method: entry.method, url: entry.url, store: false)

            // 后台异步存储，不阻塞返回
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                Logger.shared.info("后台存储检测成功的 URL: \(entry.url) (method: \(entry.method))")
                if await self.urlManager.addURL(storedEntry) {
                    Logger.shared.info("成功存储 URL: \(entry.url)")
                } else {
                    Logger.shared.error("存储 URL 失败: \(entry.url)")
                }
            }
        }

        return result
    }
    
    /// Check an API URL with retry mechanism
    private func checkAPIURL(_ url: String, customData: String?, recursionDepth: Int) async -> String? {
        Logger.shared.debug("CheckAPIURL() called for: \(url) with customData: \(customData ?? "nil")")

        guard !url.isEmpty else {
            lastError = "Empty URL provided"
            return nil
        }

        // Retry loop
        for attempt in 1...Config.maxRetries {
            Logger.shared.debug("Attempt \(attempt)/\(Config.maxRetries) for URL: \(url)")

            if let domain = await checkAPIURLOnce(url, customData: customData, recursionDepth: recursionDepth) {
                Logger.shared.info("Successfully verified URL: \(url) on attempt \(attempt)")
                return domain
            }

            // If this was the last attempt, give up
            if attempt == Config.maxRetries {
                Logger.shared.warning("All \(Config.maxRetries) attempts failed for URL: \(url). Last error: \(lastError ?? "unknown")")
                return nil
            }

            // Wait before retry
            Logger.shared.debug("Waiting \(Config.retryDelay)s before retry...")
            try? await Task.sleep(nanoseconds: UInt64(Config.retryDelay * 1_000_000_000))
        }

        return nil
    }
    
    /// Check an API URL once (no retry)
    private func checkAPIURLOnce(_ url: String, customData: String?, recursionDepth: Int) async -> String? {
        // 1. Generate random nonce
        guard let randomData = cryptoHelper.generateRandom(length: Config.nonceSize) else {
            lastError = "Failed to generate random data"
            return nil
        }
        let randomBase64 = randomData.base64EncodedString()
        Logger.shared.debug("Generated random data: \(randomData.count) bytes")

        // 2. Truncate custom data if too long
        var clientData = customData ?? ""
        if clientData.count > Config.maxClientDataSize {
            Logger.shared.warning("client_data truncated from \(clientData.count) to \(Config.maxClientDataSize) bytes")
            clientData = String(clientData.prefix(Config.maxClientDataSize))
        }

        // 3. Build JSON payload
        let payload: [String: String] = [
            "nonce": randomBase64,
            "client_data": clientData
        ]

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            lastError = "Failed to construct payload JSON"
            return nil
        }
        Logger.shared.debug("Payload JSON: \(payloadJSON)")

        // 4. Encrypt payload
        guard let payloadBytes = payloadJSON.data(using: .utf8),
              let encryptedData = cryptoHelper.encrypt(data: payloadBytes) else {
            lastError = "Failed to encrypt data"
            return nil
        }
        let encryptedBase64 = encryptedData.base64EncodedString()
        Logger.shared.debug("Encrypted data: \(encryptedData.count) bytes")

        // 5. Build request JSON
        let requestData: [String: String] = ["data": encryptedBase64]
        guard let requestJSON = try? JSONSerialization.data(withJSONObject: requestData),
              let requestBody = String(data: requestJSON, encoding: .utf8) else {
            lastError = "Failed to construct request JSON"
            return nil
        }

        // 6. POST request
        let response = await networkClient.post(url: url, jsonBody: requestBody)
        guard response.success else {
            lastError = "POST request failed: \(url) - \(response.error ?? "unknown")"
            return nil
        }

        // 7. Parse response JSON
        guard let responseData = response.body.data(using: .utf8),
              let responseJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let returnedRandom = responseJSON["random"] as? String,
              let signature = responseJSON["signature"] as? String else {
            lastError = "Failed to parse response JSON or missing required fields (random/signature)"
            return nil
        }

        // domain 和 urls 都是可选的
        let returnedDomain = responseJSON["domain"] as? String

        Logger.shared.debug("Returned random: \(returnedRandom)")
        if let domain = returnedDomain {
            Logger.shared.debug("Returned domain: \(domain)")
        }

        // 8. Verify signature (sign response without signature field)
        // CRITICAL: Must use sorted keys to match server serialization
        var payloadForSigning = responseJSON
        payloadForSigning.removeValue(forKey: "signature")

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payloadForSigning, options: [.sortedKeys]) else {
            lastError = "Failed to serialize payload for verification"
            return nil
        }

        if let payloadString = String(data: payloadData, encoding: .utf8) {
            Logger.shared.debug("Payload for verification: \(payloadString)")
        }

        guard let signatureData = Data(base64Encoded: signature),
              cryptoHelper.verifySignature(data: payloadData, signature: signatureData) else {
            lastError = "Signature verification failed"
            return nil
        }

        // 9. Verify random matches
        guard returnedRandom == randomBase64 else {
            let expectedPrefix = String(randomBase64.prefix(10))
            let actualPrefix = String(returnedRandom.prefix(10))
            lastError = "Random mismatch: expected: \(expectedPrefix)..., actual: \(actualPrefix)..."
            return nil
        }

        // 10. 处理服务器返回的 urls 数组（如果有）
        if let urlsData = responseJSON["urls"] as? [[String: Any]] {
            Logger.shared.debug("Server returned \(urlsData.count) URLs in response")

            var urlEntries: [URLEntry] = []
            for urlDict in urlsData {
                if let method = urlDict["method"] as? String,
                   let url = urlDict["url"] as? String {
                    let store = urlDict["store"] as? Bool ?? false
                    urlEntries.append(URLEntry(method: method, url: url, store: store))
                }
            }

            // 策略：如果有 domain，说明服务器可信，异步存储 store=true 的 URL（不阻塞返回）
            if returnedDomain != nil {
                for entry in urlEntries where entry.store == true {
                    let storedEntry = URLEntry(method: entry.method, url: entry.url, store: false)
                    // 后台异步存储，不阻塞返回
                    Task.detached(priority: .background) { [weak self] in
                        guard let self = self else { return }
                        Logger.shared.info("后台存储服务器推荐的 URL: \(entry.url) (method: \(entry.method))")
                        if await self.urlManager.addURL(storedEntry) {
                            Logger.shared.info("成功存储 URL: \(entry.url)")
                        } else {
                            Logger.shared.error("存储 URL 失败: \(entry.url)")
                        }
                    }
                }
            } else {
                // 没有 domain，循环检测 urls，只存储检测成功的
                Logger.shared.debug("No domain in response, checking URLs from server...")

                for entry in urlEntries {
                    Logger.shared.debug("Checking server-provided URL: \(entry.url) (method: \(entry.method))")

                    if let domain = await checkURLEntry(entry, customData: customData, recursionDepth: recursionDepth + 1) {
                        Logger.shared.info("Server-provided URL succeeded: \(entry.url) -> \(domain)")

                        // 检测成功，异步存储（不阻塞返回）
                        if entry.store == true {
                            let storedEntry = URLEntry(method: entry.method, url: entry.url, store: false)
                            Task.detached(priority: .background) { [weak self] in
                                guard let self = self else { return }
                                Logger.shared.info("后台存储检测成功的 URL: \(entry.url)")
                                _ = await self.urlManager.addURL(storedEntry)
                            }
                        }

                        return domain
                    }

                    Logger.shared.debug("Server-provided URL failed: \(entry.url), trying next...")
                    try? await Task.sleep(nanoseconds: UInt64(Config.urlInterval * 1_000_000_000))
                }

                lastError = "All server-provided URLs failed"
                return nil
            }
        }

        // 11. 如果有 domain，返回它
        if let domain = returnedDomain {
            Logger.shared.debug("Verification successful! Using domain: \(domain)")
            return domain
        }

        // 既没有 domain 也没有 urls
        lastError = "Response has neither domain nor urls"
        return nil
    }
    
    /// Check a file URL (fetch sub-list and check each URL)
    /// ✅ 完美递归：子 URL 列表会根据配置使用并发或串行检测
    private func checkFileURL(_ url: String, customData: String?, recursionDepth: Int) async -> String? {
        Logger.shared.debug("CheckFileURL() called for: \(url) (depth: \(recursionDepth))")

        guard !url.isEmpty else {
            lastError = "Empty file URL provided"
            return nil
        }

        // Fetch sub-list
        Logger.shared.debug("Fetching sub-list from: \(url)")
        let response = await networkClient.get(url: url)

        guard response.success else {
            lastError = "GET request failed: \(url) - \(response.error ?? "unknown")"
            return nil
        }

        // Try to parse as JSON first (new format with urls array)
        if let subEntries = parseURLEntriesJSON(content: response.body), !subEntries.isEmpty {
            // ✅ 去重：使用 URL 作为唯一标识（保留第一个出现的 URLEntry）
            var seenURLs = Set<String>()
            let uniqueEntries = subEntries.filter { entry in
                if seenURLs.contains(entry.url) {
                    return false
                } else {
                    seenURLs.insert(entry.url)
                    return true
                }
            }

            let duplicateCount = subEntries.count - uniqueEntries.count
            if duplicateCount > 0 {
                Logger.shared.warning("去重：从 file 子列表中移除了 \(duplicateCount) 个重复 URL")
            }

            Logger.shared.debug("Fetched \(uniqueEntries.count) unique URL entries from JSON sub-list")

            // ✅ 递归调用并发检测逻辑（保持一致性）
            if Config.enableConcurrentCheck {
                Logger.shared.debug("使用并发模式检测子 URL 列表（深度 \(recursionDepth + 1)）")
                return await checkURLsConcurrently(entries: uniqueEntries, customData: customData, batchSize: Config.concurrentCheckCount, recursionDepth: recursionDepth + 1)
            } else {
                Logger.shared.debug("使用串行模式检测子 URL 列表（深度 \(recursionDepth + 1)）")
                return await checkURLsSequentially(entries: uniqueEntries, customData: customData, recursionDepth: recursionDepth + 1)
            }
        }

        // Fallback: parse as plain text URL list (legacy format)
        let subURLs = parseURLList(content: response.body)
        guard !subURLs.isEmpty else {
            lastError = "Sub-list empty or parse failed: \(url)"
            return nil
        }

        // ✅ 去重：移除重复的 URL
        let uniqueURLs = Array(Set(subURLs))
        let duplicateCount = subURLs.count - uniqueURLs.count

        if duplicateCount > 0 {
            Logger.shared.warning("去重：从 file 子列表中移除了 \(duplicateCount) 个重复 URL (legacy format)")
        }

        Logger.shared.debug("Fetched \(uniqueURLs.count) unique URLs from text sub-list (legacy format)")

        // Convert to URLEntry list (assume API method)
        let entries = uniqueURLs.map { URLEntry(method: "api", url: $0) }

        // ✅ 递归调用并发检测逻辑
        if Config.enableConcurrentCheck {
            Logger.shared.debug("使用并发模式检测子 URL 列表（深度 \(recursionDepth + 1)）")
            return await checkURLsConcurrently(entries: entries, customData: customData, batchSize: Config.concurrentCheckCount, recursionDepth: recursionDepth + 1)
        } else {
            Logger.shared.debug("使用串行模式检测子 URL 列表（深度 \(recursionDepth + 1)）")
            return await checkURLsSequentially(entries: entries, customData: customData, recursionDepth: recursionDepth + 1)
        }
    }
    
    /// 智能解析 URL entries（支持多种格式）
    /// Supports:
    /// 1. *PGFW*base64(URLEntry[] JSON)*PGFW* format (preferred, can embed anywhere including HTML)
    /// 2. Direct URLEntry[] JSON array format
    /// 3. Legacy {"urls": [...]} format
    /// 4. HTML with <pre>, <code>, or <script type="application/json"> tags
    private func parseURLEntriesJSON(content: String) -> [URLEntry]? {
        Logger.shared.debug("开始智能解析内容（长度: \(content.count)）")

        // 策略1: 尝试提取 *PGFW*base64*PGFW* 标记（优先级最高，可嵌入任何格式）
        if let extracted = extractPGFWContent(from: content) {
            Logger.shared.info("✓ 检测到 *PGFW* 标记格式")

            guard let decodedData = Data(base64Encoded: extracted),
                  let decodedString = String(data: decodedData, encoding: .utf8) else {
                Logger.shared.warning("× Base64 解码失败")
                return nil
            }

            Logger.shared.debug("解码内容: \(decodedString.prefix(200))...")

            if let entries = parseURLEntryArray(json: decodedString) {
                Logger.shared.info("✓ 成功解析 *PGFW* 格式，获得 \(entries.count) 个 URL")
                return entries
            }
        }

        // 策略2: 检测是否为 HTML，提取特定标签内容
        if content.contains("<html") || content.contains("<!DOCTYPE") {
            Logger.shared.info("✓ 检测到 HTML 格式，尝试提取内容...")

            // 尝试提取 <pre> 标签内容
            if let preContent = extractHTMLTag(from: content, tag: "pre") {
                Logger.shared.debug("从 <pre> 标签提取到内容")
                if let entries = parseURLEntryArray(json: preContent) {
                    Logger.shared.info("✓ 成功从 HTML <pre> 解析，获得 \(entries.count) 个 URL")
                    return entries
                }
            }

            // 尝试提取 <code> 标签内容
            if let codeContent = extractHTMLTag(from: content, tag: "code") {
                Logger.shared.debug("从 <code> 标签提取到内容")
                if let entries = parseURLEntryArray(json: codeContent) {
                    Logger.shared.info("✓ 成功从 HTML <code> 解析，获得 \(entries.count) 个 URL")
                    return entries
                }
            }

            // 尝试提取 <script type="application/json"> 内容
            if let scriptContent = extractJSONScript(from: content) {
                Logger.shared.debug("从 <script> 标签提取到 JSON")
                if let entries = parseURLEntryArray(json: scriptContent) {
                    Logger.shared.info("✓ 成功从 HTML <script> 解析，获得 \(entries.count) 个 URL")
                    return entries
                }
            }

            Logger.shared.warning("× HTML 中未找到有效的 URL 数据")
        }

        // 策略3: 尝试直接解析为 URLEntry[] JSON 数组
        if let entries = parseURLEntryArray(json: content) {
            Logger.shared.info("✓ 成功解析为直接 JSON 数组，获得 \(entries.count) 个 URL")
            return entries
        }

        // 策略4: 尝试 legacy {"urls": [...]} 格式
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let urlsArray = json["urls"] as? [[String: String]] {

            var entries: [URLEntry] = []
            for urlDict in urlsArray {
                if let method = urlDict["method"], let url = urlDict["url"] {
                    let store = urlDict["store"] == "true" || urlDict["store"] == "1"
                    entries.append(URLEntry(method: method, url: url, store: store))
                }
            }

            if !entries.isEmpty {
                Logger.shared.info("✓ 成功解析为 Legacy 格式，获得 \(entries.count) 个 URL")
                return entries
            }
        }

        Logger.shared.warning("× 所有 JSON 解析策略均失败")
        return nil
    }

    /// 从 HTML 中提取指定标签的内容
    private func extractHTMLTag(from html: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let contentRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        let content = String(html[contentRange])
        // 解码 HTML entities
        return content
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从 HTML 中提取 <script type="application/json"> 的内容
    private func extractJSONScript(from html: String) -> String? {
        let pattern = "<script[^>]*type=[\"']application/json[\"'][^>]*>(.*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let contentRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extract content between *PGFW* markers
    private func extractPGFWContent(from text: String) -> String? {
        let startMarker = "*PGFW*"
        let endMarker = "*PGFW*"
        
        guard let startRange = text.range(of: startMarker),
              let endRange = text.range(of: endMarker, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        
        let content = String(text[startRange.upperBound..<endRange.lowerBound])
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Parse URLEntry[] JSON array
    private func parseURLEntryArray(json: String) -> [URLEntry]? {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        
        var entries: [URLEntry] = []
        for dict in array {
            if let method = dict["method"] as? String,
               let url = dict["url"] as? String {
                entries.append(URLEntry(method: method, url: url))
            }
        }
        
        return entries.isEmpty ? nil : entries
    }
    
    /// Parse URL list from text content
    private func parseURLList(content: String) -> [String] {
        var urls: [String] = []
        
        // Try to extract content between *GFW* markers
        let marker = "*GFW*"
        if let startRange = content.range(of: marker),
           let endRange = content.range(of: marker, range: startRange.upperBound..<content.endIndex) {
            let gfwContent = String(content[startRange.upperBound..<endRange.lowerBound])
            let trimmed = gfwContent.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !trimmed.isEmpty {
                // Parse URLs from marked content
                let lines = trimmed.components(separatedBy: .newlines)
                for line in lines {
                    let url = line.trimmingCharacters(in: .whitespaces)
                    if !url.isEmpty && !url.hasPrefix("#") {
                        urls.append(url)
                    }
                }
                return urls
            }
        }
        
        // If no markers found, parse entire content
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let url = line.trimmingCharacters(in: .whitespaces)
            if !url.isEmpty && !url.hasPrefix("#") {
                urls.append(url)
            }
        }
        
        return urls
    }
}

