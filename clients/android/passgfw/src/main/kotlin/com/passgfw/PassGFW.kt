package com.passgfw

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * PassGFW - Firewall Detection Library (Android)
 *
 * Main entry point for the PassGFW library.
 */
class PassGFW(context: Context) {
    private val detector = FirewallDetector(context)

    /**
     * Get server domains by checking URL list
     * @param retry If true, force re-detection even if cache exists. If false, return cache if available.
     * @param customData Optional custom data to send with requests
     * @return Map containing server response data, or null if all attempts fail
     */
    suspend fun getDomains(retry: Boolean = false, customData: String? = null): Map<String, Any>? = withContext(Dispatchers.IO) {
        detector.getDomains(retry, customData)
    }

    /**
     * Get the last error message
     * @return Last error message, or null if no error
     */
    fun getLastError(): String? {
        return detector.getLastError()
    }

    /**
     * Enable or disable logging
     * @param enabled Whether to enable logging
     */
    fun setLoggingEnabled(enabled: Boolean) {
        Logger.isEnabled = enabled
    }

    /**
     * Set the minimum log level
     * @param level Minimum log level to display
     */
    fun setLogLevel(level: LogLevel) {
        Logger.minLevel = level
    }
}

