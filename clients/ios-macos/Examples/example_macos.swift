#!/usr/bin/env swift

/*
 * PassGFW macOS Example
 *
 * 演示 PassGFW v2.2 在 macOS 上的使用
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
 *   - 基本的防火墙检测（使用内置URL列表）
 *   - 自定义数据发送
 *   - 缓存机制（retry参数）
 */

import Foundation
#if canImport(PassGFW)
import PassGFW
#endif

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
// 示例 1: 首次检测
// ============================================================================

func example1_FirstDetection() async {
    printSection("示例 1: 首次检测（无缓存）")

    print("📝 说明: 使用 retry=false 进行首次检测")
    print("")

    // 创建 PassGFW 实例
    let client = PassGFWClient()

    // 设置日志级别
    client.setLogLevel(.info)

    print("🔍 开始检测...")
    print("⚠️  确保服务器正在运行: cd server && go run main.go -port=8080")
    print("")

    // 执行首次检测（retry=false）
    if let result = await client.getDomains(retry: false, customData: "macos-example") {
        print("\n✅ 检测成功!")
        print("📦 服务器返回数据:")
        for (key, value) in result {
            print("   - \(key): \(value)")
        }
        print("")
    } else {
        if let error = client.getLastError() {
            print("\n❌ 检测失败: \(error)\n")
        } else {
            print("\n❌ 检测失败: 未知错误\n")
        }
    }
}

// ============================================================================
// 示例 2: 使用缓存
// ============================================================================

func example2_CachedResult() async {
    printSection("示例 2: 使用缓存（快速返回）")

    print("📝 说明: 使用 retry=false 返回缓存结果")
    print("")

    let client = PassGFWClient()
    client.setLogLevel(.info)

    print("🔍 第一次检测（建立缓存）...")
    let _ = await client.getDomains(retry: false)

    print("\n🔍 第二次检测（使用缓存）...")
    let start = Date()
    if let result = await client.getDomains(retry: false) {
        let duration = Date().timeIntervalSince(start)
        print("\n✅ 立即返回缓存结果（耗时: \(String(format: "%.3f", duration))秒）")
        print("📦 数据: \(result)")
        print("")
    }
}

// ============================================================================
// 示例 3: 强制刷新
// ============================================================================

func example3_ForceRefresh() async {
    printSection("示例 3: 强制刷新（重新检测）")

    print("📝 说明: 使用 retry=true 强制重新检测")
    print("")

    let client = PassGFWClient()
    client.setLogLevel(.info)

    print("🔍 第一次检测...")
    let _ = await client.getDomains(retry: false)

    print("\n🔄 强制刷新（retry=true）...")
    if let result = await client.getDomains(retry: true) {
        print("\n✅ 刷新成功，获取最新数据")
        print("📦 数据: \(result)")
        print("")
    }
}

// ============================================================================
// 示例 4: 自定义数据
// ============================================================================

func example4_CustomData() async {
    printSection("示例 4: 发送自定义数据")

    print("📝 说明: 使用 customData 参数发送自定义数据给服务器")
    print("")

    let client = PassGFWClient()
    client.setLogLevel(.debug)

    // 自定义数据（可以是任何字符串，通常是JSON）
    let customData = """
    {
        "app_version": "2.2.0",
        "platform": "macos",
        "user_id": "example-user-123"
    }
    """

    print("📤 发送自定义数据:")
    print(customData)
    print("")

    print("🔍 开始检测...")
    if let result = await client.getDomains(retry: false, customData: customData) {
        print("\n✅ 检测成功")
        print("📦 服务器返回: \(result)")
        print("")
    }
}

// ============================================================================
// 主函数
// ============================================================================

printHeader("PassGFW macOS 示例程序 v2.2")

print("本示例演示了 PassGFW v2.2 的简化 API:")
print("  1. 首次检测（无缓存）")
print("  2. 使用缓存（快速返回）")
print("  3. 强制刷新（重新检测）")
print("  4. 发送自定义数据")
print("")

print("选择要运行的示例 (1-4), 或按 Enter 运行所有示例: ", terminator: "")

let choice = readLine() ?? ""

Task {
    switch choice {
    case "1":
        await example1_FirstDetection()
    case "2":
        await example2_CachedResult()
    case "3":
        await example3_ForceRefresh()
    case "4":
        await example4_CustomData()
    default:
        // 运行所有示例
        await example1_FirstDetection()
        await example2_CachedResult()
        await example3_ForceRefresh()
        await example4_CustomData()
    }

    print("\n╔═══════════════════════════════════════════════════════════════╗")
    print("║  示例程序运行完毕                                              ║")
    print("╚═══════════════════════════════════════════════════════════════╝\n")

    exit(0)
}

// 保持程序运行
RunLoop.main.run()
