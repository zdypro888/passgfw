import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { Logger } from './Logger';

/**
 * 安全存储接口
 */
export interface SecureStorage {
  save(value: string, key: string): Promise<boolean>;
  load(key: string): Promise<string | null>;
  delete(key: string): Promise<boolean>;
}

/**
 * Preferences 实现的存储
 */
export class PreferencesStorage implements SecureStorage {
  private static readonly PREFS_NAME = 'passgfw_storage';
  private preferencesPromise: Promise<preferences.Preferences> | null = null;

  constructor(context: common.Context) {
    // 获取 preferences 实例
    this.preferencesPromise = preferences.getPreferences(context, PreferencesStorage.PREFS_NAME);
  }

  async save(value: string, key: string): Promise<boolean> {
    try {
      const prefs = await this.preferencesPromise;
      if (!prefs) {
        Logger.error('Preferences not initialized');
        return false;
      }

      await prefs.put(key, value);
      await prefs.flush();
      return true;
    } catch (error) {
      Logger.error(`Failed to save to preferences: ${error}`);
      return false;
    }
  }

  async load(key: string): Promise<string | null> {
    try {
      const prefs = await this.preferencesPromise;
      if (!prefs) {
        Logger.error('Preferences not initialized');
        return null;
      }

      const value = await prefs.get(key, '');
      return value as string || null;
    } catch (error) {
      Logger.error(`Failed to load from preferences: ${error}`);
      return null;
    }
  }

  async delete(key: string): Promise<boolean> {
    try {
      const prefs = await this.preferencesPromise;
      if (!prefs) {
        Logger.error('Preferences not initialized');
        return false;
      }

      await prefs.delete(key);
      await prefs.flush();
      return true;
    } catch (error) {
      Logger.error(`Failed to delete from preferences: ${error}`);
      return false;
    }
  }
}
