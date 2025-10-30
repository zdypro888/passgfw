package com.passgfw

import android.util.Log

/**
 * Log level
 */
enum class LogLevel(val value: Int) {
    DEBUG(0),
    INFO(1),
    WARNING(2),
    ERROR(3);
    
    operator fun compareTo(other: LogLevel): Int = value.compareTo(other.value)
}

/**
 * Logger for PassGFW
 */
object Logger {
    private const val TAG = "PassGFW"
    
    var isEnabled = true
    var minLevel = LogLevel.DEBUG
    
    fun debug(message: String) {
        log(message, LogLevel.DEBUG)
    }
    
    fun info(message: String) {
        log(message, LogLevel.INFO)
    }
    
    fun warning(message: String) {
        log(message, LogLevel.WARNING)
    }
    
    fun error(message: String) {
        log(message, LogLevel.ERROR)
    }
    
    private fun log(message: String, level: LogLevel) {
        if (!isEnabled || level < minLevel) return
        
        when (level) {
            LogLevel.DEBUG -> Log.d(TAG, message)
            LogLevel.INFO -> Log.i(TAG, message)
            LogLevel.WARNING -> Log.w(TAG, message)
            LogLevel.ERROR -> Log.e(TAG, message)
        }
    }
}

