package com.passgfw.example

import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.passgfw.PassGFW
import com.passgfw.URLEntry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * PassGFW Android 测试应用
 */
class MainActivity : AppCompatActivity() {

    private lateinit var passGFW: PassGFW
    private lateinit var statusText: TextView
    private lateinit var domainText: TextView
    private lateinit var detectButton: Button
    private lateinit var customUrlButton: Button
    private lateinit var addUrlButton: Button
    private lateinit var progressBar: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // 初始化视图
        statusText = findViewById(R.id.statusText)
        domainText = findViewById(R.id.domainText)
        detectButton = findViewById(R.id.detectButton)
        customUrlButton = findViewById(R.id.customUrlButton)
        addUrlButton = findViewById(R.id.addUrlButton)
        progressBar = findViewById(R.id.progressBar)

        // 创建 PassGFW 实例
        passGFW = PassGFW(applicationContext)
        passGFW.setLoggingEnabled(true)

        // 按钮事件
        detectButton.setOnClickListener { example1BasicDetection() }
        customUrlButton.setOnClickListener { example2CustomURLs() }
        addUrlButton.setOnClickListener { example3AddDynamicURLs() }
    }

    /**
     * 示例 1: 基本防火墙检测
     */
    private fun example1BasicDetection() {
        setButtonsEnabled(false)
        showProgress(true)
        updateStatus("🔍 开始防火墙检测...")
        hideDomain()

        CoroutineScope(Dispatchers.Main).launch {
            try {
                val domain = withContext(Dispatchers.IO) {
                    passGFW.getFinalServer("android-example-v2.0")
                }

                if (domain != null) {
                    updateStatus("✅ 找到可用服务器")
                    showDomain(domain)
                } else {
                    val error = passGFW.getLastError() ?: "未知错误"
                    updateStatus("❌ 检测失败: $error")
                }
            } catch (e: Exception) {
                updateStatus("❌ 异常: ${e.message}")
            } finally {
                setButtonsEnabled(true)
                showProgress(false)
            }
        }
    }

    /**
     * 示例 2: 自定义 URL 列表
     */
    private fun example2CustomURLs() {
        setButtonsEnabled(false)
        showProgress(true)
        updateStatus("🔍 使用自定义 URL 列表...")
        hideDomain()

        // 创建自定义 URL 列表
        val customURLs = listOf(
            URLEntry(method = "navigate", url = "https://github.com/zdypro888/passgfw"),
            URLEntry(method = "api", url = "http://localhost:8080/passgfw"),
            URLEntry(method = "api", url = "http://127.0.0.1:8080/passgfw"),
            URLEntry(method = "file", url = "http://cdn.example.com/list.txt", store = true)
        )

        passGFW.setURLList(customURLs)

        CoroutineScope(Dispatchers.Main).launch {
            try {
                val domain = withContext(Dispatchers.IO) {
                    passGFW.getFinalServer("custom-urls-example")
                }

                if (domain != null) {
                    updateStatus("✅ 成功: $domain")
                    showDomain(domain)
                } else {
                    updateStatus("❌ 所有 URL 检测失败")
                }
            } catch (e: Exception) {
                updateStatus("❌ 异常: ${e.message}")
            } finally {
                setButtonsEnabled(true)
                showProgress(false)
            }
        }
    }

    /**
     * 示例 3: 动态添加 URL
     */
    private fun example3AddDynamicURLs() {
        passGFW.addURL("api", "http://backup-server.example.com/passgfw")
        passGFW.addURL("api", "http://another-server.example.com/passgfw")
        updateStatus("➕ 动态添加了 2 个 URL")
    }

    private fun updateStatus(status: String) {
        statusText.text = status
    }

    private fun showDomain(domain: String) {
        domainText.text = "服务器: $domain"
        domainText.visibility = View.VISIBLE
    }

    private fun hideDomain() {
        domainText.visibility = View.GONE
    }

    private fun setButtonsEnabled(enabled: Boolean) {
        detectButton.isEnabled = enabled
        customUrlButton.isEnabled = enabled
        addUrlButton.isEnabled = enabled
    }

    private fun showProgress(show: Boolean) {
        progressBar.visibility = if (show) View.VISIBLE else View.GONE
    }
}
