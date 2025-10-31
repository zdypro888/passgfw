package com.passgfw

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

/**
 * 管理 URL 的持久化存储（使用 EncryptedSharedPreferences 加密存储）
 */
class URLStorageManager private constructor(private val context: Context) {

    companion object {
        @Volatile
        private var instance: URLStorageManager? = null

        // 加密存储配置
        private const val PREFS_NAME = "passgfw_secure_urls"
        private const val KEY_URLS = "stored_urls"

        // 旧版本文件配置（用于数据迁移）
        private const val LEGACY_FILE_NAME = "passgfw_urls.json"

        fun initialize(context: Context) {
            if (instance == null) {
                synchronized(this) {
                    if (instance == null) {
                        instance = URLStorageManager(context.applicationContext)
                    }
                }
            }
        }

        fun getInstance(): URLStorageManager {
            return instance ?: throw IllegalStateException("URLStorageManager 未初始化。请先调用 initialize()")
        }
    }

    private val gson = Gson()
    private val encryptedPrefs: SharedPreferences

    // 旧版本文件路径（用于数据迁移）
    private val legacyFile: File = File(context.filesDir, LEGACY_FILE_NAME)

    init {
        Logger.debug("初始化 URLStorageManager（加密存储）")

        // 创建或获取 Master Key
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        // 创建加密的 SharedPreferences
        encryptedPrefs = EncryptedSharedPreferences.create(
            context,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )

        Logger.debug("EncryptedSharedPreferences 初始化完成")

        // 启动时自动迁移旧数据
        migrateFromLegacyStorage()
    }

    /**
     * 从本地加密存储加载存储的 URL
     */
    fun loadStoredURLs(): List<URLEntry> {
        val json = encryptedPrefs.getString(KEY_URLS, null)

        if (json == null) {
            Logger.debug("加密存储中没有 URL 数据")
            return emptyList()
        }

        return try {
            val type = object : TypeToken<List<URLEntry>>() {}.type
            val entries: List<URLEntry> = gson.fromJson(json, type)
            Logger.info("从加密存储加载了 ${entries.size} 个 URL")
            entries
        } catch (e: Exception) {
            Logger.error("从加密存储解析 URL 失败: ${e.message}")
            emptyList()
        }
    }

    /**
     * 保存 URL 到加密存储
     */
    private fun saveURLs(entries: List<URLEntry>): Boolean {
        return try {
            val json = gson.toJson(entries)
            encryptedPrefs.edit().putString(KEY_URLS, json).apply()
            Logger.info("成功保存 ${entries.size} 个 URL 到加密存储")
            true
        } catch (e: Exception) {
            Logger.error("保存 URL 到加密存储失败: ${e.message}")
            false
        }
    }

    /**
     * 添加 URL 到存储（如果不存在）
     */
    fun addURL(entry: URLEntry): Boolean {
        val entries = loadStoredURLs().toMutableList()

        // 检查是否已存在
        if (entries.any { it.url == entry.url }) {
            Logger.debug("URL 已存在于存储中: ${entry.url}")
            return true // 已存在，视为成功
        }

        // 添加新条目
        entries.add(entry)
        Logger.info("添加 URL 到存储: ${entry.url} (方法: ${entry.method})")

        return saveURLs(entries)
    }

    /**
     * 从存储中删除 URL
     */
    fun removeURL(url: String): Boolean {
        val entries = loadStoredURLs().toMutableList()
        val originalSize = entries.size

        // 删除匹配的 URL
        entries.removeAll { it.url == url }

        return if (entries.size < originalSize) {
            Logger.info("从存储中删除 URL: $url")
            saveURLs(entries)
        } else {
            Logger.debug("URL 未在存储中找到: $url")
            true // 未找到，但不算错误
        }
    }

    /**
     * 清空所有存储的 URL
     */
    fun clearAll(): Boolean {
        Logger.info("清空所有存储的 URL")
        return try {
            encryptedPrefs.edit().remove(KEY_URLS).apply()
            true
        } catch (e: Exception) {
            Logger.error("清空存储失败: ${e.message}")
            false
        }
    }

    /**
     * 获取存储的 URL 数量
     */
    fun getCount(): Int {
        return loadStoredURLs().size
    }

    // MARK: - 数据迁移

    /**
     * 从旧版本的明文文件存储迁移到加密存储
     */
    private fun migrateFromLegacyStorage() {
        // 检查加密存储是否已有数据
        if (encryptedPrefs.contains(KEY_URLS)) {
            Logger.debug("加密存储已有数据，跳过迁移")
            // 已有数据，检查是否需要删除旧文件
            deleteLegacyFile()
            return
        }

        // 检查旧文件是否存在
        if (!legacyFile.exists()) {
            Logger.debug("未找到旧版本存储文件，无需迁移")
            return
        }

        Logger.info("检测到旧版本存储文件，开始数据迁移...")

        try {
            // 读取旧文件
            val json = legacyFile.readText()
            val type = object : TypeToken<List<URLEntry>>() {}.type
            val entries: List<URLEntry> = gson.fromJson(json, type)

            Logger.info("从旧文件读取了 ${entries.size} 个 URL")

            // 保存到加密存储
            if (saveURLs(entries)) {
                Logger.info("✅ 数据迁移成功，已保存到加密存储")

                // 验证迁移结果
                val verifyEntries = loadStoredURLs()
                if (verifyEntries.size == entries.size) {
                    Logger.info("✅ 迁移验证成功")
                    // 删除旧文件
                    deleteLegacyFile()
                } else {
                    Logger.error("⚠️ 迁移验证失败，保留旧文件以防数据丢失")
                }
            } else {
                Logger.error("❌ 迁移失败，保留旧文件")
            }
        } catch (e: Exception) {
            Logger.error("读取旧文件失败: ${e.message}")
        }
    }

    /**
     * 删除旧版本的存储文件
     */
    private fun deleteLegacyFile() {
        if (!legacyFile.exists()) {
            return
        }

        try {
            if (legacyFile.delete()) {
                Logger.info("已删除旧版本存储文件")
            } else {
                Logger.warning("删除旧文件失败")
            }
        } catch (e: Exception) {
            Logger.warning("删除旧文件失败: ${e.message}")
        }
    }
}
