package com.passgfw

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

/**
 * Manages persistent storage of URLs locally
 */
class URLStorageManager private constructor(private val context: Context) {
    
    companion object {
        @Volatile
        private var instance: URLStorageManager? = null
        
        private const val FILE_NAME = "passgfw_urls.json"
        
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
            return instance ?: throw IllegalStateException("URLStorageManager not initialized. Call initialize() first.")
        }
    }
    
    private val gson = Gson()
    private val storageFile: File = File(context.filesDir, FILE_NAME)
    
    init {
        Logger.debug("URL storage file: ${storageFile.absolutePath}")
    }
    
    /**
     * Load stored URLs from local file
     */
    fun loadStoredURLs(): List<URLEntry> {
        if (!storageFile.exists()) {
            Logger.debug("Storage file does not exist yet")
            return emptyList()
        }
        
        return try {
            val json = storageFile.readText()
            val type = object : TypeToken<List<URLEntry>>() {}.type
            val entries: List<URLEntry> = gson.fromJson(json, type)
            Logger.info("Loaded ${entries.size} stored URLs from local file")
            entries
        } catch (e: Exception) {
            Logger.error("Failed to load stored URLs: ${e.message}")
            emptyList()
        }
    }
    
    /**
     * Save URLs to local file
     */
    private fun saveURLs(entries: List<URLEntry>): Boolean {
        return try {
            val json = gson.toJson(entries)
            storageFile.writeText(json)
            Logger.info("Saved ${entries.size} URLs to local file")
            true
        } catch (e: Exception) {
            Logger.error("Failed to save URLs: ${e.message}")
            false
        }
    }
    
    /**
     * Add a URL to storage (if not already exists)
     */
    fun addURL(entry: URLEntry): Boolean {
        val entries = loadStoredURLs().toMutableList()
        
        // Check if already exists
        if (entries.any { it.url == entry.url }) {
            Logger.debug("URL already exists in storage: ${entry.url}")
            return true // Already exists, consider it success
        }
        
        // Add new entry
        entries.add(entry)
        Logger.info("Adding URL to storage: ${entry.url} (method: ${entry.method})")
        
        return saveURLs(entries)
    }
    
    /**
     * Remove a URL from storage
     */
    fun removeURL(url: String): Boolean {
        val entries = loadStoredURLs().toMutableList()
        val originalSize = entries.size
        
        // Remove matching URL
        entries.removeAll { it.url == url }
        
        return if (entries.size < originalSize) {
            Logger.info("Removed URL from storage: $url")
            saveURLs(entries)
        } else {
            Logger.debug("URL not found in storage: $url")
            true // Not found, but not an error
        }
    }
    
    /**
     * Clear all stored URLs
     */
    fun clearAll(): Boolean {
        Logger.info("Clearing all stored URLs")
        return saveURLs(emptyList())
    }
    
    /**
     * Get count of stored URLs
     */
    fun getCount(): Int {
        return loadStoredURLs().size
    }
}

