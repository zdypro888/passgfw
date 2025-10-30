package com.passgfw

import android.util.Base64
import java.security.KeyFactory
import java.security.PublicKey
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher

/**
 * Crypto Helper for RSA encryption and signature verification
 */
class CryptoHelper {
    private var publicKey: PublicKey? = null
    
    /**
     * Set public key from PEM string
     */
    fun setPublicKey(pem: String): Boolean {
        return try {
            // Remove PEM headers and whitespace
            val keyString = pem
                .replace("-----BEGIN PUBLIC KEY-----", "")
                .replace("-----END PUBLIC KEY-----", "")
                .replace("\\s+".toRegex(), "")
            
            // Base64 decode
            val keyBytes = Base64.decode(keyString, Base64.DEFAULT)
            
            // Create public key
            val spec = X509EncodedKeySpec(keyBytes)
            val keyFactory = KeyFactory.getInstance("RSA")
            publicKey = keyFactory.generatePublic(spec)
            
            true
        } catch (e: Exception) {
            Logger.error("Failed to set public key: ${e.message}")
            false
        }
    }
    
    /**
     * Generate random bytes
     */
    fun generateRandom(length: Int): ByteArray {
        val random = SecureRandom()
        val bytes = ByteArray(length)
        random.nextBytes(bytes)
        return bytes
    }
    
    /**
     * Encrypt data with public key (RSA-PKCS1)
     */
    fun encrypt(data: ByteArray): ByteArray? {
        return try {
            val key = publicKey ?: throw IllegalStateException("Public key not set")
            val cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding")
            cipher.init(Cipher.ENCRYPT_MODE, key)
            cipher.doFinal(data)
        } catch (e: Exception) {
            Logger.error("Encryption failed: ${e.message}")
            null
        }
    }
    
    /**
     * Verify signature (RSA-SHA256)
     */
    fun verifySignature(data: ByteArray, signature: ByteArray): Boolean {
        return try {
            val key = publicKey ?: throw IllegalStateException("Public key not set")
            val sig = Signature.getInstance("SHA256withRSA")
            sig.initVerify(key)
            sig.update(data)
            sig.verify(signature)
        } catch (e: Exception) {
            Logger.error("Signature verification failed: ${e.message}")
            false
        }
    }
}

