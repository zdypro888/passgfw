package com.example.passgfw

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.passgfw.PassGFW
import com.passgfw.URLEntry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * PassGFW Android Example
 *
 * 一个演示 PassGFW 在 Android 上使用的示例 Activity
 *
 * 集成步骤:
 * 1. 添加依赖到 build.gradle:
 *    implementation files('libs/passgfw-release.aar')
 *
 * 2. 在 AndroidManifest.xml 添加网络权限:
 *    <uses-permission android:name="android.permission.INTERNET" />
 *
 * 3. 在 Activity 中使用:
 *    val passGFW = PassGFW(this)
 *    val domain = passGFW.getFinalServer("custom-data")
 *
 * 功能演示:
 *   - 基本的防火墙检测
 *   - 自定义 URL 列表
 *   - 日志级别控制
 *   - 错误处理
 */
class PassGFWExampleActivity : AppCompatActivity() {

    private val TAG = "PassGFWExample"
    private lateinit var passGFW: PassGFW
    private lateinit var statusText: TextView
    private lateinit var detectButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // 初始化视图
        statusText = findViewById(R.id.statusText)
        detectButton = findViewById(R.id.detectButton)

        // 创建 PassGFW 实例（需要 Context）
        passGFW = PassGFW(applicationContext)

        // 设置日志级别
        passGFW.setLoggingEnabled(true)

        // 设置按钮点击事件
        detectButton.setOnClickListener {
            detectButton.isEnabled = false
            statusText.text = "检测中..."

            // 示例1: 基本检测
            example1BasicDetection()
        }

        updateStatus("就绪：点击按钮开始检测")
    }

    /**
     * 示例 1: 基本防火墙检测
     */
    private fun example1BasicDetection() {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                updateStatus("🔍 开始防火墙检测...")
                Log.i(TAG, "Starting firewall detection")

                // 在后台线程执行网络请求
                val domain = withContext(Dispatchers.IO) {
                    passGFW.getFinalServer("android-example-v2.0")
                }

                if (domain != null) {
                    updateStatus("✅ 找到可用服务器: $domain")
                    Log.i(TAG, "Found server: $domain")
                } else {
                    val error = passGFW.getLastError() ?: "未知错误"
                    updateStatus("❌ 检测失败: $error")
                    Log.e(TAG, "Detection failed: $error")
                }
            } catch (e: Exception) {
                updateStatus("❌ 异常: ${e.message}")
                Log.e(TAG, "Exception during detection", e)
            } finally {
                detectButton.isEnabled = true
            }
        }
    }

    /**
     * 示例 2: 使用自定义 URL 列表
     */
    private fun example2CustomURLs() {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                updateStatus("🔍 使用自定义 URL 列表...")

                // 创建自定义 URL 列表
                val customURLs = listOf(
                    URLEntry("navigate", "https://github.com/zdypro888/passgfw"),
                    URLEntry("api", "http://192.168.1.100:8080/passgfw"),
                    URLEntry("api", "http://10.0.0.1:8080/passgfw"),
                    URLEntry("file", "http://cdn.example.com/list.txt", store = true)
                )

                passGFW.setURLList(customURLs)

                val domain = withContext(Dispatchers.IO) {
                    passGFW.getFinalServer("custom-urls-example")
                }

                if (domain != null) {
                    updateStatus("✅ 成功: $domain")
                } else {
                    updateStatus("❌ 所有 URL 检测失败")
                }
            } catch (e: Exception) {
                updateStatus("❌ 异常: ${e.message}")
            } finally {
                detectButton.isEnabled = true
            }
        }
    }

    /**
     * 示例 3: 动态添加 URL
     */
    private fun example3DynamicURLs() {
        passGFW.addURL("api", "http://backup-server.example.com/passgfw")
        passGFW.addURL("api", "http://another-server.example.com/passgfw")

        Log.i(TAG, "Dynamically added 2 URLs")
        updateStatus("动态添加了 2 个 URL")
    }

    private fun updateStatus(message: String) {
        statusText.text = message
    }
}

/**
 * 对应的布局文件 (res/layout/activity_main.xml):
 *
 * <?xml version="1.0" encoding="utf-8"?>
 * <LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
 *     android:layout_width="match_parent"
 *     android:layout_height="match_parent"
 *     android:orientation="vertical"
 *     android:padding="16dp">
 *
 *     <TextView
 *         android:layout_width="match_parent"
 *         android:layout_height="wrap_content"
 *         android:text="PassGFW Android 示例"
 *         android:textSize="24sp"
 *         android:textStyle="bold"
 *         android:gravity="center"
 *         android:layout_marginBottom="32dp" />
 *
 *     <TextView
 *         android:id="@+id/statusText"
 *         android:layout_width="match_parent"
 *         android:layout_height="wrap_content"
 *         android:text="就绪"
 *         android:textSize="16sp"
 *         android:padding="16dp"
 *         android:background="#f0f0f0"
 *         android:layout_marginBottom="16dp" />
 *
 *     <Button
 *         android:id="@+id/detectButton"
 *         android:layout_width="match_parent"
 *         android:layout_height="wrap_content"
 *         android:text="开始检测" />
 *
 * </LinearLayout>
 */
