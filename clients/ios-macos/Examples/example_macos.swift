#!/usr/bin/env swift

/*
 * PassGFW macOS Example
 *
 * 一个演示 PassGFW 在 macOS 上使用的命令行工具示例
 *
 * 构建并运行:
 *   cd clients/ios-macos
 *   swift build
 *   .build/debug/PassGFWExample
 *
 * 或直接运行:
 *   swift run
 *
 * 功能演示:
 *   - 基本的防火墙检测
 *   - 自定义数据发送
 *   - 日志级别控制
 *   - 错误处理
 */

import Foundation
#if canImport(PassGFW)
import PassGFW
#endif

// ============================================================================
// 配置
// ============================================================================

let CUSTOM_DATA = "macos-example-v2.0"

// ============================================================================
// 辅助函数
// ============================================================================

func printHeader(_ title: String) {
    print("\n╔═══════════════════════════════════════════════════════════════╗")
    print("║ \(title.padding(toLength: 61, withPad: " ", startingAt: 0)) ║")
    print("╚═══════════════════════════════════════════════════════════════╝\n")
}

func printSection(_ title: String) {
    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  \(title)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
}

// ============================================================================
// 示例 1: 基本检测
// ============================================================================

func example1_BasicDetection() async {
    printSection("示例 1: 基本防火墙检测")

    print("📝 说明: 使用默认配置进行防火墙检测")
    print("")

    // 创建 PassGFW 实例
    let client = PassGFWClient()

    // 启用 debug 日志
    client.setLogLevel(.debug)

    print("🔍 开始检测...")
    print("⚠️  注意: 这将阻塞直到找到可用服务器")
    print("⚠️  确保服务器正在运行: cd server && go run main.go")
    print("")

    // 执行检测
    if let domain = await client.getFinalServer(customData: CUSTOM_DATA) {
        print("\n✅ 找到可用服务器: \(domain)")
        print("   可以使用此域名进行后续通信\n")
    } else {
        if let error = client.getLastError() {
            print("\n❌ 检测失败: \(error)\n")
        } else {
            print("\n❌ 检测失败: 未知错误\n")
        }
    }
}

// ============================================================================
// 示例 2: 自定义 URL 列表
// ============================================================================

func example2_CustomURLs() async {
    printSection("示例 2: 使用自定义 URL 列表")

    print("📝 说明: 动态设置要检测的 URL 列表")
    print("")

    // 创建 PassGFW 实例
    let client = PassGFWClient()
    client.setLogLevel(.info)

    // 自定义 URL 列表（支持多种 method）
    let customURLs = [
        URLEntry(method: "navigate", url: "https://github.com/zdypro888/passgfw"),
        URLEntry(method: "api", url: "http://localhost:8080/passgfw"),
        URLEntry(method: "api", url: "http://127.0.0.1:8080/passgfw"),
        URLEntry(method: "file", url: "http://localhost:8080/list.txt", store: true)
    ]

    print("📋 设置自定义 URL 列表:")
    for (index, entry) in customURLs.enumerated() {
        let storeTag = entry.store ? " [持久化]" : ""
        print("   \(index + 1). [\(entry.method)] \(entry.url)\(storeTag)")
    }
    print("")

    client.setURLList(customURLs)

    print("🔍 开始检测...")
    if let domain = await client.getFinalServer(customData: "custom-urls-example") {
        print("\n✅ 成功: \(domain)\n")
    } else {
        print("\n❌ 所有 URL 检测失败\n")
    }
}

// ============================================================================
// 示例 3: 错误处理
// ============================================================================

func example3_ErrorHandling() async {
    printSection("示例 3: 错误处理演示")

    print("📝 说明: 演示如何处理检测失败的情况")
    print("")

    let client = PassGFWClient()
    client.setLogLevel(.error)  // 只显示错误日志

    // 故意使用无效的 URL
    let invalidURLs = [
        URLEntry(method: "api", url: "http://invalid-domain-123456.com/passgfw"),
        URLEntry(method: "api", url: "http://localhost:9999/passgfw")  // 假设此端口未监听
    ]

    client.setURLList(invalidURLs)

    print("🔍 尝试连接无效服务器（会失败）...")
    print("⏱  等待超时...\n")

    // 注意: 这会循环重试，实际使用中应该设置超时
    // 这里我们只等待几秒钟然后退出
    let result: String? = await withCheckedContinuation { continuation in
        Task {
            // 在后台执行检测
            let _ = await client.getFinalServer(customData: "error-example")
            continuation.resume(returning: nil)
        }

        // 5秒后超时
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            continuation.resume(returning: "timeout")
        }
    }

    if result == "timeout" {
        print("⏱  检测超时（这是预期的，因为服务器不可用）")
        if let error = client.getLastError() {
            print("   最后错误: \(error)")
        }
    }
    print("")
}

// ============================================================================
// 示例 4: 动态添加 URL
// ============================================================================

func example4_DynamicURLs() async {
    printSection("示例 4: 动态添加 URL")

    print("📝 说明: 在运行时动态添加检测 URL")
    print("")

    let client = PassGFWClient()
    client.setLogLevel(.info)

    // 从其他来源动态获取 URL
    let dynamicURLs = [
        "http://localhost:8080/passgfw",
        "http://127.0.0.1:8080/passgfw"
    ]

    print("➕ 动态添加 URL:")
    for url in dynamicURLs {
        client.addURL(method: "api", url: url)
        print("   - \(url)")
    }
    print("")

    print("🔍 开始检测...")
    if let domain = await client.getFinalServer(customData: "dynamic-example") {
        print("\n✅ 找到服务器: \(domain)\n")
    } else {
        print("\n❌ 检测失败\n")
    }
}

// ============================================================================
// 主函数
// ============================================================================

printHeader("PassGFW macOS 示例程序 v2.0")

print("本示例演示了 PassGFW 库的各种使用方式:")
print("  1. 基本防火墙检测")
print("  2. 自定义 URL 列表")
print("  3. 错误处理")
print("  4. 动态添加 URL")
print("")

print("选择要运行的示例 (1-4), 或按 Enter 运行所有示例: ", terminator: "")

let choice = readLine() ?? ""

Task {
    switch choice {
    case "1":
        await example1_BasicDetection()
    case "2":
        await example2_CustomURLs()
    case "3":
        await example3_ErrorHandling()
    case "4":
        await example4_DynamicURLs()
    default:
        // 运行所有示例
        await example1_BasicDetection()
        await example2_CustomURLs()
        await example3_ErrorHandling()
        await example4_DynamicURLs()
    }

    print("\n╔═══════════════════════════════════════════════════════════════╗")
    print("║  示例程序运行完毕                                              ║")
    print("╚═══════════════════════════════════════════════════════════════╝\n")

    exit(0)
}

// 保持程序运行
RunLoop.main.run()
