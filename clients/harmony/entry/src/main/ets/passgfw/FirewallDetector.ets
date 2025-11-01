import { NetworkClient } from './NetworkClient';
import { CryptoHelper } from './CryptoHelper';
import { Config, URLEntry } from './Config';
import { Logger } from './Logger';
import { URLManager } from './URLManager';
import { PreferencesStorage } from './SecureStorage';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

/**
 * Firewall Detector - Core detection logic
 */
export class FirewallDetector {
  private networkClient: NetworkClient;
  private cryptoHelper: CryptoHelper;
  private urlManager: URLManager | null = null;
  private lastError: string | null = null;
  private initialized: boolean = false;
  private context: common.UIAbilityContext | null = null;

  // 记录已打开的 navigate URLs，避免重复打开
  private openedNavigateURLs: Set<string> = new Set();

  constructor() {
    this.networkClient = new NetworkClient();
    this.cryptoHelper = new CryptoHelper();

    // Initialize crypto with public key
    this.cryptoHelper.setPublicKey(Config.getPublicKey());
  }

  /**
   * 初始化检测器（加载内置 URL 和存储的 URL）
   * @param context UIAbilityContext（用于打开浏览器等操作）
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }

    // 保存 context
    this.context = context;

    // Initialize URLManager with secure storage
    const storage = new PreferencesStorage(context);
    this.urlManager = new URLManager(storage);

    // Initialize URL list (first time will use builtin URLs)
    await this.urlManager.initializeIfNeeded();

    Logger.getInstance().info(`FirewallDetector initialized`);

    this.initialized = true;
  }

  /**
   * Get final server domain (main entry point)
   */
  async getFinalServer(customData?: string): Promise<string | null> {
    Logger.getInstance().debug(`getFinalServer() called with customData: ${customData || 'null'}`);

    // Loop infinitely until finding an available server
    while (true) {
      // Reload sorted URLs at the beginning of each cycle to get latest priorities
      const urls = this.urlManager ? await this.urlManager.getSortedURLs() : [];
      Logger.getInstance().debug(`Starting URL iteration with ${urls.length} sorted URLs`);

      const domain = Config.ENABLE_CONCURRENT_CHECK
        ? await this.checkURLsConcurrently(urls, customData, Config.CONCURRENT_CHECK_COUNT)
        : await this.checkURLsSequentially(urls, customData);

      if (domain) {
        return domain;
      }

      // All URLs failed, wait and retry
      this.lastError = 'All URL detection failed, retrying...';
      Logger.getInstance().warning(this.lastError);
      await this.sleep(Config.RETRY_INTERVAL);
    }
  }

  /**
   * Set URL list
   * @deprecated Use addURL instead for better control
   * URLs will be persisted to storage
   */
  setURLList(entries: URLEntry[]): void {
    // 批量添加 URL 到存储（异步操作）
    if (this.urlManager) {
      entries.forEach(entry => {
        this.urlManager?.addURL(entry).then((success) => {
          if (success) {
            Logger.getInstance().info(`成功添加 URL 到存储: ${entry.url}`);
          }
        });
      });
    }
  }

  /**
   * Add URL to persistent storage
   * URL will be persisted and available in next detection
   */
  addURL(method: string, url: string): void {
    const entry: URLEntry = { method, url, store: false };
    if (this.urlManager) {
      this.urlManager.addURL(entry).then((success) => {
        if (success) {
          Logger.getInstance().info(`成功添加 URL 到存储: ${url}`);
        } else {
          Logger.getInstance().error(`添加 URL 失败: ${url}`);
        }
      });
    }
  }

  /**
   * Get last error
   */
  getLastError(): string | null {
    return this.lastError;
  }

  // MARK: - Private Methods

  /**
   * 串行检测 URLs（原逻辑）
   */
  private async checkURLsSequentially(
    entries: URLEntry[],
    customData: string | undefined,
    recursionDepth: number = 0
  ): Promise<string | null> {
    for (const entry of entries) {
      Logger.getInstance().debug(`Checking URL: ${entry.url} (method: ${entry.method}, depth: ${recursionDepth})`);

      const domain = await this.checkURLEntry(entry, customData, recursionDepth);
      if (domain) {
        Logger.getInstance().info(`Found available server: ${domain}`);
        // 异步记录成功
        if (this.urlManager) {
          this.urlManager.recordSuccess(entry.url);
        }
        return domain;
      }

      // 异步记录失败
      if (this.urlManager) {
        this.urlManager.recordFailure(entry.url);
      }
    }
    return null;
  }

  /**
   * 并发检测 URLs（批次间串行，批次内并发）
   *
   * 重要：navigate、remove 等特殊方法始终串行执行
   * 如果配置禁止 file 方法并发，file 也会串行执行
   */
  private async checkURLsConcurrently(
    entries: URLEntry[],
    customData: string | undefined,
    batchSize: number,
    recursionDepth: number = 0
  ): Promise<string | null> {
    // 边界检查：batchSize 必须 >= 1
    const safeBatchSize = Math.max(1, batchSize);
    if (batchSize <= 0) {
      Logger.getInstance().warning(`并发批次大小无效 (${batchSize})，已自动调整为 1`);
    }

    // 分离特殊方法和普通方法
    const specialMethods = new Set(['navigate', 'remove']);
    if (!Config.FILE_METHOD_CONCURRENT) {
      specialMethods.add('file');
    }

    const specialEntries = entries.filter(e => specialMethods.has(e.method.toLowerCase()));
    const normalEntries = entries.filter(e => !specialMethods.has(e.method.toLowerCase()));

    // 1. 先串行处理特殊方法
    if (specialEntries.length > 0) {
      Logger.getInstance().debug(`串行处理 ${specialEntries.length} 个特殊方法 URL（深度: ${recursionDepth}）`);
      for (const entry of specialEntries) {
        Logger.getInstance().debug(`串行检测: ${entry.url} (method: ${entry.method}, depth: ${recursionDepth})`);

        const domain = await this.checkURLEntry(entry, customData, recursionDepth);
        if (domain) {
          Logger.getInstance().info(`Found available server: ${domain} (from ${entry.url})`);
          // 异步记录成功
          if (this.urlManager) {
            this.urlManager.recordSuccess(entry.url);
          }
          return domain;
        } else {
          // 异步记录失败
          if (this.urlManager) {
            this.urlManager.recordFailure(entry.url);
          }
        }
      }
    }

    // 2. 再并发处理普通方法
    if (normalEntries.length === 0) {
      return null;
    }

    Logger.getInstance().debug(`并发处理 ${normalEntries.length} 个普通方法 URL（批次大小: ${safeBatchSize}）`);

    // 按批次处理
    for (let batchStart = 0; batchStart < normalEntries.length; batchStart += safeBatchSize) {
      const batchEnd = Math.min(batchStart + safeBatchSize, normalEntries.length);
      const batch = normalEntries.slice(batchStart, batchEnd);

      Logger.getInstance().debug(`并发检测批次: [${batchStart}..${batchEnd - 1}], 共 ${batch.length} 个 URL（深度: ${recursionDepth}）`);

      // 批次内并发检测（使用 Promise.all 等待所有结果）
      const promises = batch.map(entry =>
        this.checkURLEntry(entry, customData, recursionDepth)
          .then(domain => ({ entry, domain }))
      );

      // 等待所有结果（完整统计）
      const results = await Promise.all(promises);

      // 查找第一个成功
      let successDomain: string | null = null;
      const successIndex = results.findIndex(r => r.domain !== null);

      if (successIndex >= 0) {
        successDomain = results[successIndex].domain;
        Logger.getInstance().info(`Found available server: ${successDomain} (from ${results[successIndex].entry.url})`);
      }

      // 统计所有结果（包括成功后的其他结果）
      for (const result of results) {
        if (this.urlManager) {
          if (result.domain) {
            this.urlManager.recordSuccess(result.entry.url);
            Logger.getInstance().debug(`统计：${result.entry.url} 成功`);
          } else {
            this.urlManager.recordFailure(result.entry.url);
            Logger.getInstance().debug(`统计：${result.entry.url} 失败`);
          }
        }
      }

      // 如果找到成功，立即返回
      if (successDomain) {
        return successDomain;
      }

      // 批次全部失败，立即尝试下一批次
    }

    return null;
  }

  /**
   * 检查单个 URL Entry
   */
  private async checkURLEntry(entry: URLEntry, customData: string | undefined, recursionDepth: number): Promise<string | null> {
    this.lastError = null;

    // Check recursion depth limit（深度从0开始，允许 0 到 MAX_DEPTH-1）
    if (recursionDepth >= Config.MAX_LIST_RECURSION_DEPTH) {
      this.lastError = `Maximum list recursion depth exceeded: ${entry.url}`;
      Logger.getInstance().error(`Recursion depth limit reached (${recursionDepth} >= ${Config.MAX_LIST_RECURSION_DEPTH}) for URL: ${entry.url}`);
      return null;
    }

    // Handle "remove" method - 从存储中删除 URL
    if (entry.method.toLowerCase() === 'remove') {
      Logger.getInstance().info(`删除本地存储中的 URL: ${entry.url}`);
      if (this.urlManager) {
        if (await this.urlManager.removeURL(entry.url)) {
          Logger.getInstance().info(`成功删除 URL: ${entry.url}`);
        } else {
          Logger.getInstance().warning(`删除失败（URL 可能不存在）: ${entry.url}`);
        }
      }
      // 不检查此 URL，直接跳过
      return null;
    }

    // Handle "navigate" method - 打开浏览器
    if (entry.method.toLowerCase() === 'navigate') {
      // 检查是否已经打开过，避免重复打开
      if (this.openedNavigateURLs.has(entry.url)) {
        Logger.getInstance().debug(`Navigate URL 已打开过，跳过: ${entry.url}`);
        return null;
      }

      Logger.getInstance().info(`打开浏览器导航到: ${entry.url}`);

      // 尝试打开浏览器
      if (this.context) {
        try {
          const want = {
            action: 'ohos.want.action.viewData',
            entities: ['entity.system.browsable'],
            uri: entry.url
          };
          await this.context.startAbility(want);
          Logger.getInstance().info(`已在 HarmonyOS 默认浏览器中打开: ${entry.url}`);

          // 记录已打开
          this.openedNavigateURLs.add(entry.url);
        } catch (error) {
          Logger.getInstance().error(`打开浏览器失败: ${error.message}`);
        }
      } else {
        Logger.getInstance().error('Context 未初始化，无法打开浏览器');
      }

      // 打开浏览器后继续检测下一个 URL
      return null;
    }

    // Dispatch based on method
    let result: string | null = null;

    switch (entry.method.toLowerCase()) {
      case 'api':
        result = await this.checkAPIURL(entry.url, customData, recursionDepth);
        break;
      case 'file':
        result = await this.checkFileURL(entry.url, customData, recursionDepth);
        break;
      default:
        this.lastError = `Unknown method: ${entry.method}`;
        Logger.getInstance().error(`未知的 method '${entry.method}' for URL: ${entry.url}`);
        return null;
    }

    // 如果检查成功且 store=true，则异步持久化存储此 URL（不阻塞返回）
    if (result !== null && entry.store === true) {
      const storedEntry: URLEntry = { method: entry.method, url: entry.url };

      // 后台异步存储，不阻塞返回（不等待 Promise）
      if (this.urlManager) {
        this.urlManager.addURL(storedEntry).then((success) => {
          if (success) {
            Logger.getInstance().info(`后台存储成功: ${entry.url} (method: ${entry.method})`);
          } else {
            Logger.getInstance().error(`后台存储失败: ${entry.url}`);
          }
        }).catch((error) => {
          Logger.getInstance().error(`存储出错: ${error}`);
        });
        Logger.getInstance().info(`启动后台存储检测成功的 URL: ${entry.url} (method: ${entry.method})`);
      }
    }

    return result;
  }

  /**
   * Check an API URL with retry mechanism
   */
  private async checkAPIURL(url: string, customData: string | undefined, recursionDepth: number): Promise<string | null> {
    Logger.getInstance().debug(`CheckAPIURL() called for: ${url} with customData: ${customData || 'null'}`);

    if (!url || url.length === 0) {
      this.lastError = 'Empty URL provided';
      return null;
    }

    // Retry loop
    for (let attempt = 1; attempt <= Config.MAX_RETRIES; attempt++) {
      Logger.getInstance().debug(`Attempt ${attempt}/${Config.MAX_RETRIES} for URL: ${url}`);

      const domain = await this.checkNormalURLOnce(url, customData, recursionDepth);
      if (domain) {
        Logger.getInstance().info(`Successfully verified URL: ${url} on attempt ${attempt}`);
        return domain;
      }

      // If this was the last attempt, give up
      if (attempt === Config.MAX_RETRIES) {
        Logger.getInstance().warning(`All ${Config.MAX_RETRIES} attempts failed for URL: ${url}. Last error: ${this.lastError || 'unknown'}`);
        return null;
      }

      // Wait before retry
      Logger.getInstance().debug(`Waiting ${Config.RETRY_DELAY}ms before retry...`);
      await this.sleep(Config.RETRY_DELAY);
    }

    return null;
  }

  /**
   * Check a file URL (fetch sub-list and check each URL)
   */
  private async checkFileURL(url: string, customData: string | undefined, recursionDepth: number): Promise<string | null> {
    Logger.getInstance().debug(`CheckFileURL() called for: ${url} (depth: ${recursionDepth})`);

    if (!url || url.length === 0) {
      this.lastError = 'Empty file URL provided';
      return null;
    }

    // Fetch sub-list
    Logger.getInstance().debug(`Fetching sub-list from: ${url}`);
    const response = await this.networkClient.get(url);

    if (!response.success) {
      this.lastError = `GET request failed: ${url} - ${response.error}`;
      return null;
    }

    // Try to parse as JSON first (new format with urls array)
    const subEntries = this.parseURLEntriesJSON(response.body);
    if (subEntries && subEntries.length > 0) {
      // ✅ 去重：使用 URL 作为唯一标识
      const uniqueEntries: URLEntry[] = [];
      const seenURLs = new Set<string>();
      for (const entry of subEntries) {
        if (!seenURLs.has(entry.url)) {
          seenURLs.add(entry.url);
          uniqueEntries.push(entry);
        }
      }

      const duplicateCount = subEntries.length - uniqueEntries.length;
      if (duplicateCount > 0) {
        Logger.getInstance().warning(`去重：从 file 子列表中移除了 ${duplicateCount} 个重复 URL`);
      }

      Logger.getInstance().debug(`Fetched ${uniqueEntries.length} unique URL entries from JSON sub-list`);

      // ✅ 递归调用并发检测逻辑（保持一致性）
      return Config.ENABLE_CONCURRENT_CHECK
        ? await this.checkURLsConcurrently(uniqueEntries, customData, Config.CONCURRENT_CHECK_COUNT, recursionDepth + 1)
        : await this.checkURLsSequentially(uniqueEntries, customData, recursionDepth + 1);
    } else {
      // Fallback: parse as plain text URL list (legacy format)
      const subURLs = this.parseURLList(response.body);
      if (subURLs.length === 0) {
        this.lastError = `Sub-list empty or parse failed: ${url}`;
        return null;
      }

      // ✅ 去重：移除重复的 URL
      const uniqueURLs = Array.from(new Set(subURLs));
      const duplicateCount = subURLs.length - uniqueURLs.length;

      if (duplicateCount > 0) {
        Logger.getInstance().warning(`去重：从 file 子列表中移除了 ${duplicateCount} 个重复 URL (legacy format)`);
      }

      Logger.getInstance().debug(`Fetched ${uniqueURLs.length} unique URLs from text sub-list (legacy format)`);

      // Convert to URLEntry list (assume API method)
      const entries: URLEntry[] = uniqueURLs.map(u => ({ method: 'api', url: u }));

      // ✅ 递归调用并发检测逻辑
      return Config.ENABLE_CONCURRENT_CHECK
        ? await this.checkURLsConcurrently(entries, customData, Config.CONCURRENT_CHECK_COUNT, recursionDepth + 1)
        : await this.checkURLsSequentially(entries, customData, recursionDepth + 1);
    }

    // All URLs in sub-list failed
    Logger.getInstance().debug('All URLs in sub-list failed');
    this.lastError = `All URLs in sub-list failed: ${url}`;
    return null;
  }

  /**
   * 智能解析 URL entries（支持多种格式）
   * Supports:
   * 1. *PGFW*base64(URLEntry[] JSON)*PGFW* format (preferred, can embed anywhere)
   * 2. HTML with <pre>, <code>, or <script type="application/json"> tags
   * 3. Direct URLEntry[] JSON array format
   * 4. Legacy {"urls": [...]} format
   */
  private parseURLEntriesJSON(content: string): URLEntry[] | null {
    Logger.getInstance().debug(`开始智能解析内容（长度: ${content.length}）`);

    // Strategy 1: 优先尝试提取 *PGFW* 标记格式
    const extracted = this.extractPGFWContent(content);
    if (extracted) {
      Logger.getInstance().info('✓ 检测到 *PGFW* 标记格式');
      Logger.getInstance().debug(`提取的 base64 长度: ${extracted.length}`);

      // Decode base64
      try {
        const base64Helper = new util.Base64Helper();
        const decodedBytes = base64Helper.decodeSync(extracted);
        const textDecoder = util.TextDecoder.create();
        const decodedString = textDecoder.decodeToString(decodedBytes);

        Logger.getInstance().debug(`解码后的内容: ${decodedString.substring(0, 200)}...`);

        // Parse as URLEntry[] JSON array
        const entries = this.parseURLEntryArray(decodedString);
        if (entries) {
          Logger.getInstance().info(`✓ 成功从 *PGFW* 标记中解析出 ${entries.length} 个 URL entries`);
          return entries;
        }
      } catch (error) {
        Logger.getInstance().debug(`Base64 解码失败: ${error.message}`);
      }
    }

    // Strategy 2: 检测 HTML 格式
    if (content.toLowerCase().includes('<html') || content.toLowerCase().includes('<!doctype')) {
      Logger.getInstance().info('✓ 检测到 HTML 格式，尝试提取内容...');

      // 2a. 尝试从 <pre> 标签提取
      const preContent = this.extractHTMLTag(content, 'pre');
      if (preContent) {
        Logger.getInstance().debug('从 <pre> 标签提取到内容');
        const entries = this.parseURLEntryArray(preContent);
        if (entries) {
          Logger.getInstance().info(`✓ 成功从 <pre> 标签解析出 ${entries.length} 个 URL entries`);
          return entries;
        }
      }

      // 2b. 尝试从 <code> 标签提取
      const codeContent = this.extractHTMLTag(content, 'code');
      if (codeContent) {
        Logger.getInstance().debug('从 <code> 标签提取到内容');
        const entries = this.parseURLEntryArray(codeContent);
        if (entries) {
          Logger.getInstance().info(`✓ 成功从 <code> 标签解析出 ${entries.length} 个 URL entries`);
          return entries;
        }
      }

      // 2c. 尝试从 <script type="application/json"> 提取
      const scriptContent = this.extractJSONScript(content);
      if (scriptContent) {
        Logger.getInstance().debug('从 <script type="application/json"> 提取到内容');
        const entries = this.parseURLEntryArray(scriptContent);
        if (entries) {
          Logger.getInstance().info(`✓ 成功从 <script> 标签解析出 ${entries.length} 个 URL entries`);
          return entries;
        }
      }

      Logger.getInstance().debug('HTML 中未找到可解析的 JSON 内容');
    }

    // Strategy 3: 尝试直接解析为 URLEntry[] JSON 数组
    const directEntries = this.parseURLEntryArray(content);
    if (directEntries) {
      Logger.getInstance().info(`✓ 成功直接解析为 URLEntry[] 数组（${directEntries.length} 个 entries）`);
      return directEntries;
    }

    // Strategy 4: 尝试旧版 {"urls": [...]} 格式
    try {
      const json = JSON.parse(content);
      const urlsArray = json.urls;

      if (Array.isArray(urlsArray)) {
        const entries: URLEntry[] = [];
        for (const urlDict of urlsArray) {
          if (urlDict.method && urlDict.url) {
            entries.push({
              method: urlDict.method,
              url: urlDict.url,
              store: urlDict.store || false
            });
          }
        }
        if (entries.length > 0) {
          Logger.getInstance().info(`✓ 成功解析旧版 {"urls": [...]} 格式（${entries.length} 个 entries）`);
          return entries;
        }
      }
    } catch (error) {
      Logger.getInstance().debug(`旧版格式解析失败: ${error.message}`);
    }

    Logger.getInstance().warning('所有解析策略均失败');
    return null;
  }

  /**
   * 从 HTML 中提取指定标签的内容
   * 支持 HTML 实体解码
   */
  private extractHTMLTag(html: string, tag: string): string | null {
    try {
      // 匹配 <tag...>content</tag>，支持标签属性
      const pattern = new RegExp(`<${tag}[^>]*>(.*?)</${tag}>`, 'is');
      const match = html.match(pattern);
      if (!match || match.length < 2) return null;

      const content = match[1];

      // HTML 实体解码
      return this.decodeHTMLEntities(content);
    } catch (error) {
      Logger.getInstance().debug(`提取 HTML 标签 <${tag}> 失败: ${error.message}`);
      return null;
    }
  }

  /**
   * 从 HTML 中提取 <script type="application/json"> 的内容
   */
  private extractJSONScript(html: string): string | null {
    try {
      const pattern = /<script[^>]+type=["']application\/json["'][^>]*>(.*?)<\/script>/is;
      const match = html.match(pattern);
      if (!match || match.length < 2) return null;

      return match[1].trim();
    } catch (error) {
      Logger.getInstance().debug(`提取 JSON script 失败: ${error.message}`);
      return null;
    }
  }

  /**
   * HTML 实体解码
   */
  private decodeHTMLEntities(text: string): string {
    return text
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&amp;/g, '&')
      .trim();
  }

  /**
   * Extract content between *PGFW* markers
   */
  private extractPGFWContent(text: string): string | null {
    const startMarker = '*PGFW*';
    const endMarker = '*PGFW*';

    const startIndex = text.indexOf(startMarker);
    if (startIndex === -1) return null;

    const contentStart = startIndex + startMarker.length;
    const endIndex = text.indexOf(endMarker, contentStart);
    if (endIndex === -1) return null;

    return text.substring(contentStart, endIndex).trim();
  }

  /**
   * Parse URLEntry[] JSON array
   */
  private parseURLEntryArray(json: string): URLEntry[] | null {
    try {
      const array = JSON.parse(json);

      if (!Array.isArray(array)) return null;

      const entries: URLEntry[] = [];
      for (const item of array) {
        if (item.method && item.url) {
          entries.push({ method: item.method, url: item.url });
        }
      }

      return entries.length > 0 ? entries : null;
    } catch (error) {
      return null;
    }
  }

  /**
   * Check a normal URL once (no retry)
   */
  private async checkNormalURLOnce(url: string, customData: string | undefined, recursionDepth: number): Promise<string | null> {
    try {
      // 1. Generate random nonce
      const randomData = this.cryptoHelper.generateRandom(Config.NONCE_SIZE);
      const base64Helper = new util.Base64Helper();
      const randomBase64 = base64Helper.encodeToStringSync(randomData);
      Logger.getInstance().debug(`Generated random data: ${randomData.length} bytes`);

      // 2. Truncate custom data if too long
      let clientData = customData || '';
      if (clientData.length > Config.MAX_CLIENT_DATA_SIZE) {
        Logger.getInstance().warning(`client_data truncated from ${clientData.length} to ${Config.MAX_CLIENT_DATA_SIZE} bytes`);
        clientData = clientData.substring(0, Config.MAX_CLIENT_DATA_SIZE);
      }

      // 3. Build JSON payload
      const payload = {
        nonce: randomBase64,
        client_data: clientData
      };
      const payloadJSON = JSON.stringify(payload);
      Logger.getInstance().debug(`Payload JSON: ${payloadJSON}`);

      // 4. Encrypt payload
      const textEncoder = new util.TextEncoder();
      const payloadBytes = textEncoder.encodeInto(payloadJSON);
      const encryptedData = await this.cryptoHelper.encrypt(payloadBytes);

      if (!encryptedData) {
        this.lastError = 'Failed to encrypt data';
        return null;
      }

      const encryptedBase64 = base64Helper.encodeToStringSync(encryptedData);
      Logger.getInstance().debug(`Encrypted data: ${encryptedData.length} bytes`);

      // 5. Build request JSON
      const requestData = { data: encryptedBase64 };
      const requestBody = JSON.stringify(requestData);

      // 6. POST request
      const response = await this.networkClient.post(url, requestBody);
      if (!response.success) {
        this.lastError = `POST request failed: ${url} - ${response.error}`;
        return null;
      }

      // 7. Parse response JSON
      const responseJSON = JSON.parse(response.body);
      const returnedRandom = responseJSON.random;
      const signature = responseJSON.signature;

      if (!returnedRandom || !signature) {
        this.lastError = 'Response JSON missing required fields (random/signature)';
        return null;
      }

      // domain 和 urls 都是可选的
      const returnedDomain = responseJSON.domain;

      Logger.getInstance().debug(`Returned random: ${returnedRandom}`);
      if (returnedDomain) {
        Logger.getInstance().debug(`Returned domain: ${returnedDomain}`);
      }

      // 8. Verify signature (sign response without signature field)
      // CRITICAL: Must use sorted keys to match server serialization
      const payloadForSigning: Record<string, any> = {};
      Object.keys(responseJSON).sort().forEach(key => {
        if (key !== 'signature') {
          payloadForSigning[key] = responseJSON[key];
        }
      });

      const payloadJSON2 = JSON.stringify(payloadForSigning);
      Logger.getInstance().debug(`Payload for verification: ${payloadJSON2}`);

      const payloadData = textEncoder.encodeInto(payloadJSON2);
      const signatureData = base64Helper.decodeSync(signature);

      const verified = await this.cryptoHelper.verifySignature(payloadData, signatureData);
      if (!verified) {
        this.lastError = 'Signature verification failed';
        return null;
      }

      // 9. Verify random matches
      if (returnedRandom !== randomBase64) {
        const expectedPrefix = randomBase64.substring(0, 10);
        const actualPrefix = returnedRandom.substring(0, 10);
        this.lastError = `Random mismatch: expected: ${expectedPrefix}..., actual: ${actualPrefix}...`;
        return null;
      }

      // 10. 处理服务器返回的 urls 数组（如果有）
      if (responseJSON.urls && Array.isArray(responseJSON.urls)) {
        Logger.getInstance().debug(`Server returned ${responseJSON.urls.length} URLs in response`);

        const urlEntries: URLEntry[] = [];
        for (const urlDict of responseJSON.urls) {
          if (urlDict.method && urlDict.url) {
            urlEntries.push({
              method: urlDict.method,
              url: urlDict.url,
              store: urlDict.store || false
            });
          }
        }

        // 策略：如果有 domain，说明服务器可信，异步存储 store=true 的 URL（不阻塞返回）
        if (returnedDomain) {
          for (const entry of urlEntries) {
            if (entry.store === true && this.urlManager) {
              const storedEntry: URLEntry = { method: entry.method, url: entry.url };
              // 后台异步存储，不阻塞返回（不等待 Promise）
              this.urlManager.addURL(storedEntry).then((success) => {
                if (success) {
                  Logger.getInstance().info(`后台存储成功: ${entry.url}`);
                } else {
                  Logger.getInstance().error(`后台存储失败: ${entry.url}`);
                }
              }).catch((error) => {
                Logger.getInstance().error(`存储出错: ${error}`);
              });
              Logger.getInstance().info(`启动后台存储服务器推荐的 URL: ${entry.url} (method: ${entry.method})`);
            }
          }
        } else {
          // 没有 domain，循环检测 urls，只存储检测成功的
          Logger.getInstance().debug('No domain in response, checking URLs from server...');

          for (const entry of urlEntries) {
            Logger.getInstance().debug(`Checking server-provided URL: ${entry.url} (method: ${entry.method})`);

            const domain = await this.checkURLEntry(entry, customData, recursionDepth + 1);
            if (domain) {
              Logger.getInstance().info(`Server-provided URL succeeded: ${entry.url} -> ${domain}`);

              // 检测成功，异步存储（不阻塞返回）
              if (entry.store === true && this.urlManager) {
                const storedEntry: URLEntry = { method: entry.method, url: entry.url };
                // 不等待存储完成，立即返回
                this.urlManager.addURL(storedEntry).then((success) => {
                  if (success) {
                    Logger.getInstance().info(`后台存储成功: ${entry.url}`);
                  }
                }).catch((error) => {
                  Logger.getInstance().error(`存储出错: ${error}`);
                });
                Logger.getInstance().info(`启动后台存储检测成功的 URL: ${entry.url}`);
              }

              return domain;
            }

            Logger.getInstance().debug(`Server-provided URL failed: ${entry.url}, trying next...`);
            await this.sleep(Config.URL_INTERVAL);
          }

          this.lastError = 'All server-provided URLs failed';
          return null;
        }
      }

      // 11. 如果有 domain，返回它
      if (returnedDomain) {
        Logger.getInstance().debug(`Verification successful! Using domain: ${returnedDomain}`);
        return returnedDomain;
      }

      // 既没有 domain 也没有 urls
      this.lastError = 'Response has neither domain nor urls';
      return null;
    } catch (error) {
      this.lastError = `Exception: ${error?.message || 'unknown'}`;
      return null;
    }
  }

  /**
   * Parse URL list from text content
   */
  private parseURLList(content: string): string[] {
    const urls: string[] = [];

    // Try to extract content between *GFW* markers
    const marker = '*GFW*';
    const startIndex = content.indexOf(marker);

    if (startIndex !== -1) {
      const endIndex = content.indexOf(marker, startIndex + marker.length);
      if (endIndex !== -1) {
        const gfwContent = content.substring(startIndex + marker.length, endIndex).trim();

        if (gfwContent.length > 0) {
          // Parse URLs from marked content
          const lines = gfwContent.split('\n');
          for (const line of lines) {
            const url = line.trim();
            if (url.length > 0 && !url.startsWith('#')) {
              urls.push(url);
            }
          }
          return urls;
        }
      }
    }

    // If no markers found, parse entire content
    const lines = content.split('\n');
    for (const line of lines) {
      const url = line.trim();
      if (url.length > 0 && !url.startsWith('#')) {
        urls.push(url);
      }
    }

    return urls;
  }

  /**
   * Sleep helper
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
