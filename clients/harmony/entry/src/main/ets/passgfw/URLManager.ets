import { SecureStorage } from './SecureStorage';
import { Logger } from './Logger';
import { Config, URLEntry } from './Config';

/**
 * URL Manager - 负责 URL 列表的持久化存储
 */
export class URLManager {
  private static readonly STORAGE_KEY = 'passgfw.urls';
  private storage: SecureStorage;

  constructor(storage: SecureStorage) {
    this.storage = storage;
  }

  /**
   * 初始化 URL 列表（仅首次启动时调用）
   * @returns 是否成功初始化
   */
  async initializeIfNeeded(): Promise<boolean> {
    // 检查是否已经初始化
    const existing = await this.loadURLs();
    if (existing !== null) {
      return true;  // 已经初始化过了
    }

    // 首次启动，使用内置 URLs 初始化
    const builtinURLs = Config.getBuiltinURLs();
    return await this.saveURLs(builtinURLs);
  }

  /**
   * 获取 URL 列表（按存储顺序）
   * @returns URLEntry 数组
   */
  async getURLs(): Promise<URLEntry[]> {
    const urls = await this.loadURLs();
    if (urls !== null) {
      return urls;
    }
    // 如果加载失败，返回内置 URLs
    return Config.getBuiltinURLs();
  }

  /**
   * 添加新的 URL（通过动态添加，store=true）
   * @param entry 要添加的 URLEntry
   * @returns 是否成功添加
   */
  async addURL(entry: URLEntry): Promise<boolean> {
    let urls = await this.loadURLs();
    if (urls === null) {
      urls = [];
    }

    // 检查是否已存在
    const exists = urls.some(u => u.url === entry.url);
    if (exists) {
      return true;  // 已存在，不重复添加
    }

    // 添加新 URL
    urls.push(entry);
    return await this.saveURLs(urls);
  }

  /**
   * 删除 URL（remove 方法）
   * @param url 要删除的 URL
   * @returns 是否成功删除
   */
  async removeURL(url: string): Promise<boolean> {
    let urls = await this.loadURLs();
    if (urls === null) {
      return false;
    }

    urls = urls.filter(u => u.url !== url);
    return await this.saveURLs(urls);
  }

  /**
   * 清空所有 URL 并重新初始化为内置列表
   * @returns 是否成功重置
   */
  async reset(): Promise<boolean> {
    const builtinURLs = Config.getBuiltinURLs();
    return await this.saveURLs(builtinURLs);
  }

  // MARK: - Private Methods

  private async loadURLs(): Promise<URLEntry[] | null> {
    const data = await this.storage.load(URLManager.STORAGE_KEY);
    if (!data) {
      return null;
    }

    try {
      const json = data;
      const urls: URLEntry[] = JSON.parse(json);
      return urls;
    } catch (error) {
      Logger.getInstance().error(`Failed to decode URLs: ${error}`);
      return null;
    }
  }

  private async saveURLs(urls: URLEntry[]): Promise<boolean> {
    try {
      const json = JSON.stringify(urls);
      return await this.storage.save(URLManager.STORAGE_KEY, json);
    } catch (error) {
      Logger.getInstance().error(`Failed to encode URLs: ${error}`);
      return false;
    }
  }
}
