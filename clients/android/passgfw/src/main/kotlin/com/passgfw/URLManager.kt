package com.passgfw

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * URL 状态枚举
 */
enum class URLStatus {
    UNTESTED,   // 未测试
    SUCCESS,    // 成功
    FAILED      // 失败
}

/**
 * URL 元数据 - 包含 URL 信息和测试统计
 */
@Serializable
data class URLMetadata(
    val method: String,
    val url: String,
    val store: Boolean = false,
    var status: String = URLStatus.UNTESTED.name,
    var successCount: Int = 0,
    var failureCount: Int = 0,
    var lastTested: Long? = null,      // Unix timestamp (milliseconds)
    var lastSuccess: Long? = null      // Unix timestamp (milliseconds)
) {
    constructor(entry: URLEntry) : this(
        method = entry.method,
        url = entry.url,
        store = entry.store,
        status = URLStatus.UNTESTED.name,
        successCount = 0,
        failureCount = 0,
        lastTested = null,
        lastSuccess = null
    )

    /**
     * 转换为 URLEntry
     */
    fun toURLEntry(): URLEntry {
        return URLEntry(method = method, url = url, store = store)
    }

    /**
     * 记录成功
     */
    fun recordSuccess(): URLMetadata {
        val now = System.currentTimeMillis()
        return copy(
            status = URLStatus.SUCCESS.name,
            successCount = successCount + 1,
            lastTested = now,
            lastSuccess = now
        )
    }

    /**
     * 记录失败
     */
    fun recordFailure(): URLMetadata {
        return copy(
            status = URLStatus.FAILED.name,
            failureCount = failureCount + 1,
            lastTested = System.currentTimeMillis()
        )
    }

    /**
     * 获取状态枚举
     */
    fun getStatusEnum(): URLStatus {
        return try {
            URLStatus.valueOf(status)
        } catch (e: Exception) {
            URLStatus.UNTESTED
        }
    }
}

/**
 * URL 管理器 - 负责 URL 列表的持久化存储和优先级排序
 */
class URLManager(private val storage: SecureStorage) {
    companion object {
        private const val STORAGE_KEY = "passgfw.urls"
    }

    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = false
    }

    // 互斥锁，确保所有存储操作的线程安全
    private val mutex = Mutex()

    /**
     * 初始化 URL 列表（仅首次启动时调用）（线程安全）
     * @return 是否成功初始化
     */
    fun initializeIfNeeded(): Boolean {
        // 先快速检查（无锁，避免频繁加锁）
        if (loadURLs() != null) {
            return true  // 已经初始化过了
        }

        // 加锁进行初始化（避免重复初始化）
        return kotlinx.coroutines.runBlocking {
            mutex.withLock {
                // 双重检查：可能其他线程已经初始化了
                if (loadURLs() != null) {
                    return@withLock true
                }

                // 首次启动，使用内置 URLs 初始化
                val builtinURLs = Config.getBuiltinURLs()
                val metadata = builtinURLs.map { URLMetadata(it) }
                return@withLock saveURLs(metadata)
            }
        }
    }

    /**
     * 获取排序后的 URL 列表（线程安全）
     * @return 按优先级排序的 URLEntry 列表
     *
     * 注意：为了保证与写操作的一致性，此方法使用锁保护读取。
     * 虽然会略微影响性能，但确保了数据的正确性。
     */
    suspend fun getSortedURLs(): List<URLEntry> = mutex.withLock {
        val metadata = loadURLs() ?: run {
            // 如果加载失败，返回内置 URLs
            return@withLock Config.getBuiltinURLs()
        }

        // 排序逻辑
        val sorted = metadata.sortedWith(compareBy<URLMetadata> {
            // 1. 首先按 status 排序：success > untested > failed
            when (it.getStatusEnum()) {
                URLStatus.SUCCESS -> 0
                URLStatus.UNTESTED -> 1
                URLStatus.FAILED -> 2
            }
        }.thenByDescending {
            // 2. 同一 status，按 successCount 降序
            it.successCount
        }.thenByDescending {
            // 3. successCount 相同，按 lastSuccess 降序
            it.lastSuccess ?: 0L
        })

        return@withLock sorted.map { it.toURLEntry() }
    }

    /**
     * 记录 URL 检测成功（线程安全）
     * @param url 成功的 URL
     */
    suspend fun recordSuccess(url: String) = mutex.withLock {
        val metadata = loadURLs()?.toMutableList() ?: return@withLock

        val index = metadata.indexOfFirst { it.url == url }
        if (index >= 0) {
            metadata[index] = metadata[index].recordSuccess()
            saveURLs(metadata)
        }
    }

    /**
     * 记录 URL 检测失败（线程安全）
     * @param url 失败的 URL
     */
    suspend fun recordFailure(url: String) = mutex.withLock {
        val metadata = loadURLs()?.toMutableList() ?: return@withLock

        val index = metadata.indexOfFirst { it.url == url }
        if (index >= 0) {
            metadata[index] = metadata[index].recordFailure()
            saveURLs(metadata)
        }
    }

    /**
     * 添加新的 URL（通过 list# 或 file# 动态添加）（线程安全）
     * @param entry 要添加的 URLEntry
     * @return 是否成功添加
     */
    suspend fun addURL(entry: URLEntry): Boolean = mutex.withLock {
        val metadata = loadURLs()?.toMutableList() ?: mutableListOf()

        // 检查是否已存在
        if (metadata.any { it.url == entry.url }) {
            return@withLock true  // 已存在，不重复添加
        }

        // 添加新 URL
        metadata.add(URLMetadata(entry))
        return@withLock saveURLs(metadata)
    }

    /**
     * 删除 URL（明确删除操作）（线程安全）
     * @param url 要删除的 URL
     * @return 是否成功删除
     */
    suspend fun removeURL(url: String): Boolean = mutex.withLock {
        val metadata = loadURLs()?.toMutableList() ?: return@withLock false

        metadata.removeAll { it.url == url }
        return@withLock saveURLs(metadata)
    }

    /**
     * 清空所有 URL 并重新初始化为内置列表（线程安全）
     * @return 是否成功重置
     */
    suspend fun reset(): Boolean = mutex.withLock {
        val builtinURLs = Config.getBuiltinURLs()
        val metadata = builtinURLs.map { URLMetadata(it) }
        return@withLock saveURLs(metadata)
    }

    // MARK: - Private Methods

    private fun loadURLs(): List<URLMetadata>? {
        val jsonString = storage.load(STORAGE_KEY) ?: return null

        return try {
            json.decodeFromString<List<URLMetadata>>(jsonString)
        } catch (e: Exception) {
            Logger.error("Failed to decode URL metadata: ${e.message}")
            null
        }
    }

    private fun saveURLs(metadata: List<URLMetadata>): Boolean {
        return try {
            val jsonString = json.encodeToString(metadata)
            storage.save(jsonString, STORAGE_KEY)
        } catch (e: Exception) {
            Logger.error("Failed to encode URL metadata: ${e.message}")
            false
        }
    }
}
