/**
 * 鸿蒙平台网络辅助类（ArkTS）
 * 整合 HTTP、JSON、加密、签名验证
 * 使用鸿蒙原生 API
 */

import http from '@ohos.net.http';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';

export class NetworkHelper {
  private static publicKey: cryptoFramework.PubKey | null = null;
  
  /**
   * 设置公钥
   */
  static async setPublicKey(publicKeyPem: string): Promise<boolean> {
    try {
      let keyStr = publicKeyPem
        .replace('-----BEGIN PUBLIC KEY-----', '')
        .replace('-----END PUBLIC KEY-----', '')
        .replace(/\s+/g, '');
      
      let base64Helper = new util.Base64Helper();
      let keyData = base64Helper.decodeSync(keyStr);
      
      let generator = cryptoFramework.createAsyKeyGenerator('RSA2048');
      this.publicKey = await generator.convertKey(null, keyData);
      
      return true;
    } catch (error) {
      console.error('设置公钥失败:', error);
      return false;
    }
  }
  
  /**
   * 验证 URL（完整流程）
   */
  static async verifyURL(url: string, timeout: number): Promise<string> {
    let result = {
      success: false,
      verified: false,
      data: '',
      error: ''
    };
    
    try {
      if (!this.publicKey) {
        result.error = '公钥未设置';
        return JSON.stringify(result);
      }
      
      // 1. 生成随机字符串
      let randomData = this.generateRandomString(32);
      
      // 2. 加密随机字符串
      let encryptedData = await this.encrypt(randomData);
      if (!encryptedData) {
        result.error = '加密失败';
        return JSON.stringify(result);
      }
      
      // 3. 构建 JSON POST 数据（使用原生 JSON）
      let postData = {
        data: encryptedData
      };
      let postBody = JSON.stringify(postData);
      
      // 4. 发送 POST 请求
      let httpRequest = http.createHttp();
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'User-Agent': 'PassGFW/1.0'
        },
        readTimeout: timeout,
        connectTimeout: timeout,
        extraData: postBody
      });
      
      httpRequest.destroy();
      
      if (response.responseCode < 200 || response.responseCode >= 300) {
        result.error = `HTTP ${response.responseCode}`;
        return JSON.stringify(result);
      }
      
      // 5. 解析 JSON 响应（使用原生 JSON.parse）
      let responseBody = response.result as string;
      let responseJson = JSON.parse(responseBody);
      let decryptedData = responseJson.data;
      let signature = responseJson.signature;
      
      // 6. 验证签名
      let verified = await this.verifySignature(decryptedData, signature);
      
      // 7. 验证数据是否匹配
      let dataMatches = (decryptedData === randomData);
      
      result.success = true;
      result.verified = verified && dataMatches;
      result.data = decryptedData;
      
    } catch (error) {
      result.error = error.message || '请求失败';
    }
    
    return JSON.stringify(result);
  }
  
  /**
   * 获取 URL 列表
   */
  static async fetchURLList(url: string, timeout: number): Promise<string[]> {
    let urls: string[] = [];
    
    try {
      let httpRequest = http.createHttp();
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'PassGFW/1.0'
        },
        readTimeout: timeout,
        connectTimeout: timeout
      });
      
      httpRequest.destroy();
      
      if (response.responseCode >= 200 && response.responseCode < 300) {
        let content = response.result as string;
        
        // 按行分割
        let lines = content.split('\n');
        for (let line of lines) {
          line = line.trim();
          
          // 跳过空行和注释
          if (line.length === 0 || line.startsWith('#')) {
            continue;
          }
          
          // 验证是否是 URL
          if (line.startsWith('http://') || line.startsWith('https://')) {
            urls.push(line);
          }
        }
      }
    } catch (error) {
      console.error('获取 URL 列表失败:', error);
    }
    
    return urls;
  }
  
  // 私有辅助方法
  
  private static async encrypt(plaintext: string): Promise<string | null> {
    if (!this.publicKey) {
      return null;
    }
    
    try {
      let cipher = cryptoFramework.createCipher('RSA|PKCS1');
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, this.publicKey, null);
      
      let textEncoder = new util.TextEncoder();
      let plainData: cryptoFramework.DataBlob = {
        data: textEncoder.encodeInto(plaintext)
      };
      
      let encryptedData = await cipher.doFinal(plainData);
      
      let base64Helper = new util.Base64Helper();
      return base64Helper.encodeToStringSync(encryptedData.data);
    } catch (error) {
      console.error('加密失败:', error);
      return null;
    }
  }
  
  private static async verifySignature(data: string, signatureStr: string): Promise<boolean> {
    if (!this.publicKey) {
      return false;
    }
    
    try {
      let verifier = cryptoFramework.createVerify('RSA|PKCS1|SHA256');
      await verifier.init(this.publicKey);
      
      let textEncoder = new util.TextEncoder();
      let dataBlob: cryptoFramework.DataBlob = {
        data: textEncoder.encodeInto(data)
      };
      
      await verifier.update(dataBlob);
      
      let base64Helper = new util.Base64Helper();
      let signatureData = base64Helper.decodeSync(signatureStr);
      
      let signatureBlob: cryptoFramework.DataBlob = {
        data: signatureData
      };
      
      return await verifier.verify(dataBlob, signatureBlob);
    } catch (error) {
      console.error('验证签名失败:', error);
      return false;
    }
  }
  
  private static generateRandomString(length: number): string {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    let result = '';
    
    let random = cryptoFramework.createRandom();
    let randomBytes = random.generateRandomSync(length);
    
    for (let i = 0; i < length; i++) {
      result += charset.charAt(randomBytes.data[i] % charset.length);
    }
    
    return result;
  }
}

