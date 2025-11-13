package com.passgfw

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

/**
 * URL Manager - 负责 URL 列表的持久化存储
 */
class URLManager(private val context: Context) {
    private companion object {
        const val STORAGE_KEY = "passgfw.urls"
    }

    private val storage = SecureStorage(context)
    private val gson = Gson()

    /**
     * 初始化 URL 列表（仅首次启动时调用）
     * @return 是否成功初始化
     */
    fun initializeIfNeeded(): Boolean {
        // 检查是否已经初始化
        if (loadURLs() != null) {
            return true  // 已经初始化过了
        }

        // 首次启动，使用内置 URLs 初始化
        val builtinURLs = Config.getBuiltinURLs()
        return saveURLs(builtinURLs)
    }

    /**
     * 获取 URL 列表（按存储顺序）
     * @return URLEntry 数组
     */
    fun getURLs(): List<URLEntry> {
        return loadURLs() ?: Config.getBuiltinURLs()
    }

    /**
     * 添加新的 URL（通过动态添加，store=true）
     * @param entry 要添加的 URLEntry
     * @return 是否成功添加
     */
    fun addURL(entry: URLEntry): Boolean {
        val urls = (loadURLs() ?: emptyList()).toMutableList()

        // 检查是否已存在
        if (urls.any { it.url == entry.url }) {
            return true  // 已存在，不重复添加
        }

        // 添加新 URL
        urls.add(entry)
        return saveURLs(urls)
    }

    /**
     * 删除 URL（remove 方法）
     * @param url 要删除的 URL
     * @return 是否成功删除
     */
    fun removeURL(url: String): Boolean {
        val urls = (loadURLs() ?: return false).toMutableList()
        urls.removeAll { it.url == url }
        return saveURLs(urls)
    }

    /**
     * 清空所有 URL 并重新初始化为内置列表
     * @return 是否成功重置
     */
    fun reset(): Boolean {
        val builtinURLs = Config.getBuiltinURLs()
        return saveURLs(builtinURLs)
    }

    // MARK: - Private Methods

    private fun loadURLs(): List<URLEntry>? {
        val data = storage.load(STORAGE_KEY) ?: return null

        return try {
            val json = String(data)
            val type = object : TypeToken<List<URLEntry>>() {}.type
            gson.fromJson<List<URLEntry>>(json, type)
        } catch (e: Exception) {
            Logger.error("Failed to decode URLs: ${e.message}")
            null
        }
    }

    private fun saveURLs(urls: List<URLEntry>): Boolean {
        return try {
            val json = gson.toJson(urls)
            storage.save(STORAGE_KEY, json.toByteArray())
        } catch (e: Exception) {
            Logger.error("Failed to encode URLs: ${e.message}")
            false
        }
    }
}
