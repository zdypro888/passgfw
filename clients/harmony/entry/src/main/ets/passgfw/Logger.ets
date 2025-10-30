import hilog from '@ohos.hilog';

/**
 * Log level
 */
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARNING = 2,
  ERROR = 3
}

/**
 * Logger for PassGFW
 */
export class Logger {
  private static instance: Logger;
  private enabled: boolean = true;
  private minLevel: LogLevel = LogLevel.DEBUG;
  private domain: number = 0x0000;
  private tag: string = 'PassGFW';
  
  private constructor() {}
  
  static getInstance(): Logger {
    if (!Logger.instance) {
      Logger.instance = new Logger();
    }
    return Logger.instance;
  }
  
  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }
  
  setMinLevel(level: LogLevel): void {
    this.minLevel = level;
  }
  
  debug(message: string): void {
    this.log(message, LogLevel.DEBUG);
  }
  
  info(message: string): void {
    this.log(message, LogLevel.INFO);
  }
  
  warning(message: string): void {
    this.log(message, LogLevel.WARNING);
  }
  
  error(message: string): void {
    this.log(message, LogLevel.ERROR);
  }
  
  private log(message: string, level: LogLevel): void {
    if (!this.enabled || level < this.minLevel) {
      return;
    }
    
    const timestamp = new Date().toISOString();
    const levelStr = LogLevel[level];
    const logMessage = `[${timestamp}] [${levelStr}] ${message}`;
    
    switch (level) {
      case LogLevel.DEBUG:
        hilog.debug(this.domain, this.tag, logMessage);
        break;
      case LogLevel.INFO:
        hilog.info(this.domain, this.tag, logMessage);
        break;
      case LogLevel.WARNING:
        hilog.warn(this.domain, this.tag, logMessage);
        break;
      case LogLevel.ERROR:
        hilog.error(this.domain, this.tag, logMessage);
        break;
    }
  }
}

