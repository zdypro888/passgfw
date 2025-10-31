import { NetworkClient } from './NetworkClient';
import { CryptoHelper } from './CryptoHelper';
import { Config } from './Config';
import { Logger } from './Logger';
import { URLStorageManager, URLEntry } from './URLStorageManager';
import { util } from '@kit.ArkTS';

/**
 * Firewall Detector - Core detection logic
 */
export class FirewallDetector {
  private urlList: URLEntry[];
  private networkClient: NetworkClient;
  private cryptoHelper: CryptoHelper;
  private lastError: string | null = null;
  private initialized: boolean = false;

  constructor() {
    this.urlList = [];
    this.networkClient = new NetworkClient();
    this.cryptoHelper = new CryptoHelper();

    // Initialize crypto with public key
    this.cryptoHelper.setPublicKey(Config.getPublicKey());
  }

  /**
   * 初始化检测器（加载内置 URL 和存储的 URL）
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    // 加载内置 URL
    const builtinURLs = Config.getBuiltinURLs();

    // 尝试加载存储的 URL
    try {
      const storedURLs = await URLStorageManager.getInstance().loadStoredURLs();
      if (storedURLs.length > 0) {
        Logger.getInstance().info(`加载了 ${storedURLs.length} 个存储的 URL`);
        this.urlList = [...builtinURLs, ...storedURLs];
      } else {
        this.urlList = builtinURLs;
      }
    } catch (error) {
      Logger.getInstance().warning(`加载存储的 URL 失败，使用内置 URL: ${error.message}`);
      this.urlList = builtinURLs;
    }

    Logger.getInstance().debug(`总共加载了 ${this.urlList.length} 个 URL (内置: ${builtinURLs.length}, 存储: ${this.urlList.length - builtinURLs.length})`);

    this.initialized = true;
  }

  /**
   * Get final server domain (main entry point)
   */
  async getFinalServer(customData?: string): Promise<string | null> {
    // 确保已初始化
    await this.initialize();

    Logger.getInstance().debug(`getFinalServer() called with customData: ${customData || 'null'}`);
    Logger.getInstance().debug(`URL list size: ${this.urlList.length}`);

    // Loop infinitely until finding an available server
    while (true) {
      Logger.getInstance().debug('Starting URL iteration...');

      for (const entry of this.urlList) {
        Logger.getInstance().debug(`Checking URL: ${entry.url} (method: ${entry.method})`);

        const domain = await this.checkURLEntry(entry, customData, 0);
        if (domain) {
          Logger.getInstance().info(`Found available server: ${domain}`);
          return domain;
        }

        // Wait between URL checks
        await this.sleep(Config.URL_INTERVAL);
      }

      // All URLs failed, wait and retry
      this.lastError = 'All URL detection failed, retrying...';
      Logger.getInstance().warning(this.lastError);
      await this.sleep(Config.RETRY_INTERVAL);
    }
  }

  /**
   * Set URL list
   */
  setURLList(entries: URLEntry[]): void {
    this.urlList = entries;
  }

  /**
   * Add URL to list
   */
  addURL(method: string, url: string): void {
    this.urlList.push({ method, url });
  }

  /**
   * Get last error
   */
  getLastError(): string | null {
    return this.lastError;
  }

  // MARK: - Private Methods

  /**
   * 检查单个 URL Entry
   */
  private async checkURLEntry(entry: URLEntry, customData: string | undefined, recursionDepth: number): Promise<string | null> {
    this.lastError = null;

    // Check recursion depth limit
    if (recursionDepth > Config.MAX_LIST_RECURSION_DEPTH) {
      this.lastError = `Maximum list recursion depth exceeded: ${entry.url}`;
      Logger.getInstance().error(`Recursion depth limit reached (${recursionDepth}) for URL: ${entry.url}`);
      return null;
    }

    // Handle "remove" method - 从存储中删除 URL
    if (entry.method.toLowerCase() === 'remove') {
      Logger.getInstance().info(`删除本地存储中的 URL: ${entry.url}`);
      try {
        const manager = URLStorageManager.getInstance();
        if (await manager.removeURL(entry.url)) {
          Logger.getInstance().info(`成功删除 URL: ${entry.url}`);
        } else {
          Logger.getInstance().warning(`删除失败（URL 可能不存在）: ${entry.url}`);
        }
      } catch (error) {
        Logger.getInstance().error(`URLStorageManager not available: ${error.message}`);
      }
      // 不检查此 URL，直接跳过
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
      URLStorageManager.getInstance().addURL(storedEntry).then((success) => {
        if (success) {
          Logger.getInstance().info(`后台存储成功: ${entry.url} (method: ${entry.method})`);
        } else {
          Logger.getInstance().error(`后台存储失败: ${entry.url}`);
        }
      }).catch((error) => {
        Logger.getInstance().error(`存储出错: ${error.message}`);
      });
      Logger.getInstance().info(`启动后台存储检测成功的 URL: ${entry.url} (method: ${entry.method})`);
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
      Logger.getInstance().debug(`Fetched ${subEntries.length} URL entries from JSON sub-list, checking each one...`);

      // Check each URL entry in sub-list
      for (const subEntry of subEntries) {
        Logger.getInstance().debug(`Checking sub-list entry: ${subEntry.url} (method: ${subEntry.method})`);

        const domain = await this.checkURLEntry(subEntry, customData, recursionDepth + 1);
        if (domain) {
          Logger.getInstance().info(`Sub-list entry succeeded: ${subEntry.url} -> ${domain}`);
          return domain;
        }

        Logger.getInstance().debug(`Sub-list entry failed: ${subEntry.url}, trying next...`);
        await this.sleep(Config.URL_INTERVAL);
      }
    } else {
      // Fallback: parse as plain text URL list (legacy format)
      const subURLs = this.parseURLList(response.body);
      if (subURLs.length === 0) {
        this.lastError = `Sub-list empty or parse failed: ${url}`;
        return null;
      }

      Logger.getInstance().debug(`Fetched ${subURLs.length} URLs from text sub-list, checking each one...`);

      // Check each URL in sub-list (assume API method)
      for (const subURL of subURLs) {
        Logger.getInstance().debug(`Checking sub-list URL: ${subURL}`);
        const subEntry: URLEntry = { method: 'api', url: subURL };

        const domain = await this.checkURLEntry(subEntry, customData, recursionDepth + 1);
        if (domain) {
          Logger.getInstance().info(`Sub-list URL succeeded: ${subURL} -> ${domain}`);
          return domain;
        }

        Logger.getInstance().debug(`Sub-list URL failed: ${subURL}, trying next...`);
        await this.sleep(Config.URL_INTERVAL);
      }
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
            if (entry.store === true) {
              const storedEntry: URLEntry = { method: entry.method, url: entry.url };
              // 后台异步存储，不阻塞返回（不等待 Promise）
              URLStorageManager.getInstance().addURL(storedEntry).then((success) => {
                if (success) {
                  Logger.getInstance().info(`后台存储成功: ${entry.url}`);
                } else {
                  Logger.getInstance().error(`后台存储失败: ${entry.url}`);
                }
              }).catch((error) => {
                Logger.getInstance().error(`存储出错: ${error.message}`);
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
              if (entry.store === true) {
                const storedEntry: URLEntry = { method: entry.method, url: entry.url };
                // 不等待存储完成，立即返回
                URLStorageManager.getInstance().addURL(storedEntry).then((success) => {
                  if (success) {
                    Logger.getInstance().info(`后台存储成功: ${entry.url}`);
                  }
                }).catch((error) => {
                  Logger.getInstance().error(`存储出错: ${error.message}`);
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
