import SwiftUI
import PassGFW

/**
 * PassGFW iOS Example v2.2
 *
 * 一个演示 PassGFW v2.2 在 iOS 上使用的 SwiftUI 应用示例
 *
 * 集成步骤:
 * 1. 添加 PassGFW 框架到项目
 * 2. 在 Info.plist 添加网络权限:
 *    <key>NSAppTransportSecurity</key>
 *    <dict>
 *        <key>NSAllowsArbitraryLoads</key>
 *        <true/>
 *    </dict>
 *
 * 3. 在视图中使用:
 *    let client = PassGFWClient()
 *    let result = await client.getDomains(retry: false)
 *
 * 功能演示:
 *   - SwiftUI 集成
 *   - 异步检测
 *   - 状态管理
 *   - 缓存机制
 *   - 自定义数据
 */

// MARK: - View Model

@MainActor
class PassGFWViewModel: ObservableObject {
    @Published var status: String = "就绪：点击按钮开始检测"
    @Published var isDetecting: Bool = false
    @Published var resultData: [String: Any]?

    private let client = PassGFWClient()

    init() {
        // 配置日志级别
        client.setLogLevel(.info)
    }

    /// 示例 1: 首次检测（使用缓存）
    func startFirstDetection() async {
        guard !isDetecting else { return }

        isDetecting = true
        status = "🔍 开始检测（retry=false）..."
        resultData = nil

        do {
            if let result = await client.getDomains(retry: false, customData: "ios-example-v2.2") {
                status = "✅ 检测成功"
                resultData = result
            } else {
                let error = client.getLastError() ?? "未知错误"
                status = "❌ 检测失败: \(error)"
            }
        } catch {
            status = "❌ 异常: \(error.localizedDescription)"
        }

        isDetecting = false
    }

    /// 示例 2: 强制刷新
    func startForceRefresh() async {
        guard !isDetecting else { return }

        isDetecting = true
        status = "🔄 强制刷新（retry=true）..."

        if let result = await client.getDomains(retry: true) {
            status = "✅ 刷新成功"
            resultData = result
        } else {
            status = "❌ 刷新失败"
        }

        isDetecting = false
    }

    /// 示例 3: 发送自定义数据
    func startCustomDataDetection() async {
        guard !isDetecting else { return }

        isDetecting = true
        status = "📤 发送自定义数据..."

        // 创建自定义数据
        let customData = """
        {
            "app_version": "2.2.0",
            "platform": "ios",
            "user_id": "example-user-123"
        }
        """

        if let result = await client.getDomains(retry: false, customData: customData) {
            status = "✅ 成功（已发送自定义数据）"
            resultData = result
        } else {
            status = "❌ 失败"
        }

        isDetecting = false
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var viewModel = PassGFWViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 标题
                Text("PassGFW iOS v2.2")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)

                // 状态显示
                VStack(alignment: .leading, spacing: 10) {
                    Text("状态:")
                        .font(.headline)

                    Text(viewModel.status)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)

                    if let result = viewModel.resultData {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("返回数据:")
                                .font(.headline)

                            ForEach(Array(result.keys.sorted()), id: \.self) { key in
                                HStack {
                                    Text("\(key):")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(String(describing: result[key] ?? ""))")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // 按钮组
                VStack(spacing: 15) {
                    // 首次检测按钮
                    Button(action: {
                        Task {
                            await viewModel.startFirstDetection()
                        }
                    }) {
                        HStack {
                            Image(systemName: "network")
                            Text("首次检测")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(viewModel.isDetecting)

                    // 强制刷新按钮
                    Button(action: {
                        Task {
                            await viewModel.startForceRefresh()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("强制刷新")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(viewModel.isDetecting)

                    // 自定义数据按钮
                    Button(action: {
                        Task {
                            await viewModel.startCustomDataDetection()
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("自定义数据")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(viewModel.isDetecting)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)

                if viewModel.isDetecting {
                    ProgressView("检测中...")
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - App Entry Point

@main
struct PassGFWExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
