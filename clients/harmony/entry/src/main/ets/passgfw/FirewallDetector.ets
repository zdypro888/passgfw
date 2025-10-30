import { NetworkClient } from './NetworkClient';
import { CryptoHelper } from './CryptoHelper';
import { Config } from './Config';
import { Logger } from './Logger';
import { util } from '@kit.ArkTS';

/**
 * Firewall Detector - Core detection logic
 */
export class FirewallDetector {
  private urlList: string[];
  private networkClient: NetworkClient;
  private cryptoHelper: CryptoHelper;
  private lastError: string | null = null;
  
  constructor() {
    this.urlList = Config.getBuiltinURLs();
    this.networkClient = new NetworkClient();
    this.cryptoHelper = new CryptoHelper();
    
    // Initialize crypto with public key
    this.cryptoHelper.setPublicKey(Config.getPublicKey());
  }
  
  /**
   * Get final server domain (main entry point)
   */
  async getFinalServer(customData?: string): Promise<string | null> {
    Logger.getInstance().debug(`getFinalServer() called with customData: ${customData || 'null'}`);
    Logger.getInstance().debug(`URL list size: ${this.urlList.length}`);
    
    // Loop infinitely until finding an available server
    while (true) {
      Logger.getInstance().debug('Starting URL iteration...');
      
      for (const url of this.urlList) {
        Logger.getInstance().debug(`Checking URL: ${url}`);
        
        const domain = await this.checkURL(url, customData, 0);
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
  setURLList(urls: string[]): void {
    this.urlList = urls;
  }
  
  /**
   * Add URL to list
   */
  addURL(url: string): void {
    this.urlList.push(url);
  }
  
  /**
   * Get last error
   */
  getLastError(): string | null {
    return this.lastError;
  }
  
  // MARK: - Private Methods
  
  /**
   * Check a single URL (with recursion support for list#)
   */
  private async checkURL(url: string, customData: string | undefined, recursionDepth: number): Promise<string | null> {
    this.lastError = null;
    
    // Check recursion depth limit
    if (recursionDepth > Config.MAX_LIST_RECURSION_DEPTH) {
      this.lastError = `Maximum list recursion depth exceeded: ${url}`;
      Logger.getInstance().error(`Recursion depth limit reached (${recursionDepth}) for URL: ${url}`);
      return null;
    }
    
    // Check if it's a list URL (ending with #)
    if (url.endsWith('#')) {
      return await this.checkListURL(url, customData, recursionDepth);
    } else {
      return await this.checkNormalURL(url, customData);
    }
  }
  
  /**
   * Check a normal URL with retry mechanism
   */
  private async checkNormalURL(url: string, customData: string | undefined): Promise<string | null> {
    Logger.getInstance().debug(`CheckNormalURL() called for: ${url} with customData: ${customData || 'null'}`);
    
    if (!url || url.length === 0) {
      this.lastError = 'Empty URL provided';
      return null;
    }
    
    // Retry loop
    for (let attempt = 1; attempt <= Config.MAX_RETRIES; attempt++) {
      Logger.getInstance().debug(`Attempt ${attempt}/${Config.MAX_RETRIES} for URL: ${url}`);
      
      const domain = await this.checkNormalURLOnce(url, customData);
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
   * Check a normal URL once (no retry)
   */
  private async checkNormalURLOnce(url: string, customData: string | undefined): Promise<string | null> {
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
      const serverResponseJSON = responseJSON.data;
      const signature = responseJSON.signature;
      
      if (!serverResponseJSON || !signature) {
        this.lastError = 'Response JSON missing required fields';
        return null;
      }
      
      Logger.getInstance().debug(`Server response JSON: ${serverResponseJSON}`);
      
      // 8. Verify signature
      const serverResponseData = textEncoder.encodeInto(serverResponseJSON);
      const signatureData = base64Helper.decodeSync(signature);
      
      const verified = await this.cryptoHelper.verifySignature(serverResponseData, signatureData);
      if (!verified) {
        this.lastError = 'Signature verification failed';
        return null;
      }
      
      // 9. Parse server payload
      const serverPayload = JSON.parse(serverResponseJSON);
      const returnedNonce = serverPayload.nonce;
      const returnedDomain = serverPayload.server_domain;
      
      if (!returnedNonce || !returnedDomain) {
        this.lastError = 'Server payload missing required fields';
        return null;
      }
      
      Logger.getInstance().debug(`Returned nonce: ${returnedNonce}`);
      Logger.getInstance().debug(`Returned domain: ${returnedDomain}`);
      
      // 10. Verify nonce matches
      if (returnedNonce !== randomBase64) {
        const expectedPrefix = randomBase64.substring(0, 10);
        const actualPrefix = returnedNonce.substring(0, 10);
        this.lastError = `Nonce mismatch: expected: ${expectedPrefix}..., actual: ${actualPrefix}...`;
        return null;
      }
      
      // 11. Success!
      Logger.getInstance().debug(`Verification successful! Using domain: ${returnedDomain}`);
      return returnedDomain;
    } catch (error) {
      this.lastError = `Exception: ${error?.message || 'unknown'}`;
      return null;
    }
  }
  
  /**
   * Check a list URL (fetch sub-list and check each URL)
   */
  private async checkListURL(url: string, customData: string | undefined, recursionDepth: number): Promise<string | null> {
    Logger.getInstance().debug(`CheckListURL() called for: ${url} (depth: ${recursionDepth})`);
    
    if (url.length < 2) {
      this.lastError = 'Invalid list URL: too short';
      return null;
    }
    
    // Remove trailing #
    const actualURL = url.substring(0, url.length - 1);
    if (!actualURL || actualURL.length === 0) {
      this.lastError = 'Empty URL after removing #';
      return null;
    }
    
    // Fetch sub-list
    Logger.getInstance().debug(`Fetching sub-list from: ${actualURL}`);
    const response = await this.networkClient.get(actualURL);
    
    if (!response.success) {
      this.lastError = `GET request failed: ${actualURL} - ${response.error}`;
      return null;
    }
    
    // Parse URL list
    const subURLs = this.parseURLList(response.body);
    if (subURLs.length === 0) {
      this.lastError = `Sub-list empty or parse failed: ${actualURL}`;
      return null;
    }
    
    Logger.getInstance().debug(`Fetched ${subURLs.length} URLs from sub-list, checking each one...`);
    
    // Check each URL in sub-list
    for (const subURL of subURLs) {
      Logger.getInstance().debug(`Checking sub-list URL: ${subURL}`);
      
      const domain = await this.checkURL(subURL, customData, recursionDepth + 1);
      if (domain) {
        Logger.getInstance().info(`Sub-list URL succeeded: ${subURL} -> ${domain}`);
        return domain;
      }
      
      Logger.getInstance().debug(`Sub-list URL failed: ${subURL}, trying next...`);
      await this.sleep(Config.URL_INTERVAL);
    }
    
    // All URLs in sub-list failed
    Logger.getInstance().debug('All URLs in sub-list failed');
    this.lastError = `All URLs in sub-list failed: ${actualURL}`;
    return null;
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

