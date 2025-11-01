import { SecureStorage } from './SecureStorage';
import { Logger } from './Logger';
import { Config, URLEntry } from './Config';

/**
 * URL 状态枚举
 */
export enum URLStatus {
  UNTESTED = 'untested',   // 未测试
  SUCCESS = 'success',     // 成功
  FAILED = 'failed'        // 失败
}

/**
 * URL 元数据 - 包含 URL 信息和测试统计
 */
export interface URLMetadata {
  method: string;
  url: string;
  store?: boolean;
  status: string;
  successCount: number;
  failureCount: number;
  lastTested?: number;      // Unix timestamp (milliseconds)
  lastSuccess?: number;     // Unix timestamp (milliseconds)
}

/**
 * URL 管理器 - 负责 URL 列表的持久化存储和优先级排序
 */
export class URLManager {
  private static readonly STORAGE_KEY = 'passgfw.urls';
  private storage: SecureStorage;

  constructor(storage: SecureStorage) {
    this.storage = storage;
  }

  /**
   * 从 URLEntry 创建 URLMetadata
   */
  private static createMetadata(entry: URLEntry): URLMetadata {
    return {
      method: entry.method,
      url: entry.url,
      store: entry.store || false,
      status: URLStatus.UNTESTED,
      successCount: 0,
      failureCount: 0,
      lastTested: undefined,
      lastSuccess: undefined
    };
  }

  /**
   * URLMetadata 转换为 URLEntry
   */
  private static toURLEntry(metadata: URLMetadata): URLEntry {
    return {
      method: metadata.method,
      url: metadata.url,
      store: metadata.store || false
    };
  }

  /**
   * 记录成功
   */
  private static recordSuccess(metadata: URLMetadata): URLMetadata {
    const now = Date.now();
    return {
      ...metadata,
      status: URLStatus.SUCCESS,
      successCount: metadata.successCount + 1,
      lastTested: now,
      lastSuccess: now
    };
  }

  /**
   * 记录失败
   */
  private static recordFailure(metadata: URLMetadata): URLMetadata {
    return {
      ...metadata,
      status: URLStatus.FAILED,
      failureCount: metadata.failureCount + 1,
      lastTested: Date.now()
    };
  }

  /**
   * 初始化 URL 列表（仅首次启动时调用）
   * @returns 是否成功初始化
   */
  async initializeIfNeeded(): Promise<boolean> {
    try {
      // 检查是否已经初始化
      const existing = await this.loadURLs();
      if (existing !== null) {
        return true;  // 已经初始化过了
      }

      // 首次启动，使用内置 URLs 初始化
      const builtinURLs = Config.getBuiltinURLs();
      const metadata = builtinURLs.map(entry => URLManager.createMetadata(entry));
      return await this.saveURLs(metadata);
    } catch (error) {
      Logger.error(`Failed to initialize URLs: ${error}`);
      return false;
    }
  }

  /**
   * 获取排序后的 URL 列表
   * @returns 按优先级排序的 URLEntry 数组
   */
  async getSortedURLs(): Promise<URLEntry[]> {
    try {
      let metadata = await this.loadURLs();
      if (metadata === null) {
        // 如果加载失败，返回内置 URLs
        return Config.getBuiltinURLs();
      }

      // 排序逻辑
      metadata.sort((a, b) => {
        // 1. 首先按 status 排序：success > untested > failed
        const statusOrder = {
          [URLStatus.SUCCESS]: 0,
          [URLStatus.UNTESTED]: 1,
          [URLStatus.FAILED]: 2
        };

        const aOrder = statusOrder[a.status] ?? 2;
        const bOrder = statusOrder[b.status] ?? 2;

        if (aOrder !== bOrder) {
          return aOrder - bOrder;
        }

        // 2. 同一 status，按 successCount 降序
        if (a.successCount !== b.successCount) {
          return b.successCount - a.successCount;
        }

        // 3. successCount 相同，按 lastSuccess 降序
        const aLastSuccess = a.lastSuccess || 0;
        const bLastSuccess = b.lastSuccess || 0;
        return bLastSuccess - aLastSuccess;
      });

      return metadata.map(m => URLManager.toURLEntry(m));
    } catch (error) {
      Logger.error(`Failed to get sorted URLs: ${error}`);
      return Config.getBuiltinURLs();
    }
  }

  /**
   * 记录 URL 检测成功
   * @param url 成功的 URL
   */
  async recordSuccess(url: string): Promise<void> {
    try {
      const metadata = await this.loadURLs();
      if (metadata === null) return;

      const index = metadata.findIndex(m => m.url === url);
      if (index >= 0) {
        metadata[index] = URLManager.recordSuccess(metadata[index]);
        await this.saveURLs(metadata);
      }
    } catch (error) {
      Logger.error(`Failed to record success for ${url}: ${error}`);
    }
  }

  /**
   * 记录 URL 检测失败
   * @param url 失败的 URL
   */
  async recordFailure(url: string): Promise<void> {
    try {
      const metadata = await this.loadURLs();
      if (metadata === null) return;

      const index = metadata.findIndex(m => m.url === url);
      if (index >= 0) {
        metadata[index] = URLManager.recordFailure(metadata[index]);
        await this.saveURLs(metadata);
      }
    } catch (error) {
      Logger.error(`Failed to record failure for ${url}: ${error}`);
    }
  }

  /**
   * 添加新的 URL（通过 list# 或 file# 动态添加）
   * @param entry 要添加的 URLEntry
   * @returns 是否成功添加
   */
  async addURL(entry: URLEntry): Promise<boolean> {
    try {
      let metadata = await this.loadURLs();
      if (metadata === null) {
        metadata = [];
      }

      // 检查是否已存在
      if (metadata.some(m => m.url === entry.url)) {
        return true;  // 已存在，不重复添加
      }

      // 添加新 URL
      metadata.push(URLManager.createMetadata(entry));
      return await this.saveURLs(metadata);
    } catch (error) {
      Logger.error(`Failed to add URL: ${error}`);
      return false;
    }
  }

  /**
   * 删除 URL（明确删除操作）
   * @param url 要删除的 URL
   * @returns 是否成功删除
   */
  async removeURL(url: string): Promise<boolean> {
    try {
      const metadata = await this.loadURLs();
      if (metadata === null) return false;

      const filtered = metadata.filter(m => m.url !== url);
      return await this.saveURLs(filtered);
    } catch (error) {
      Logger.error(`Failed to remove URL: ${error}`);
      return false;
    }
  }

  /**
   * 清空所有 URL 并重新初始化为内置列表
   * @returns 是否成功重置
   */
  async reset(): Promise<boolean> {
    try {
      const builtinURLs = Config.getBuiltinURLs();
      const metadata = builtinURLs.map(entry => URLManager.createMetadata(entry));
      return await this.saveURLs(metadata);
    } catch (error) {
      Logger.error(`Failed to reset URLs: ${error}`);
      return false;
    }
  }

  // MARK: - Private Methods

  private async loadURLs(): Promise<URLMetadata[] | null> {
    try {
      const jsonString = await this.storage.load(URLManager.STORAGE_KEY);
      if (!jsonString) {
        return null;
      }

      const metadata = JSON.parse(jsonString) as URLMetadata[];
      return metadata;
    } catch (error) {
      Logger.error(`Failed to decode URL metadata: ${error}`);
      return null;
    }
  }

  private async saveURLs(metadata: URLMetadata[]): Promise<boolean> {
    try {
      const jsonString = JSON.stringify(metadata);
      return await this.storage.save(jsonString, URLManager.STORAGE_KEY);
    } catch (error) {
      Logger.error(`Failed to encode URL metadata: ${error}`);
      return false;
    }
  }
}
