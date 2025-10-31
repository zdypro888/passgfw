import SwiftUI
import PassGFW

/**
 * PassGFW iOS Example
 *
 * 一个演示 PassGFW 在 iOS 上使用的 SwiftUI 应用示例
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
 *    let domain = await client.getFinalServer("custom-data")
 *
 * 功能演示:
 *   - SwiftUI 集成
 *   - 异步检测
 *   - 状态管理
 *   - 自定义 URL 列表
 */

// MARK: - View Model

@MainActor
class PassGFWViewModel: ObservableObject {
    @Published var status: String = "就绪：点击按钮开始检测"
    @Published var isDetecting: Bool = false
    @Published var foundDomain: String?

    private let client = PassGFWClient()

    init() {
        // 配置日志级别
        client.setLogLevel(.info)
    }

    /// 示例 1: 基本防火墙检测
    func startBasicDetection() async {
        guard !isDetecting else { return }

        isDetecting = true
        status = "🔍 开始防火墙检测..."
        foundDomain = nil

        do {
            if let domain = await client.getFinalServer(customData: "ios-example-v2.0") {
                status = "✅ 找到可用服务器"
                foundDomain = domain
            } else {
                let error = client.getLastError() ?? "未知错误"
                status = "❌ 检测失败: \(error)"
            }
        } catch {
            status = "❌ 异常: \(error.localizedDescription)"
        }

        isDetecting = false
    }

    /// 示例 2: 使用自定义 URL 列表
    func startCustomURLDetection() async {
        guard !isDetecting else { return }

        isDetecting = true
        status = "🔍 使用自定义 URL 列表..."

        // 创建自定义 URL 列表
        let customURLs = [
            URLEntry(method: "navigate", url: "https://github.com/zdypro888/passgfw"),
            URLEntry(method: "api", url: "http://192.168.1.1:8080/passgfw"),
            URLEntry(method: "api", url: "http://10.0.0.1:8080/passgfw"),
            URLEntry(method: "file", url: "http://cdn.example.com/list.txt", store: true)
        ]

        client.setURLList(customURLs)

        if let domain = await client.getFinalServer(customData: "custom-urls-example") {
            status = "✅ 成功: \(domain)"
            foundDomain = domain
        } else {
            status = "❌ 所有 URL 检测失败"
        }

        isDetecting = false
    }

    /// 示例 3: 动态添加 URL
    func addDynamicURL() {
        client.addURL(method: "api", url: "http://backup-server.example.com/passgfw")
        client.addURL(method: "api", url: "http://another-server.example.com/passgfw")

        status = "➕ 动态添加了 2 个 URL"
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var viewModel = PassGFWViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 标题
                Text("PassGFW iOS 示例")
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

                    if let domain = viewModel.foundDomain {
                        HStack {
                            Text("服务器:")
                                .font(.headline)
                            Text(domain)
                                .font(.body)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                // 按钮组
                VStack(spacing: 15) {
                    // 基本检测按钮
                    Button(action: {
                        Task {
                            await viewModel.startBasicDetection()
                        }
                    }) {
                        HStack {
                            Image(systemName: "network")
                            Text("基本检测")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(viewModel.isDetecting)

                    // 自定义 URL 检测按钮
                    Button(action: {
                        Task {
                            await viewModel.startCustomURLDetection()
                        }
                    }) {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("自定义 URL 检测")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(viewModel.isDetecting)

                    // 动态添加 URL 按钮
                    Button(action: {
                        viewModel.addDynamicURL()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("动态添加 URL")
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
