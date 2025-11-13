import { NetworkClient } from './NetworkClient';
import { CryptoHelper } from './CryptoHelper';
import { Config, URLEntry } from './Config';
import { Logger } from './Logger';
import { URLManager } from './URLManager';
import { SecureStorage } from './SecureStorage';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

/**
 * Firewall Detector - Core detection logic
 */
export class FirewallDetector {
  private networkClient: NetworkClient;
  private cryptoHelper: CryptoHelper;
  private urlManager: URLManager | null = null;
  private context: common.UIAbilityContext | null = null;

  // 缓存最后成功的结果
  private cachedResult: ESObject | null = null;
  private lastError: string | null = null;

  constructor() {
    this.networkClient = new NetworkClient();
    this.cryptoHelper = new CryptoHelper();

    // Set public key
    const publicKey = Config.getPublicKey();
    this.cryptoHelper.setPublicKey(publicKey).then((success: boolean) => {
      if (success) {
        Logger.getInstance().info('Public key set successfully');
      } else {
        Logger.getInstance().error('Failed to set public key');
      }
    });
  }

  /**
   * Initialize FirewallDetector
   * @param context UIAbilityContext
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;

    // Initialize URL Manager
    const storage = new SecureStorage(context);
    this.urlManager = new URLManager(storage);

    const success = await this.urlManager.initializeIfNeeded();
    if (success) {
      Logger.getInstance().info('URLManager initialized');
    } else {
      Logger.getInstance().warning('URLManager initialization failed');
    }
  }

  /**
   * Get domains by checking URL list
   * @param retry If true, force re-detection. If false, return cache if available.
   * @param customData Optional custom data to send with requests
   * @returns ESObject containing server response data, or null if all attempts fail
   */
  async getDomains(retry: boolean, customData?: string): Promise<ESObject | null> {
    // If not retry and cache exists, return cache
    if (!retry && this.cachedResult !== null) {
      Logger.getInstance().info('Returning cached result');
      return this.cachedResult;
    }

    // Perform detection
    Logger.getInstance().info(`Starting detection (retry=${retry})`);

    // Infinite retry loop until success
    while (true) {
      if (!this.urlManager) {
        Logger.getInstance().error('URLManager not initialized');
        return null;
      }

      const urls = await this.urlManager.getURLs();
      Logger.getInstance().debug(`Checking ${urls.length} URLs`);

      const result = await this.checkURLsSequentially(urls, customData, 0);
      if (result !== null) {
        // Success - cache and return
        this.cachedResult = result;
        Logger.getInstance().info('Detection succeeded');
        return result;
      }

      // All failed, wait and retry
      this.lastError = 'All URLs failed, retrying...';
      Logger.getInstance().warning(this.lastError);
      await this.sleep(Config.RETRY_INTERVAL);
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
   * Check URLs sequentially
   */
  private async checkURLsSequentially(
    entries: URLEntry[],
    customData: string | undefined,
    recursionDepth: number
  ): Promise<ESObject | null> {
    for (const entry of entries) {
      Logger.getInstance().debug(`Checking URL: ${entry.url} (method: ${entry.method}, depth: ${recursionDepth})`);

      const result = await this.checkURLEntry(entry, customData, recursionDepth);
      if (result !== null) {
        Logger.getInstance().info('Found available server');
        return result;
      }

      // Small delay between checks
      await this.sleep(Config.URL_INTERVAL);
    }
    return null;
  }

  /**
   * Check single URL entry
   */
  private async checkURLEntry(
    entry: URLEntry,
    customData: string | undefined,
    recursionDepth: number
  ): Promise<ESObject | null> {
    switch (entry.method) {
      case 'api':
        return await this.checkAPIMethod(entry, customData);
      case 'file':
        return await this.checkFileMethod(entry, customData, recursionDepth);
      case 'navigate':
        this.handleNavigateMethod(entry);
        // Navigate 执行后算成功，返回表示已引导用户
        return { navigated: true, url: entry.url };
      case 'remove':
        await this.handleRemoveMethod(entry);
        // Remove 执行后继续下一个（返回null）
        return null;
      default:
        Logger.getInstance().warning(`Unknown method: ${entry.method}`);
        return null;
    }
  }

  /**
   * Check API method
   */
  private async checkAPIMethod(entry: URLEntry, customData?: string): Promise<ESObject | null> {
    // Generate random nonce
    const nonceData = this.cryptoHelper.generateRandom(Config.NONCE_SIZE);
    const base64Helper = new util.Base64Helper();
    const randomBase64 = base64Helper.encodeToStringSync(nonceData);

    // Prepare client data
    const clientData = {
      domain: 'example.com'
    };
    const clientDataStr = JSON.stringify(clientData);

    // Build request payload
    const payload = {
      nonce: randomBase64,
      os: 'harmonyos',
      app: this.context?.applicationInfo.name || 'unknown',
      data: customData || clientDataStr
    };

    const payloadStr = JSON.stringify(payload);
    const payloadBytes = new util.TextEncoder().encodeInto(payloadStr);

    // Encrypt payload
    const encryptedData = await this.cryptoHelper.encrypt(payloadBytes);
    if (!encryptedData) {
      Logger.getInstance().error('Failed to encrypt payload');
      return null;
    }

    // Send request
    const response = await this.networkClient.postBytes(entry.url, encryptedData);

    if (!response.success) {
      Logger.getInstance().warning(`API request failed: ${response.error}`);
      return null;
    }

    // Parse response
    let responseJSON: ESObject;
    try {
      responseJSON = JSON.parse(response.body) as ESObject;
    } catch (e) {
      Logger.getInstance().error(`Failed to parse response JSON: ${e}`);
      return null;
    }

    // Get nonce, data, signature (all base64 strings in JSON)
    const returnedNonceBase64 = responseJSON.nonce as string;
    const dataBase64 = responseJSON.data as string;
    const signatureBase64 = responseJSON.signature as string;

    if (!returnedNonceBase64 || !dataBase64 || !signatureBase64) {
      Logger.getInstance().error('Missing required fields');
      return null;
    }

    // Verify nonce (decode and compare bytes)
    const returnedNonceData = base64Helper.decodeSync(returnedNonceBase64);
    if (!this.arraysEqual(nonceData, returnedNonceData)) {
      Logger.getInstance().error('Nonce mismatch');
      return null;
    }

    // Decode data and signature
    const dataBytes = base64Helper.decodeSync(dataBase64);
    const signatureData = base64Helper.decodeSync(signatureBase64);

    // Rebuild response for verification (same structure as server)
    // IMPORTANT: Keep base64 strings, don't decode to []byte
    const responseForVerify: Record<string, Object> = {
      nonce: returnedNonceBase64,
      data: dataBase64
    };

    // Add URLs if present
    if (responseJSON.urls) {
      responseForVerify.urls = responseJSON.urls;
    }

    // Serialize to bytes (JSON.stringify maintains object property order)
    const jsonString = JSON.stringify(responseForVerify);
    const verifyBytes = new util.TextEncoder().encodeInto(jsonString);

    // Verify signature
    const verified = await this.cryptoHelper.verifySignature(verifyBytes, signatureData);
    if (!verified) {
      Logger.getInstance().error('Signature verification failed');
      return null;
    }

    Logger.getInstance().info(`API check succeeded for ${entry.url}`);

    // Parse data JSON
    let parsedData: ESObject;
    try {
      const dataString = new util.TextDecoder('utf-8').decodeWithStream(dataBytes);
      parsedData = JSON.parse(dataString) as ESObject;
    } catch (e) {
      Logger.getInstance().error(`Failed to parse data JSON: ${e}`);
      return null;
    }

    // Handle store flag
    if (entry.store && this.urlManager) {
      await this.urlManager.addURL(entry);
      Logger.getInstance().debug(`Store URL ${entry.url}`);
    }

    // Handle dynamic URLs from response
    if (responseJSON.urls) {
      await this.handleDynamicURLs(responseJSON.urls as ESObject[]);
    }

    // Return parsed data
    return parsedData;
  }

  /**
   * Check file method
   */
  private async checkFileMethod(
    entry: URLEntry,
    customData: string | undefined,
    recursionDepth: number
  ): Promise<ESObject | null> {
    // Check recursion depth
    if (recursionDepth >= Config.MAX_LIST_RECURSION_DEPTH) {
      Logger.getInstance().warning('Max recursion depth reached');
      return null;
    }

    // Fetch file
    const response = await this.networkClient.get(entry.url);

    if (!response.success) {
      Logger.getInstance().warning(`File request failed: ${response.error}`);
      return null;
    }

    // Parse URL list
    const urls = this.parseURLList(response.body);
    if (!urls) {
      Logger.getInstance().error('Failed to parse URL list');
      return null;
    }

    Logger.getInstance().info(`File method: loaded ${urls.length} URLs from ${entry.url}`);

    // Handle store flag
    if (entry.store && this.urlManager) {
      await this.urlManager.addURL(entry);
      Logger.getInstance().debug(`Store file URL ${entry.url}`);
    }

    // Check nested URLs
    return await this.checkURLsSequentially(urls, customData, recursionDepth + 1);
  }

  /**
   * Handle navigate method
   */
  private handleNavigateMethod(entry: URLEntry): void {
    Logger.getInstance().info(`Navigate method: opening ${entry.url}`);
    // Note: HarmonyOS需要使用want来打开浏览器，这里简化处理
    // 实际使用时需要在context中调用startAbility
    if (this.context) {
      try {
        // 使用UIAbilityContext打开URL
        // this.context.startAbility(...) - 需要具体实现
        Logger.getInstance().debug(`Would open URL: ${entry.url}`);
      } catch (e) {
        Logger.getInstance().error(`Failed to open URL: ${e}`);
      }
    }
  }

  /**
   * Handle remove method
   */
  private async handleRemoveMethod(entry: URLEntry): Promise<void> {
    Logger.getInstance().info(`Remove method: removing ${entry.url}`);
    if (this.urlManager) {
      await this.urlManager.removeURL(entry.url);
      Logger.getInstance().debug(`Remove URL ${entry.url}`);
    }
  }

  /**
   * Handle dynamic URLs from API response
   */
  private async handleDynamicURLs(urlsJSON: ESObject[]): Promise<void> {
    for (const urlObj of urlsJSON) {
      const method = urlObj.method as string;
      const url = urlObj.url as string;

      if (!method || !url) continue;

      const store = (urlObj.store as boolean) || false;
      const entry: URLEntry = { method, url, store };

      if (!this.urlManager) continue;

      switch (method) {
        case 'remove':
          await this.urlManager.removeURL(url);
          Logger.getInstance().debug(`Dynamic remove: ${url}`);
          break;
        case 'api':
        case 'file':
          if (store) {
            await this.urlManager.addURL(entry);
            Logger.getInstance().debug(`Dynamic store: ${url}`);
          }
          break;
        case 'navigate':
          this.handleNavigateMethod(entry);
          break;
        default:
          Logger.getInstance().warning(`Unknown dynamic method: ${method}`);
      }
    }
  }

  /**
   * Parse URL list from text
   */
  private parseURLList(text: string): URLEntry[] | null {
    // Try *PGFW* format first
    const pgfwContent = this.extractPGFWContent(text);
    if (pgfwContent) {
      try {
        const urls = JSON.parse(pgfwContent) as URLEntry[];
        return urls;
      } catch (e) {
        // Continue to next format
      }
    }

    // Try direct JSON array
    try {
      const urls = JSON.parse(text) as URLEntry[];
      if (Array.isArray(urls)) {
        return urls;
      }
    } catch (e) {
      // Continue to next format
    }

    // Try legacy format {"urls": [...]}
    try {
      const json = JSON.parse(text) as ESObject;
      if (json.urls && Array.isArray(json.urls)) {
        return json.urls as URLEntry[];
      }
    } catch (e) {
      // Continue to next format
    }

    // Fallback: plain text (one URL per line)
    const entries: URLEntry[] = [];
    const lines = text.split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed === '' || trimmed.startsWith('#')) continue;
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        entries.push({ method: 'api', url: trimmed, store: false });
      }
    }

    return entries.length > 0 ? entries : null;
  }

  /**
   * Extract content from *PGFW*...*PGFW* markers
   */
  private extractPGFWContent(text: string): string | null {
    const startMarker = '*PGFW*';
    const endMarker = '*PGFW*';

    const startIndex = text.indexOf(startMarker);
    if (startIndex === -1) return null;

    const contentStart = startIndex + startMarker.length;
    const endIndex = text.indexOf(endMarker, contentStart);
    if (endIndex === -1) return null;

    const base64String = text.substring(contentStart, endIndex);
    try {
      const base64Helper = new util.Base64Helper();
      const decodedBytes = base64Helper.decodeSync(base64String);
      const decodedString = new util.TextDecoder('utf-8').decodeWithStream(decodedBytes);
      return decodedString;
    } catch (e) {
      return null;
    }
  }

  /**
   * Sleep helper
   */
  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /**
   * Compare two Uint8Array for equality
   */
  private arraysEqual(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false;
    }
    return true;
  }
}
