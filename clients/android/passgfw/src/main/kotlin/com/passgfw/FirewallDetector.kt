package com.passgfw

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.Job
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Firewall Detector - Core detection logic
 */
class FirewallDetector(private val context: Context) {
    private val networkClient = NetworkClient()
    private val cryptoHelper = CryptoHelper()
    private val urlManager: URLManager

    // 使用 AtomicReference 确保线程安全
    private val lastError = AtomicReference<String?>(null)

    // 协程作用域用于异步存储操作
    private val storageScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // 记录已打开的 navigate URLs，避免重复打开（使用线程安全的 ConcurrentHashMap.KeySetView）
    private val openedNavigateURLs = ConcurrentHashMap.newKeySet<String>()

    // ========== 缓存机制 ==========
    @Volatile
    private var cachedDomain: String? = null
    @Volatile
    private var cacheTimestamp: Long = 0
    private val CACHE_DURATION_MS = 5 * 60 * 1000L // 5分钟缓存
    private val cacheLock = Any()  // 缓存更新锁，保证原子性

    // ========== 多线程调用保护 ==========
    private val detectionMutex = Mutex()
    @Volatile
    private var ongoingDetection: Deferred<String?>? = null

    // ========== 自动检测机制 ==========
    private val autoDetectionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    @Volatile
    private var autoDetectionJob: kotlinx.coroutines.Job? = null
    @Volatile
    private var isAutoDetectionEnabled = false
    @Volatile
    private var autoDetectionCustomData: String? = null
    private val autoDetectionInterval = 4 * 60 * 1000L // 4分钟自动检测一次
    private val autoDetectionLock = Any()  // 自动检测启动锁

    init {
        // Initialize URLManager with secure storage
        val storage = EncryptedStorage(context)
        urlManager = URLManager(storage)

        // Initialize URL list (first time will use builtin URLs)
        urlManager.initializeIfNeeded()

        // Initialize crypto with public key
        cryptoHelper.setPublicKey(Config.getPublicKey())

        Logger.info("FirewallDetector initialized")
    }
    
    /**
     * Get final server domain (main entry point)
     *
     * 特性：
     * 1. 缓存机制：5分钟内返回缓存结果
     * 2. 多线程保护：多个线程调用时，只执行一次检测，其它等待
     * 3. 立即返回：找到可用domain立即返回，后台异步记录
     * 4. 自动检测模式：如果开启自动检测，优先返回缓存（后台自动更新）
     */
    suspend fun getFinalServer(customData: String?): String? {
        Logger.debug("getFinalServer() called with customData: $customData, autoDetection: $isAutoDetectionEnabled")

        // 自动检测模式：总是快速返回缓存（不管是否过期）或null
        if (isAutoDetectionEnabled) {
            val cached = cachedDomain  // 读取最新缓存
            if (cached != null) {
                Logger.debug("自动检测模式：返回缓存的domain: $cached（后台自动更新中）")
                return cached
            } else {
                Logger.debug("自动检测模式：缓存为空，返回null（后台检测中）")
                return null
            }
        }

        // 手动检测模式：检查有效缓存或执行检测
        // 使用synchronized确保读取cachedDomain和cacheTimestamp的原子性
        val validCache = synchronized(cacheLock) {
            val domain = cachedDomain
            if (domain != null && (System.currentTimeMillis() - cacheTimestamp < CACHE_DURATION_MS)) {
                domain
            } else {
                null
            }
        }

        if (validCache != null) {
            Logger.debug("返回有效缓存的domain: $validCache")
            return validCache
        }

        // 需要执行检测：多线程调用保护
        // 1. 在锁内获取或创建 deferred（原子操作）
        val deferredToWait = detectionMutex.withLock {
            // 双重检查：可能其它线程已经更新了缓存
            val recheckCache = synchronized(cacheLock) {
                val domain = cachedDomain
                if (domain != null && (System.currentTimeMillis() - cacheTimestamp < CACHE_DURATION_MS)) {
                    domain
                } else {
                    null
                }
            }

            if (recheckCache != null) {
                Logger.debug("其它线程已更新缓存: $recheckCache")
                return recheckCache
            }

            // 检查是否有正在进行的检测（原子检查）
            ongoingDetection?.let {
                Logger.debug("检测到正在进行的检测，等待其完成...")
                return@withLock it
            }

            // 开始新的检测
            Logger.debug("开始新的检测流程")
            val deferred = storageScope.async {
                doDetection(customData)
            }
            ongoingDetection = deferred
            deferred
        }

        // 2. 在锁外等待检测完成（不阻塞其他线程）
        val result = try {
            deferredToWait.await()
        } finally {
            // 3. 清理 ongoingDetection（只清理自己创建的）
            detectionMutex.withLock {
                if (ongoingDetection == deferredToWait) {
                    ongoingDetection = null
                }
            }
        }

        // 4. 更新缓存
        if (result != null) {
            synchronized(cacheLock) {
                cachedDomain = result
                cacheTimestamp = System.currentTimeMillis()
            }
            Logger.info("检测成功，已缓存domain: $result")
        }

        return result
    }

    /**
     * 开启自动检测模式
     *
     * 开启后会每隔 intervalMinutes 分钟在后台自动检测一次，保持缓存始终有效
     * getFinalServer() 调用将始终快速返回缓存结果
     *
     * @param customData 自定义数据（传递给服务器）
     * @param intervalMinutes 检测间隔（分钟），默认4分钟
     */
    fun startAutoDetection(customData: String? = null, intervalMinutes: Int = 4) {
        synchronized(autoDetectionLock) {
            if (isAutoDetectionEnabled) {
                Logger.debug("自动检测已经开启，忽略重复调用")
                return
            }

            Logger.info("开启自动检测模式：间隔=${intervalMinutes}分钟, customData=$customData")
            isAutoDetectionEnabled = true
            autoDetectionCustomData = customData

            val intervalMs = intervalMinutes * 60 * 1000L

            // 启动定时检测任务
            autoDetectionJob = autoDetectionScope.launch {
                // 立即执行一次检测（如果没有缓存）
                // 使用 synchronized 保护 cachedDomain 读取
                val needsInitialDetection = synchronized(cacheLock) {
                    cachedDomain == null
                }

                if (needsInitialDetection) {
                    Logger.debug("首次自动检测...")
                    try {
                        val result = doDetectionOnce(customData)
                        if (result != null) {
                            // 原子更新缓存
                            synchronized(cacheLock) {
                                cachedDomain = result
                                cacheTimestamp = System.currentTimeMillis()
                            }
                            Logger.info("首次自动检测成功: $result")
                        } else {
                            Logger.warning("首次自动检测失败，等待下次定时检测")
                        }
                    } catch (e: Exception) {
                        Logger.error("首次自动检测异常: ${e.message}")
                    }
                }

                // 定时检测
                while (isAutoDetectionEnabled) {
                    delay(intervalMs)
                    if (!isAutoDetectionEnabled) break

                    Logger.debug("定时自动检测...")
                    try {
                        val result = doDetectionOnce(customData)
                        if (result != null) {
                            // 原子更新缓存
                            synchronized(cacheLock) {
                                cachedDomain = result
                                cacheTimestamp = System.currentTimeMillis()
                            }
                            Logger.info("自动检测成功: $result")
                        } else {
                            Logger.warning("自动检测失败，保持旧缓存，等待下次检测")
                        }
                    } catch (e: Exception) {
                        Logger.error("自动检测异常: ${e.message}")
                    }
                }
            }
        }
    }

    /**
     * 关闭自动检测模式
     *
     * 关闭后 getFinalServer() 恢复为手动检测模式（调用时才检测）
     */
    fun stopAutoDetection() {
        synchronized(autoDetectionLock) {
            if (!isAutoDetectionEnabled) {
                Logger.debug("自动检测未开启，无需关闭")
                return
            }

            Logger.info("关闭自动检测模式")
            isAutoDetectionEnabled = false
            autoDetectionJob?.cancel()
            autoDetectionJob = null
            autoDetectionCustomData = null
        }
    }

    /**
     * 检查是否开启了自动检测模式
     */
    fun isAutoDetectionEnabled(): Boolean {
        return isAutoDetectionEnabled
    }

    /**
     * 执行实际的检测逻辑（无限循环直到找到可用服务器）
     * 用于手动检测模式
     */
    private suspend fun doDetection(customData: String?): String? {
        while (true) {
            // Reload sorted URLs at the beginning of each cycle to get latest priorities
            val urls = urlManager.getSortedURLs()
            Logger.debug("Starting URL iteration with ${urls.size} sorted URLs")

            val domain = if (Config.ENABLE_CONCURRENT_CHECK) {
                checkURLsConcurrently(urls, customData, Config.CONCURRENT_CHECK_COUNT)
            } else {
                checkURLsSequentially(urls, customData)
            }

            if (domain != null) {
                return domain
            }

            // All URLs failed, wait and retry
            val errorMsg = "All URL detection failed, retrying..."
            lastError.set(errorMsg)
            Logger.warning(errorMsg)
            delay(Config.RETRY_INTERVAL)
        }
    }

    /**
     * 执行一次检测（不重试）
     * 用于自动检测模式
     */
    private suspend fun doDetectionOnce(customData: String?): String? {
        // Reload sorted URLs
        val urls = urlManager.getSortedURLs()
        Logger.debug("Starting URL detection (once) with ${urls.size} sorted URLs")

        val domain = if (Config.ENABLE_CONCURRENT_CHECK) {
            checkURLsConcurrently(urls, customData, Config.CONCURRENT_CHECK_COUNT)
        } else {
            checkURLsSequentially(urls, customData)
        }

        if (domain != null) {
            Logger.info("Detection succeeded: $domain")
            return domain
        } else {
            Logger.warning("Detection failed (all URLs failed)")
            return null
        }
    }

    /**
     * 串行检测 URLs（原逻辑）
     * @param recursionDepth 递归深度（用于 file 方法递归调用）
     */
    private suspend fun checkURLsSequentially(
        entries: List<URLEntry>,
        customData: String?,
        recursionDepth: Int = 0
    ): String? {
        for (entry in entries) {
            Logger.debug("Checking URL: ${entry.url} (method: ${entry.method}, depth: $recursionDepth)")

            checkURLEntry(entry, customData, recursionDepth)?.let { domain ->
                Logger.info("Found available server: $domain")
                // 异步记录成功，不阻塞返回
                storageScope.launch {
                    urlManager.recordSuccess(entry.url)
                }
                return domain
            }

            // 异步记录失败，不阻塞下一个URL的检测
            storageScope.launch {
                urlManager.recordFailure(entry.url)
            }
        }
        return null
    }

    /**
     * 并发检测 URLs（批次间串行，批次内并发）
     * 确保线程安全和顺序处理
     *
     * 重要：navigate、remove 等特殊方法始终串行执行
     * 如果配置禁止 file 方法并发，file 也会串行执行
     *
     * @param recursionDepth 递归深度（用于 file 方法递归调用）
     */
    private suspend fun checkURLsConcurrently(
        entries: List<URLEntry>,
        customData: String?,
        batchSize: Int,
        recursionDepth: Int = 0
    ): String? = coroutineScope {
        // 边界检查：batchSize 必须 >= 1
        val safeBatchSize = maxOf(1, batchSize)
        if (batchSize <= 0) {
            Logger.warning("并发批次大小无效 ($batchSize)，已自动调整为 1")
        }

        // 分离特殊方法和普通方法
        // 特殊方法：navigate, remove 始终串行
        // 如果配置禁止 file 并发，file 也归入特殊方法
        val specialMethods = buildSet {
            add("navigate")
            add("remove")
            if (!Config.FILE_METHOD_CONCURRENT) {
                add("file")
            }
        }

        val (specialEntries, normalEntries) = entries.partition {
            specialMethods.contains(it.method.lowercase())
        }

        // 1. 先串行处理特殊方法（navigate, remove, file[如果禁止并发]）
        if (specialEntries.isNotEmpty()) {
            Logger.debug("串行处理 ${specialEntries.size} 个特殊方法 URL（深度: $recursionDepth）")
            for (entry in specialEntries) {
                Logger.debug("串行检测: ${entry.url} (method: ${entry.method}, depth: $recursionDepth)")

                val domain = checkURLEntry(entry, customData, recursionDepth)
                if (domain != null) {
                    Logger.info("Found available server: $domain (from ${entry.url})")
                    // 异步记录成功，立即返回
                    storageScope.launch {
                        urlManager.recordSuccess(entry.url)
                    }
                    return@coroutineScope domain
                } else {
                    // 异步记录失败
                    storageScope.launch {
                        urlManager.recordFailure(entry.url)
                    }
                }
            }
        }

        // 2. 再并发处理普通方法（api, file）
        if (normalEntries.isEmpty()) {
            return@coroutineScope null
        }

        Logger.debug("并发处理 ${normalEntries.size} 个普通方法 URL（批次大小: $safeBatchSize）")

        // 按批次处理
        for (batchStart in normalEntries.indices step safeBatchSize) {
            val batchEnd = minOf(batchStart + safeBatchSize, normalEntries.size)
            val batch = normalEntries.subList(batchStart, batchEnd)

            Logger.debug("并发检测批次: [${batchStart}..${batchEnd-1}], 共 ${batch.size} 个 URL（深度: $recursionDepth）")

            // 批次内并发检测（竞赛模式：一旦有成功立即返回）
            // 使用 Channel 收集结果，避免 awaitAll() 的阻塞等待
            val resultChannel = Channel<Pair<URLEntry, String?>>(Channel.UNLIMITED)

            // 启动所有检测任务（使用 try-catch 保护 send 操作）
            val jobs = batch.map { entry ->
                launch(Dispatchers.IO) {
                    val domain = checkURLEntry(entry, customData, recursionDepth)
                    // 安全发送：channel 可能已关闭，忽略异常
                    try {
                        resultChannel.send(entry to domain)
                    } catch (e: Exception) {
                        // Channel 已关闭或任务已取消，忽略
                        Logger.debug("结果发送被忽略（任务已取消或 channel 已关闭）: ${entry.url}")
                    }
                }
            }

            // 竞赛模式：接收结果，一旦成功立即返回（后台继续统计）
            var receivedCount = 0
            val batchCount = batch.size
            var successDomain: String? = null

            try {
                while (receivedCount < batchCount && successDomain == null) {
                    val (entry, domain) = resultChannel.receive()
                    receivedCount++

                    if (domain != null) {
                        // 成功！立即返回，后台继续统计剩余结果
                        Logger.info("Found available server: $domain (from ${entry.url})")
                        successDomain = domain

                        // 异步记录成功
                        storageScope.launch {
                            urlManager.recordSuccess(entry.url)
                        }

                        // 后台继续接收并统计剩余结果（不阻塞返回）
                        val remainingCount = batchCount - receivedCount
                        if (remainingCount > 0) {
                            storageScope.launch {
                                Logger.debug("后台继续统计剩余 $remainingCount 个结果")
                                repeat(remainingCount) {
                                    try {
                                        val (remainEntry, remainDomain) = resultChannel.receive()
                                        if (remainDomain != null) {
                                            urlManager.recordSuccess(remainEntry.url)
                                            Logger.debug("后台统计：${remainEntry.url} 成功")
                                        } else {
                                            urlManager.recordFailure(remainEntry.url)
                                            Logger.debug("后台统计：${remainEntry.url} 失败")
                                        }
                                    } catch (e: Exception) {
                                        Logger.debug("后台统计中断: ${e.message}")
                                        return@launch
                                    }
                                }
                                Logger.debug("后台统计完成")
                            }
                        }

                        // 立即退出主循环（不等待剩余结果）
                        break
                    } else {
                        // 失败，异步记录，继续等待其他结果
                        storageScope.launch {
                            urlManager.recordFailure(entry.url)
                        }
                    }
                }
            } finally {
                // 如果找到成功结果，稍微延迟关闭以允许后台任务开始接收
                if (successDomain != null) {
                    delay(50)  // 给后台协程 50ms 启动时间
                }
                // 清理资源：取消未完成的任务，关闭 channel
                jobs.forEach { it.cancel() }
                resultChannel.close()
            }

            if (successDomain != null) {
                return@coroutineScope successDomain
            }

            // 批次全部失败，立即尝试下一批次（无delay，追求最快响应）
        }

        return@coroutineScope null
    }
    
    /**
     * Add URL to persistent storage (线程安全，异步操作)
     * URL 会被持久化存储，并在下次检测时生效
     *
     * 注意：此操作是异步的，添加的 URL 不会立即在当前检测中使用
     */
    fun addURL(method: String, url: String) {
        val entry = URLEntry(method, url, store = false)
        storageScope.launch {
            if (urlManager.addURL(entry)) {
                Logger.info("成功添加 URL 到存储: $url")
            } else {
                Logger.error("添加 URL 失败: $url")
            }
        }
    }
    
    /**
     * Get last error
     */
    fun getLastError(): String? = lastError.get()

    /**
     * 清理资源（关闭协程作用域）
     * 当 FirewallDetector 不再使用时应该调用此方法
     */
    fun close() {
        // 先停止自动检测
        stopAutoDetection()

        // 取消所有协程作用域
        storageScope.cancel()
        autoDetectionScope.cancel()

        Logger.info("FirewallDetector resources cleaned up")
    }

    // MARK: - Private Methods
    
    /**
     * Check a single URL entry
     */
    private suspend fun checkURLEntry(entry: URLEntry, customData: String?, recursionDepth: Int): String? {
        lastError.set(null)

        // Check recursion depth limit（深度从0开始，允许 0 到 MAX_DEPTH-1）
        if (recursionDepth >= Config.MAX_LIST_RECURSION_DEPTH) {
            lastError.set("Maximum list recursion depth exceeded: ${entry.url}")
            Logger.error("Recursion depth limit reached ($recursionDepth >= ${Config.MAX_LIST_RECURSION_DEPTH}) for URL: ${entry.url}")
            return null
        }

        // Handle "remove" method - 从存储中删除 URL
        if (entry.method.lowercase() == "remove") {
            Logger.info("删除本地存储中的 URL: ${entry.url}")
            if (urlManager.removeURL(entry.url)) {
                Logger.info("成功删除 URL: ${entry.url}")
            } else {
                Logger.warning("删除失败（URL 可能不存在）: ${entry.url}")
            }
            // 不检查此 URL，直接跳过
            return null
        }

        // Handle "navigate" method - 打开浏览器
        if (entry.method.lowercase() == "navigate") {
            // 检查是否已经打开过，避免重复打开
            if (openedNavigateURLs.contains(entry.url)) {
                Logger.debug("Navigate URL 已打开过，跳过: ${entry.url}")
                return null
            }

            Logger.info("打开浏览器导航到: ${entry.url}")

            // 尝试打开浏览器
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(entry.url))
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                context.startActivity(intent)
                Logger.info("已在 Android 默认浏览器中打开: ${entry.url}")

                // 记录已打开
                openedNavigateURLs.add(entry.url)
            } catch (e: Exception) {
                Logger.error("打开浏览器失败: ${e.message}")
            }

            // 打开浏览器后继续检测下一个 URL
            return null
        }

        // Dispatch based on method
        val result = when (entry.method.lowercase()) {
            "api" -> checkAPIURL(entry.url, customData, recursionDepth)
            "file" -> checkFileURL(entry.url, customData, recursionDepth)
            else -> {
                lastError.set("Unknown method: ${entry.method}")
                Logger.error("未知的 method '${entry.method}' for URL: ${entry.url}")
                null
            }
        }

        // 如果检查成功且 store=true，则异步持久化存储此 URL（不阻塞返回）
        if (result != null && entry.store) {
            val storedEntry = URLEntry(method = entry.method, url = entry.url, store = false)

            // 后台异步存储，不阻塞返回
            storageScope.launch {
                Logger.info("后台存储检测成功的 URL: ${entry.url} (method: ${entry.method})")
                if (urlManager.addURL(storedEntry)) {
                    Logger.info("成功存储 URL: ${entry.url}")
                } else {
                    Logger.error("存储 URL 失败: ${entry.url}")
                }
            }
        }

        return result
    }
    
    /**
     * Check an API URL with retry mechanism
     */
    private suspend fun checkAPIURL(url: String, customData: String?, recursionDepth: Int): String? {
        Logger.debug("CheckAPIURL() called for: $url with customData: $customData")

        if (url.isEmpty()) {
            lastError.set("Empty URL provided")
            return null
        }

        // Retry loop
        for (attempt in 1..Config.MAX_RETRIES) {
            Logger.debug("Attempt $attempt/${Config.MAX_RETRIES} for URL: $url")

            checkNormalURLOnce(url, customData, recursionDepth)?.let { domain ->
                Logger.info("Successfully verified URL: $url on attempt $attempt")
                return domain
            }

            // If this was the last attempt, give up
            if (attempt == Config.MAX_RETRIES) {
                Logger.warning("All ${Config.MAX_RETRIES} attempts failed for URL: $url. Last error: ${lastError.get() ?: "unknown"}")
                return null
            }

            // Wait before retry
            Logger.debug("Waiting ${Config.RETRY_DELAY}ms before retry...")
            delay(Config.RETRY_DELAY)
        }

        return null
    }
    
    /**
     * Check a normal URL once (no retry)
     */
    private suspend fun checkNormalURLOnce(url: String, customData: String?, recursionDepth: Int): String? {
        val gson = Gson()

        // 1. Generate random nonce
        val randomData = cryptoHelper.generateRandom(Config.NONCE_SIZE)
        val randomBase64 = Base64.encodeToString(randomData, Base64.NO_WRAP)
        Logger.debug("Generated random data: ${randomData.size} bytes")

        // 2. Truncate custom data if too long
        var clientData = customData ?: ""
        if (clientData.length > Config.MAX_CLIENT_DATA_SIZE) {
            Logger.warning("client_data truncated from ${clientData.length} to ${Config.MAX_CLIENT_DATA_SIZE} bytes")
            clientData = clientData.substring(0, Config.MAX_CLIENT_DATA_SIZE)
        }

        // 3. Build JSON payload
        val payload = mapOf(
            "nonce" to randomBase64,
            "client_data" to clientData
        )
        val payloadJSON = gson.toJson(payload)
        Logger.debug("Payload JSON: $payloadJSON")

        // 4. Encrypt payload
        val encryptedData = cryptoHelper.encrypt(payloadJSON.toByteArray(Charsets.UTF_8))
        if (encryptedData == null) {
            lastError.set("Failed to encrypt data")
            return null
        }
        val encryptedBase64 = Base64.encodeToString(encryptedData, Base64.NO_WRAP)
        Logger.debug("Encrypted data: ${encryptedData.size} bytes")

        // 5. Build request JSON
        val requestData = mapOf("data" to encryptedBase64)
        val requestBody = gson.toJson(requestData)

        // 6. POST request
        val response = networkClient.post(url, requestBody)
        if (!response.success) {
            lastError.set("POST request failed: $url - ${response.error}")
            return null
        }

        // 7. Parse response JSON
        @Suppress("UNCHECKED_CAST")
        val responseJSON = try {
            gson.fromJson(response.body, Map::class.java) as Map<*, *>
        } catch (e: Exception) {
            lastError.set("Failed to parse response JSON: ${e.message}")
            return null
        }

        val returnedRandom = responseJSON.get("random") as? String
        val signature = responseJSON.get("signature") as? String

        if (returnedRandom == null || signature == null) {
            lastError.set("Response JSON missing required fields (random/signature)")
            return null
        }

        // domain 和 urls 都是可选的
        val returnedDomain = responseJSON.get("domain") as? String

        Logger.debug("Returned random: $returnedRandom")
        if (returnedDomain != null) {
            Logger.debug("Returned domain: $returnedDomain")
        }

        // 8. Verify signature (sign response without signature field)
        // CRITICAL: Must use sorted keys to match server serialization
        val payloadForSigning = sortedMapOf<String, Any?>()
        responseJSON.forEach { (key, value) ->
            val keyStr = key as? String ?: return@forEach
            if (keyStr != "signature") {
                payloadForSigning[keyStr] = value
            }
        }

        val payloadJSON2 = gson.toJson(payloadForSigning)
        Logger.debug("Payload for verification: $payloadJSON2")

        val payloadData = payloadJSON2.toByteArray(Charsets.UTF_8)
        val signatureData = Base64.decode(signature, Base64.DEFAULT)

        if (!cryptoHelper.verifySignature(payloadData, signatureData)) {
            lastError.set("Signature verification failed")
            return null
        }

        // 9. Verify random matches
        if (returnedRandom != randomBase64) {
            val expectedPrefix = randomBase64.take(10)
            val actualPrefix = returnedRandom.take(10)
            lastError.set("Random mismatch: expected: $expectedPrefix..., actual: $actualPrefix...")
            return null
        }

        // 10. 处理服务器返回的 urls 数组（如果有）
        val urlsData = responseJSON.get("urls") as? List<*>
        if (urlsData != null) {
            Logger.debug("Server returned ${urlsData.size} URLs in response")

            val urlEntries = mutableListOf<URLEntry>()
            for (urlDict in urlsData) {
                val dict = urlDict as? Map<*, *> ?: continue
                val method = dict["method"] as? String ?: continue
                val urlStr = dict["url"] as? String ?: continue
                val store = dict["store"] as? Boolean ?: false
                urlEntries.add(URLEntry(method = method, url = urlStr, store = store))
            }

            // 策略：如果有 domain，说明服务器可信，异步存储 store=true 的 URL（不阻塞返回）
            if (returnedDomain != null) {
                for (entry in urlEntries) {
                    if (entry.store) {
                        val storedEntry = URLEntry(method = entry.method, url = entry.url, store = false)
                        // 后台异步存储，不阻塞返回
                        storageScope.launch {
                            Logger.info("后台存储服务器推荐的 URL: ${entry.url} (method: ${entry.method})")
                            if (urlManager.addURL(storedEntry)) {
                                Logger.info("成功存储 URL: ${entry.url}")
                            } else {
                                Logger.error("存储 URL 失败: ${entry.url}")
                            }
                        }
                    }
                }
            } else {
                // 没有 domain，循环检测 urls，只存储检测成功的
                Logger.debug("No domain in response, checking URLs from server...")

                for (entry in urlEntries) {
                    Logger.debug("Checking server-provided URL: ${entry.url} (method: ${entry.method})")

                    checkURLEntry(entry, customData, recursionDepth + 1)?.let { domain ->
                        Logger.info("Server-provided URL succeeded: ${entry.url} -> $domain")

                        // 检测成功，异步存储（不阻塞返回）
                        if (entry.store) {
                            val storedEntry = URLEntry(method = entry.method, url = entry.url, store = false)
                            storageScope.launch {
                                Logger.info("后台存储检测成功的 URL: ${entry.url}")
                                urlManager.addURL(storedEntry)
                            }
                        }

                        return domain
                    }

                    Logger.debug("Server-provided URL failed: ${entry.url}, trying next...")
                    delay(Config.URL_INTERVAL)
                }

                lastError.set("All server-provided URLs failed")
                return null
            }
        }

        // 11. 如果有 domain，返回它
        if (returnedDomain != null) {
            Logger.debug("Verification successful! Using domain: $returnedDomain")
            return returnedDomain
        }

        // 既没有 domain 也没有 urls
        lastError.set("Response has neither domain nor urls")
        return null
    }
    
    /**
     * Check a file URL (fetch sub-list and check each URL)
     * ✅ 完美递归：子 URL 列表会根据配置使用并发或串行检测
     */
    private suspend fun checkFileURL(url: String, customData: String?, recursionDepth: Int): String? {
        Logger.debug("CheckFileURL() called for: $url (depth: $recursionDepth)")

        if (url.isEmpty()) {
            lastError.set("Empty file URL provided")
            return null
        }

        // Fetch sub-list
        Logger.debug("Fetching sub-list from: $url")
        val response = networkClient.get(url)

        if (!response.success) {
            lastError.set("GET request failed: $url - ${response.error}")
            return null
        }

        // Try to parse as JSON first (new format with urls array)
        val subEntries = parseURLEntriesJSON(response.body)
        if (subEntries != null && subEntries.isNotEmpty()) {
            // ✅ 去重：使用 URL 作为唯一标识（保留第一个出现的 URLEntry）
            val uniqueEntries = subEntries.distinctBy { it.url }
            val duplicateCount = subEntries.size - uniqueEntries.size

            if (duplicateCount > 0) {
                Logger.warning("去重：从 file 子列表中移除了 $duplicateCount 个重复 URL")
            }

            Logger.debug("Fetched ${uniqueEntries.size} unique URL entries from JSON sub-list")

            // ✅ 递归调用并发检测逻辑（保持一致性）
            return if (Config.ENABLE_CONCURRENT_CHECK) {
                Logger.debug("使用并发模式检测子 URL 列表（深度 ${recursionDepth + 1}）")
                checkURLsConcurrently(uniqueEntries, customData, Config.CONCURRENT_CHECK_COUNT, recursionDepth + 1)
            } else {
                Logger.debug("使用串行模式检测子 URL 列表（深度 ${recursionDepth + 1}）")
                checkURLsSequentially(uniqueEntries, customData, recursionDepth + 1)
            }
        }

        // Fallback: parse as plain text URL list (legacy format)
        val subURLs = parseURLList(response.body)
        if (subURLs.isEmpty()) {
            lastError.set("Sub-list empty or parse failed: $url")
            return null
        }

        // ✅ 去重：移除重复的 URL
        val uniqueURLs = subURLs.distinct()
        val duplicateCount = subURLs.size - uniqueURLs.size

        if (duplicateCount > 0) {
            Logger.warning("去重：从 file 子列表中移除了 $duplicateCount 个重复 URL (legacy format)")
        }

        Logger.debug("Fetched ${uniqueURLs.size} unique URLs from text sub-list (legacy format)")

        // Convert to URLEntry list (assume API method)
        val entries = uniqueURLs.map { URLEntry(method = "api", url = it) }

        // ✅ 递归调用并发检测逻辑
        return if (Config.ENABLE_CONCURRENT_CHECK) {
            Logger.debug("使用并发模式检测子 URL 列表（深度 ${recursionDepth + 1}）")
            checkURLsConcurrently(entries, customData, Config.CONCURRENT_CHECK_COUNT, recursionDepth + 1)
        } else {
            Logger.debug("使用串行模式检测子 URL 列表（深度 ${recursionDepth + 1}）")
            checkURLsSequentially(entries, customData, recursionDepth + 1)
        }
    }
    
    /**
     * 智能解析 URL entries（支持多种格式）
     * Supports:
     * 1. *PGFW*base64(URLEntry[] JSON)*PGFW* format (preferred, can embed anywhere)
     * 2. HTML with <pre>, <code>, or <script type="application/json"> tags
     * 3. Direct URLEntry[] JSON array format
     * 4. Legacy {"urls": [...]} format
     */
    private fun parseURLEntriesJSON(content: String): List<URLEntry>? {
        Logger.debug("开始智能解析内容（长度: ${content.length}）")

        // Strategy 1: 优先尝试提取 *PGFW* 标记格式
        extractPGFWContent(content)?.let { extracted ->
            Logger.info("✓ 检测到 *PGFW* 标记格式")
            Logger.debug("提取的 base64 长度: ${extracted.length}")

            // Decode base64
            try {
                val decodedBytes = Base64.decode(extracted, Base64.DEFAULT)
                val decodedString = String(decodedBytes, Charsets.UTF_8)
                Logger.debug("解码后的内容: ${decodedString.take(200)}...")

                // Parse as URLEntry[] JSON array
                parseURLEntryArray(decodedString)?.let {
                    Logger.info("✓ 成功从 *PGFW* 标记中解析出 ${it.size} 个 URL entries")
                    return it
                }
            } catch (e: Exception) {
                Logger.debug("Base64 解码失败: ${e.message}")
            }
        }

        // Strategy 2: 检测 HTML 格式
        if (content.contains("<html", ignoreCase = true) ||
            content.contains("<!DOCTYPE", ignoreCase = true)) {
            Logger.info("✓ 检测到 HTML 格式，尝试提取内容...")

            // 2a. 尝试从 <pre> 标签提取
            extractHTMLTag(content, "pre")?.let { preContent ->
                Logger.debug("从 <pre> 标签提取到内容")
                parseURLEntryArray(preContent)?.let {
                    Logger.info("✓ 成功从 <pre> 标签解析出 ${it.size} 个 URL entries")
                    return it
                }
            }

            // 2b. 尝试从 <code> 标签提取
            extractHTMLTag(content, "code")?.let { codeContent ->
                Logger.debug("从 <code> 标签提取到内容")
                parseURLEntryArray(codeContent)?.let {
                    Logger.info("✓ 成功从 <code> 标签解析出 ${it.size} 个 URL entries")
                    return it
                }
            }

            // 2c. 尝试从 <script type="application/json"> 提取
            extractJSONScript(content)?.let { scriptContent ->
                Logger.debug("从 <script type=\"application/json\"> 提取到内容")
                parseURLEntryArray(scriptContent)?.let {
                    Logger.info("✓ 成功从 <script> 标签解析出 ${it.size} 个 URL entries")
                    return it
                }
            }

            Logger.debug("HTML 中未找到可解析的 JSON 内容")
        }

        // Strategy 3: 尝试直接解析为 URLEntry[] JSON 数组
        parseURLEntryArray(content)?.let {
            Logger.info("✓ 成功直接解析为 URLEntry[] 数组（${it.size} 个 entries）")
            return it
        }

        // Strategy 4: 尝试旧版 {"urls": [...]} 格式
        try {
            val gson = Gson()
            @Suppress("UNCHECKED_CAST")
            val json = gson.fromJson(content, Map::class.java) as Map<*, *>
            val urlsArray = json.get("urls") as? List<*>

            urlsArray?.mapNotNull { urlDict ->
                (urlDict as? Map<*, *>)?.let {
                    val method = it["method"] as? String
                    val url = it["url"] as? String
                    val store = it["store"] as? Boolean ?: false
                    if (method != null && url != null) {
                        URLEntry(method, url, store)
                    } else null
                }
            }?.takeIf { it.isNotEmpty() }?.let {
                Logger.info("✓ 成功解析旧版 {\"urls\": [...]} 格式（${it.size} 个 entries）")
                return it
            }
        } catch (e: Exception) {
            Logger.debug("旧版格式解析失败: ${e.message}")
        }

        Logger.warning("所有解析策略均失败")
        return null
    }

    /**
     * 从 HTML 中提取指定标签的内容
     * 支持 HTML 实体解码
     */
    private fun extractHTMLTag(html: String, tag: String): String? {
        try {
            // 匹配 <tag...>content</tag>，支持标签属性
            val pattern = Regex("<$tag[^>]*>(.*?)</$tag>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
            val match = pattern.find(html) ?: return null

            val content = match.groups[1]?.value ?: return null

            // HTML 实体解码
            return decodeHTMLEntities(content)
        } catch (e: Exception) {
            Logger.debug("提取 HTML 标签 <$tag> 失败: ${e.message}")
            return null
        }
    }

    /**
     * 从 HTML 中提取 <script type="application/json"> 的内容
     */
    private fun extractJSONScript(html: String): String? {
        try {
            val pattern = Regex(
                "<script[^>]+type=[\"']application/json[\"'][^>]*>(.*?)</script>",
                setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE)
            )
            val match = pattern.find(html) ?: return null

            return match.groups[1]?.value?.trim()
        } catch (e: Exception) {
            Logger.debug("提取 JSON script 失败: ${e.message}")
            return null
        }
    }

    /**
     * HTML 实体解码
     */
    private fun decodeHTMLEntities(text: String): String {
        return text
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
            .replace("&amp;", "&")
            .trim()
    }
    
    /**
     * Extract content between *PGFW* markers
     */
    private fun extractPGFWContent(text: String): String? {
        val startMarker = "*PGFW*"
        val endMarker = "*PGFW*"
        
        val startIndex = text.indexOf(startMarker)
        if (startIndex == -1) return null
        
        val contentStart = startIndex + startMarker.length
        val endIndex = text.indexOf(endMarker, contentStart)
        if (endIndex == -1) return null
        
        return text.substring(contentStart, endIndex).trim()
    }
    
    /**
     * Parse URLEntry[] JSON array
     */
    private fun parseURLEntryArray(json: String): List<URLEntry>? {
        return try {
            val gson = Gson()
            @Suppress("UNCHECKED_CAST")
            val array = gson.fromJson(json, List::class.java) as List<*>

            array.mapNotNull { item ->
                (item as? Map<*, *>)?.let {
                    val method = it["method"] as? String
                    val url = it["url"] as? String
                    if (method != null && url != null) {
                        URLEntry(method, url)
                    } else null
                }
            }?.takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * Parse URL list from text content
     */
    private fun parseURLList(content: String): List<String> {
        val urls = mutableListOf<String>()
        
        // Try to extract content between *GFW* markers
        val marker = "*GFW*"
        val startIndex = content.indexOf(marker)
        
        if (startIndex != -1) {
            val endIndex = content.indexOf(marker, startIndex + marker.length)
            if (endIndex != -1) {
                val gfwContent = content.substring(startIndex + marker.length, endIndex).trim()
                
                if (gfwContent.isNotEmpty()) {
                    // Parse URLs from marked content
                    gfwContent.lines().forEach { line ->
                        val url = line.trim()
                        if (url.isNotEmpty() && !url.startsWith("#")) {
                            urls.add(url)
                        }
                    }
                    return urls
                }
            }
        }
        
        // If no markers found, parse entire content
        content.lines().forEach { line ->
            val url = line.trim()
            if (url.isNotEmpty() && !url.startsWith("#")) {
                urls.add(url)
            }
        }
        
        return urls
    }
}

