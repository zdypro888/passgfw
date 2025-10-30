/**
 * PassGFW - Firewall Detection Library (HarmonyOS)
 * 
 * Main entry point for the PassGFW library.
 */

import { FirewallDetector } from './FirewallDetector';
import { Logger, LogLevel } from './Logger';

export class PassGFW {
  private detector: FirewallDetector;
  
  constructor() {
    this.detector = new FirewallDetector();
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
   * @param urls Array of URLs to check
   */
  setURLList(urls: string[]): void {
    this.detector.setURLList(urls);
  }
  
  /**
   * Add a URL to the check list
   * @param url URL to add
   */
  addURL(url: string): void {
    this.detector.addURL(url);
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

