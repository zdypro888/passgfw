/**
 * PassGFW - Firewall Detection Library (HarmonyOS)
 *
 * Main entry point for the PassGFW library.
 */

import { FirewallDetector } from './FirewallDetector';
import { Logger, LogLevel } from './Logger';
import { URLStorageManager, URLEntry } from './URLStorageManager';
import { Context } from '@kit.AbilityKit';

export class PassGFW {
  private detector: FirewallDetector;
  private initialized: boolean = false;

  constructor() {
    this.detector = new FirewallDetector();
  }

  /**
   * 初始化 PassGFW（必须在使用前调用）
   * @param context Application context
   */
  async initialize(context: Context): Promise<void> {
    if (this.initialized) {
      return;
    }

    // 初始化 URLStorageManager
    await URLStorageManager.initialize(context);

    this.initialized = true;
    Logger.getInstance().info('PassGFW 初始化完成');
  }

  /**
   * Get the final available server domain
   * @param customData Optional custom data to send with requests
   * @returns The final server domain, or null if all attempts fail
   */
  async getFinalServer(customData?: string): Promise<string | null> {
    return await this.detector.getFinalServer(customData);
  }

  /**
   * Set the URL list to check
   * @param entries Array of URL entries to check
   */
  setURLList(entries: URLEntry[]): void {
    this.detector.setURLList(entries);
  }

  /**
   * Add a URL to the check list
   * @param method Method type (e.g., "api", "file", "store", "remove")
   * @param url URL to add
   */
  addURL(method: string, url: string): void {
    this.detector.addURL(method, url);
  }

  /**
   * Get the last error message
   * @returns Last error message, or null if no error
   */
  getLastError(): string | null {
    return this.detector.getLastError();
  }

  /**
   * Enable or disable logging
   * @param enabled Whether to enable logging
   */
  setLoggingEnabled(enabled: boolean): void {
    Logger.getInstance().setEnabled(enabled);
  }

  /**
   * Set the minimum log level
   * @param level Minimum log level to display
   */
  setLogLevel(level: LogLevel): void {
    Logger.getInstance().setMinLevel(level);
  }
}

// Export related types
export { LogLevel } from './Logger';
export { URLEntry } from './URLStorageManager';

