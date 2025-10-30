import cryptoFramework from '@ohos.security.cryptoFramework';
import { util } from '@kit.ArkTS';

/**
 * Crypto Helper for RSA encryption and signature verification
 */
export class CryptoHelper {
  private publicKey: cryptoFramework.PubKey | null = null;
  
  /**
   * Set public key from PEM string
   */
  async setPublicKey(pem: string): Promise<boolean> {
    try {
      // Remove PEM headers and whitespace
      const keyString = pem
        .replace('-----BEGIN PUBLIC KEY-----', '')
        .replace('-----END PUBLIC KEY-----', '')
        .replace(/\s+/g, '');
      
      // Base64 decode
      const base64Helper = new util.Base64Helper();
      const keyData = base64Helper.decodeSync(keyString);
      
      // Create AsyKeyGenerator
      const asyKeyGenerator = cryptoFramework.createAsyKeyGenerator('RSA2048|PRIMES_2');
      
      // Convert to DataBlob
      const keyBlob: cryptoFramework.DataBlob = {
        data: keyData
      };
      
      // Generate key pair from public key data
      const keyPair = await asyKeyGenerator.convertKey(keyBlob, null);
      this.publicKey = keyPair.pubKey;
      
      return true;
    } catch (error) {
      console.error('Failed to set public key:', error);
      return false;
    }
  }
  
  /**
   * Generate random bytes
   */
  generateRandom(length: number): Uint8Array {
    const random = cryptoFramework.createRandom();
    return random.generateRandomSync(length).data;
  }
  
  /**
   * Encrypt data with public key (RSA-PKCS1)
   */
  async encrypt(data: Uint8Array): Promise<Uint8Array | null> {
    try {
      if (!this.publicKey) {
        throw new Error('Public key not set');
      }
      
      // Create cipher
      const cipher = cryptoFramework.createCipher('RSA2048|PKCS1');
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, this.publicKey, null);
      
      // Encrypt
      const dataBlob: cryptoFramework.DataBlob = { data: data };
      const encryptedData = await cipher.doFinal(dataBlob);
      
      return encryptedData.data;
    } catch (error) {
      console.error('Encryption failed:', error);
      return null;
    }
  }
  
  /**
   * Verify signature (RSA-SHA256)
   */
  async verifySignature(data: Uint8Array, signature: Uint8Array): Promise<boolean> {
    try {
      if (!this.publicKey) {
        throw new Error('Public key not set');
      }
      
      // Create Verify instance
      const verify = cryptoFramework.createVerify('RSA2048|PKCS1|SHA256');
      await verify.init(this.publicKey);
      
      // Update data
      const dataBlob: cryptoFramework.DataBlob = { data: data };
      await verify.update(dataBlob);
      
      // Verify signature
      const signatureBlob: cryptoFramework.DataBlob = { data: signature };
      return await verify.verify(dataBlob, signatureBlob);
    } catch (error) {
      console.error('Signature verification failed:', error);
      return false;
    }
  }
}

