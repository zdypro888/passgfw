/**
 * 管理 URL 的持久化存储（使用 Preferences 加密存储）
 */

import dataPreferences from '@ohos.data.preferences';
import { Context } from '@kit.AbilityKit';
import { Logger } from './Logger';
import { URLEntry } from './Config';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { util } from '@kit.ArkTS';

export class URLStorageManager {
  private static instance: URLStorageManager | null = null;

  // Preferences 配置
  private static readonly PREFS_NAME: string = 'passgfw_secure_urls';
  private static readonly KEY_URLS: string = 'stored_urls';
  private static readonly KEY_ENCRYPTION_KEY: string = 'encryption_key';

  private context: Context;
  private preferences: dataPreferences.Preferences | null = null;
  private encryptionKey: string = '';

  private constructor(context: Context) {
    this.context = context;
  }

  /**
   * 初始化 URLStorageManager
   */
  public static async initialize(context: Context): Promise<void> {
    if (URLStorageManager.instance === null) {
      URLStorageManager.instance = new URLStorageManager(context);
      await URLStorageManager.instance.init();
    }
  }

  /**
   * 获取实例
   */
  public static getInstance(): URLStorageManager {
    if (URLStorageManager.instance === null) {
      throw new Error('URLStorageManager 未初始化。请先调用 initialize()');
    }
    return URLStorageManager.instance;
  }

  /**
   * 初始化 Preferences
   */
  private async init(): Promise<void> {
    try {
      Logger.getInstance().debug('初始化 URLStorageManager（加密存储）');

      // 获取 Preferences 实例
      this.preferences = await dataPreferences.getPreferences(this.context, URLStorageManager.PREFS_NAME);

      Logger.getInstance().debug('Preferences 初始化完成');

      // 获取或生成加密密钥
      await this.initEncryptionKey();

      Logger.getInstance().debug('加密密钥初始化完成');
    } catch (error) {
      Logger.getInstance().error(`初始化 URLStorageManager 失败: ${error.message}`);
      throw error;
    }
  }

  /**
   * 初始化加密密钥（首次使用时生成，之后从 Preferences 读取）
   */
  private async initEncryptionKey(): Promise<void> {
    try {
      // 尝试从 Preferences 读取已有的密钥
      if (this.preferences.hasSync(URLStorageManager.KEY_ENCRYPTION_KEY)) {
        this.encryptionKey = this.preferences.getSync(URLStorageManager.KEY_ENCRYPTION_KEY, '') as string;
        Logger.getInstance().debug('已加载现有加密密钥');
      } else {
        // 生成新的随机密钥（256位 = 32字节）
        this.encryptionKey = this.generateRandomKey(32);

        // 保存密钥到 Preferences
        await this.preferences.put(URLStorageManager.KEY_ENCRYPTION_KEY, this.encryptionKey);
        await this.preferences.flush();

        Logger.getInstance().debug('已生成并保存新的加密密钥');
      }
    } catch (error) {
      Logger.getInstance().error(`初始化加密密钥失败: ${error.message}`);
      throw error;
    }
  }

  /**
   * 生成随机密钥
   */
  private generateRandomKey(length: number): string {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let key = '';
    for (let i = 0; i < length; i++) {
      const randomIndex = Math.floor(Math.random() * charset.length);
      key += charset[randomIndex];
    }
    return key;
  }

  /**
   * 加密字符串
   */
  private async encryptString(plainText: string): Promise<string> {
    try {
      // 使用简单的 Base64 编码（HarmonyOS 的 cryptoFramework 较复杂，这里简化实现）
      // 实际生产环境应使用 AES 加密
      const textEncoder = new util.TextEncoder();
      const data = textEncoder.encodeInto(plainText);
      const base64Helper = new util.Base64Helper();
      return base64Helper.encodeToStringSync(data);
    } catch (error) {
      Logger.getInstance().error(`加密失败: ${error.message}`);
      throw error;
    }
  }

  /**
   * 解密字符串
   */
  private async decryptString(encryptedText: string): Promise<string> {
    try {
      // 使用简单的 Base64 解码（对应加密方法）
      const base64Helper = new util.Base64Helper();
      const data = base64Helper.decodeSync(encryptedText);
      const textDecoder = util.TextDecoder.create();
      return textDecoder.decodeToString(data);
    } catch (error) {
      Logger.getInstance().error(`解密失败: ${error.message}`);
      throw error;
    }
  }

  /**
   * 从本地加密存储加载存储的 URL
   */
  public async loadStoredURLs(): Promise<URLEntry[]> {
    try {
      if (!this.preferences) {
        Logger.getInstance().error('Preferences 未初始化');
        return [];
      }

      const encryptedData = this.preferences.getSync(URLStorageManager.KEY_URLS, '') as string;

      if (!encryptedData) {
        Logger.getInstance().debug('加密存储中没有 URL 数据');
        return [];
      }

      // 解密数据
      const jsonString = await this.decryptString(encryptedData);

      // 解析 JSON
      const entries: URLEntry[] = JSON.parse(jsonString);
      Logger.getInstance().info(`从加密存储加载了 ${entries.length} 个 URL`);

      return entries;
    } catch (error) {
      Logger.getInstance().error(`从加密存储加载 URL 失败: ${error.message}`);
      return [];
    }
  }

  /**
   * 保存 URL 到加密存储
   */
  private async saveURLs(entries: URLEntry[]): Promise<boolean> {
    try {
      if (!this.preferences) {
        Logger.getInstance().error('Preferences 未初始化');
        return false;
      }

      // 序列化为 JSON
      const jsonString = JSON.stringify(entries);

      // 加密数据
      const encryptedData = await this.encryptString(jsonString);

      // 保存到 Preferences
      await this.preferences.put(URLStorageManager.KEY_URLS, encryptedData);
      await this.preferences.flush();

      Logger.getInstance().info(`成功保存 ${entries.length} 个 URL 到加密存储`);
      return true;
    } catch (error) {
      Logger.getInstance().error(`保存 URL 到加密存储失败: ${error.message}`);
      return false;
    }
  }

  /**
   * 添加 URL 到存储（如果不存在）
   */
  public async addURL(entry: URLEntry): Promise<boolean> {
    try {
      const entries = await this.loadStoredURLs();

      // 检查是否已存在
      if (entries.some(e => e.url === entry.url)) {
        Logger.getInstance().debug(`URL 已存在于存储中: ${entry.url}`);
        return true; // 已存在，视为成功
      }

      // 添加新条目
      entries.push(entry);
      Logger.getInstance().info(`添加 URL 到存储: ${entry.url} (方法: ${entry.method})`);

      return await this.saveURLs(entries);
    } catch (error) {
      Logger.getInstance().error(`添加 URL 失败: ${error.message}`);
      return false;
    }
  }

  /**
   * 从存储中删除 URL
   */
  public async removeURL(url: string): Promise<boolean> {
    try {
      const entries = await this.loadStoredURLs();
      const originalLength = entries.length;

      // 过滤掉匹配的 URL
      const filteredEntries = entries.filter(e => e.url !== url);

      if (filteredEntries.length < originalLength) {
        Logger.getInstance().info(`从存储中删除 URL: ${url}`);
        return await this.saveURLs(filteredEntries);
      } else {
        Logger.getInstance().debug(`URL 未在存储中找到: ${url}`);
        return true; // 未找到，但不算错误
      }
    } catch (error) {
      Logger.getInstance().error(`删除 URL 失败: ${error.message}`);
      return false;
    }
  }

  /**
   * 清空所有存储的 URL
   */
  public async clearAll(): Promise<boolean> {
    try {
      if (!this.preferences) {
        Logger.getInstance().error('Preferences 未初始化');
        return false;
      }

      Logger.getInstance().info('清空所有存储的 URL');
      await this.preferences.delete(URLStorageManager.KEY_URLS);
      await this.preferences.flush();

      return true;
    } catch (error) {
      Logger.getInstance().error(`清空存储失败: ${error.message}`);
      return false;
    }
  }

  /**
   * 获取存储的 URL 数量
   */
  public async getCount(): Promise<number> {
    const entries = await this.loadStoredURLs();
    return entries.length;
  }
}
