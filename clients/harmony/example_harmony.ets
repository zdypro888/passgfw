/**
 * PassGFW HarmonyOS Example
 *
 * 一个演示 PassGFW 在 HarmonyOS 上使用的示例页面
 *
 * 集成步骤:
 * 1. 将 PassGFW HAR 包添加到项目
 * 2. 在 module.json5 添加网络权限:
 *    "requestPermissions": [
 *      { "name": "ohos.permission.INTERNET" }
 *    ]
 *
 * 3. 在页面中使用:
 *    import { PassGFW } from '@ohos/passgfw'
 *    const passGFW = new PassGFW()
 *    await passGFW.initialize(this.context)
 *    const domain = await passGFW.getFinalServer("custom-data")
 *
 * 功能演示:
 *   - 基本防火墙检测
 *   - 自定义 URL 列表
 *   - 状态管理
 *   - 错误处理
 */

import { PassGFW, URLEntry, LogLevel } from '@ohos/passgfw'
import { common } from '@kit.AbilityKit'

@Entry
@Component
struct PassGFWExample {
  @State statusText: string = '就绪：点击按钮开始检测'
  @State foundDomain: string = ''
  @State isDetecting: boolean = false

  private passGFW: PassGFW = new PassGFW()
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext

  async aboutToAppear() {
    try {
      // 初始化 PassGFW（必须）
      await this.passGFW.initialize(this.context)

      // 配置日志级别
      this.passGFW.setLogLevel(LogLevel.INFO)

      console.info('[PassGFWExample] Initialized successfully')
    } catch (error) {
      console.error('[PassGFWExample] Initialization failed:', error.message)
      this.statusText = '初始化失败: ' + error.message
    }
  }

  /**
   * 示例 1: 基本防火墙检测
   */
  async startBasicDetection() {
    if (this.isDetecting) return

    this.isDetecting = true
    this.statusText = '🔍 开始防火墙检测...'
    this.foundDomain = ''

    try {
      const domain = await this.passGFW.getFinalServer('harmony-example-v2.0')

      if (domain) {
        this.statusText = '✅ 找到可用服务器'
        this.foundDomain = domain
        console.info('[PassGFWExample] Found server:', domain)
      } else {
        const error = this.passGFW.getLastError() || '未知错误'
        this.statusText = '❌ 检测失败: ' + error
        console.error('[PassGFWExample] Detection failed:', error)
      }
    } catch (error) {
      this.statusText = '❌ 异常: ' + error.message
      console.error('[PassGFWExample] Exception:', error)
    } finally {
      this.isDetecting = false
    }
  }

  /**
   * 示例 2: 使用自定义 URL 列表
   */
  async startCustomURLDetection() {
    if (this.isDetecting) return

    this.isDetecting = true
    this.statusText = '🔍 使用自定义 URL 列表...'

    try {
      // 创建自定义 URL 列表
      const customURLs: URLEntry[] = [
        { method: 'navigate', url: 'https://github.com/zdypro888/passgfw' },
        { method: 'api', url: 'http://192.168.1.1:8080/passgfw' },
        { method: 'api', url: 'http://10.0.0.1:8080/passgfw' },
        { method: 'file', url: 'http://cdn.example.com/list.txt', store: true }
      ]

      this.passGFW.setURLList(customURLs)

      const domain = await this.passGFW.getFinalServer('custom-urls-example')

      if (domain) {
        this.statusText = '✅ 成功: ' + domain
        this.foundDomain = domain
      } else {
        this.statusText = '❌ 所有 URL 检测失败'
      }
    } catch (error) {
      this.statusText = '❌ 异常: ' + error.message
    } finally {
      this.isDetecting = false
    }
  }

  /**
   * 示例 3: 动态添加 URL
   */
  addDynamicURLs() {
    this.passGFW.addURL('api', 'http://backup-server.example.com/passgfw')
    this.passGFW.addURL('api', 'http://another-server.example.com/passgfw')

    this.statusText = '➕ 动态添加了 2 个 URL'
    console.info('[PassGFWExample] Added 2 dynamic URLs')
  }

  build() {
    Column() {
      // 标题
      Text('PassGFW HarmonyOS 示例')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 30 })

      // 状态显示区域
      Column() {
        Text('状态:')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 10 })
          .alignSelf(ItemAlign.Start)

        Text(this.statusText)
          .fontSize(16)
          .fontColor(Color.Gray)
          .padding(16)
          .width('100%')
          .backgroundColor('#f0f0f0')
          .borderRadius(8)

        if (this.foundDomain) {
          Row() {
            Text('服务器:')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
            Text(this.foundDomain)
              .fontSize(16)
              .fontColor('#007AFF')
              .margin({ left: 8 })
          }
          .margin({ top: 10 })
          .alignSelf(ItemAlign.Start)
        }
      }
      .padding({ left: 20, right: 20 })
      .margin({ bottom: 30 })

      // 按钮组
      Column({ space: 15 }) {
        // 基本检测按钮
        Button('基本检测')
          .width('90%')
          .height(50)
          .fontSize(18)
          .backgroundColor('#007AFF')
          .enabled(!this.isDetecting)
          .onClick(() => {
            this.startBasicDetection()
          })

        // 自定义 URL 检测按钮
        Button('自定义 URL 检测')
          .width('90%')
          .height(50)
          .fontSize(18)
          .backgroundColor('#34C759')
          .enabled(!this.isDetecting)
          .onClick(() => {
            this.startCustomURLDetection()
          })

        // 动态添加 URL 按钮
        Button('动态添加 URL')
          .width('90%')
          .height(50)
          .fontSize(18)
          .backgroundColor('#FF9500')
          .enabled(!this.isDetecting)
          .onClick(() => {
            this.addDynamicURLs()
          })
      }
      .width('100%')
      .margin({ bottom: 30 })

      // 加载指示器
      if (this.isDetecting) {
        LoadingProgress()
          .width(40)
          .height(40)
          .margin({ top: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}
