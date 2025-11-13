/**
 * PassGFW - Firewall Detection Library (HarmonyOS)
 *
 * Main entry point for the PassGFW library.
 */

import { FirewallDetector } from './FirewallDetector';
import { Logger, LogLevel } from './Logger';
import { URLEntry } from './Config';
import { common } from '@kit.AbilityKit';

export class PassGFW {
  private detector: FirewallDetector;
  private initialized: boolean = false;

  constructor() {
    this.detector = new FirewallDetector();
  }

  /**
   * 初始化 PassGFW（必须在使用前调用）
   * @param context UIAbilityContext
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }

    // 初始化 FirewallDetector（传递 context）
    await this.detector.initialize(context);

    this.initialized = true;
    Logger.getInstance().info('PassGFW 初始化完成');
  }

  /**
   * Get server domains by checking URL list
   * @param retry If true, force re-detection even if cache exists. If false, return cache if available.
   * @param customData Optional custom data to send with requests
   * @returns ESObject containing server response data, or null if all attempts fail
   */
  async getDomains(retry: boolean = false, customData?: string): Promise<ESObject | null> {
    return await this.detector.getDomains(retry, customData);
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
export { URLEntry } from './Config';

