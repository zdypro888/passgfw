package com.passgfw

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * 安全存储接口
 */
interface SecureStorage {
    fun save(value: String, key: String): Boolean
    fun load(key: String): String?
    fun delete(key: String): Boolean
}

/**
 * EncryptedSharedPreferences 实现的安全存储
 */
class EncryptedStorage(context: Context) : SecureStorage {
    companion object {
        private const val PREFS_FILE_NAME = "passgfw_secure_prefs"
    }

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val sharedPreferences = EncryptedSharedPreferences.create(
        context,
        PREFS_FILE_NAME,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    override fun save(value: String, key: String): Boolean {
        return try {
            sharedPreferences.edit().putString(key, value).apply()
            true
        } catch (e: Exception) {
            Logger.error("Failed to save to encrypted storage: ${e.message}")
            false
        }
    }

    override fun load(key: String): String? {
        return try {
            sharedPreferences.getString(key, null)
        } catch (e: Exception) {
            Logger.error("Failed to load from encrypted storage: ${e.message}")
            null
        }
    }

    override fun delete(key: String): Boolean {
        return try {
            sharedPreferences.edit().remove(key).apply()
            true
        } catch (e: Exception) {
            Logger.error("Failed to delete from encrypted storage: ${e.message}")
            false
        }
    }
}
