package com.passgfw.example

import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.passgfw.PassGFW
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * PassGFW Android 测试应用 v2.2
 */
class MainActivity : AppCompatActivity() {

    private lateinit var passGFW: PassGFW
    private lateinit var statusText: TextView
    private lateinit var resultText: TextView
    private lateinit var detectButton: Button
    private lateinit var refreshButton: Button
    private lateinit var customDataButton: Button
    private lateinit var progressBar: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // 初始化视图
        statusText = findViewById(R.id.statusText)
        resultText = findViewById(R.id.domainText)
        detectButton = findViewById(R.id.detectButton)
        refreshButton = findViewById(R.id.customUrlButton)
        customDataButton = findViewById(R.id.addUrlButton)
        progressBar = findViewById(R.id.progressBar)

        // 创建 PassGFW 实例
        passGFW = PassGFW(applicationContext)
        passGFW.setLoggingEnabled(true)

        // 更新按钮文本
        detectButton.text = "首次检测"
        refreshButton.text = "强制刷新"
        customDataButton.text = "自定义数据"

        // 按钮事件
        detectButton.setOnClickListener { example1FirstDetection() }
        refreshButton.setOnClickListener { example2ForceRefresh() }
        customDataButton.setOnClickListener { example3CustomData() }
    }

    /**
     * 示例 1: 首次检测（使用缓存）
     */
    private fun example1FirstDetection() {
        setButtonsEnabled(false)
        showProgress(true)
        updateStatus("🔍 开始检测（retry=false）...")
        hideResult()

        CoroutineScope(Dispatchers.Main).launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    passGFW.getDomains(retry = false)
                }

                if (result != null) {
                    updateStatus("✅ 检测成功")
                    showResult(result)
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
     * 示例 2: 强制刷新
     */
    private fun example2ForceRefresh() {
        setButtonsEnabled(false)
        showProgress(true)
        updateStatus("🔄 强制刷新（retry=true）...")
        hideResult()

        CoroutineScope(Dispatchers.Main).launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    passGFW.getDomains(retry = true)
                }

                if (result != null) {
                    updateStatus("✅ 刷新成功")
                    showResult(result)
                } else {
                    updateStatus("❌ 刷新失败")
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
     * 示例 3: 发送自定义数据
     */
    private fun example3CustomData() {
        setButtonsEnabled(false)
        showProgress(true)
        updateStatus("📤 发送自定义数据...")
        hideResult()

        // 创建自定义数据
        val customData = JSONObject().apply {
            put("app_version", "2.2.0")
            put("platform", "android")
            put("user_id", "example-user-123")
        }.toString()

        CoroutineScope(Dispatchers.Main).launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    passGFW.getDomains(retry = false, customData = customData)
                }

                if (result != null) {
                    updateStatus("✅ 成功（已发送自定义数据）")
                    showResult(result)
                } else {
                    updateStatus("❌ 失败")
                }
            } catch (e: Exception) {
                updateStatus("❌ 异常: ${e.message}")
            } finally {
                setButtonsEnabled(true)
                showProgress(false)
            }
        }
    }

    private fun updateStatus(status: String) {
        statusText.text = status
    }

    private fun showResult(result: Map<String, Any>) {
        val resultStr = result.entries.joinToString("\n") { (key, value) ->
            "$key: $value"
        }
        resultText.text = "返回数据:\n$resultStr"
        resultText.visibility = View.VISIBLE
    }

    private fun hideResult() {
        resultText.visibility = View.GONE
    }

    private fun setButtonsEnabled(enabled: Boolean) {
        detectButton.isEnabled = enabled
        refreshButton.isEnabled = enabled
        customDataButton.isEnabled = enabled
    }

    private fun showProgress(show: Boolean) {
        progressBar.visibility = if (show) View.VISIBLE else View.GONE
    }
}
