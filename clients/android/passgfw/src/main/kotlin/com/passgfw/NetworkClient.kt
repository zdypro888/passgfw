package com.passgfw

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * HTTP Response
 */
data class HTTPResponse(
    val success: Boolean,
    val statusCode: Int,
    val body: String,
    val error: String?
)

/**
 * Network Client for HTTP requests
 */
class NetworkClient(private val timeout: Long = Config.REQUEST_TIMEOUT) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(timeout, TimeUnit.MILLISECONDS)
        .readTimeout(timeout, TimeUnit.MILLISECONDS)
        .writeTimeout(timeout, TimeUnit.MILLISECONDS)
        .build()
    
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    
    /**
     * POST request
     */
    fun post(url: String, jsonBody: String): HTTPResponse {
        return try {
            val request = Request.Builder()
                .url(url)
                .post(jsonBody.toRequestBody(jsonMediaType))
                .addHeader("Content-Type", "application/json")
                .addHeader("User-Agent", "PassGFW/1.0 Kotlin")
                .build()
            
            client.newCall(request).execute().use { response ->
                HTTPResponse(
                    success = response.isSuccessful,
                    statusCode = response.code,
                    body = response.body?.string() ?: "",
                    error = if (response.isSuccessful) null else "HTTP ${response.code}"
                )
            }
        } catch (e: Exception) {
            HTTPResponse(false, 0, "", e.message)
        }
    }
    
    /**
     * GET request
     */
    fun get(url: String): HTTPResponse {
        return try {
            val request = Request.Builder()
                .url(url)
                .get()
                .addHeader("User-Agent", "PassGFW/1.0 Kotlin")
                .build()
            
            client.newCall(request).execute().use { response ->
                HTTPResponse(
                    success = response.isSuccessful,
                    statusCode = response.code,
                    body = response.body?.string() ?: "",
                    error = if (response.isSuccessful) null else "HTTP ${response.code}"
                )
            }
        } catch (e: Exception) {
            HTTPResponse(false, 0, "", e.message)
        }
    }
}

