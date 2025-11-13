import Foundation
import Security

/// Crypto Helper for RSA encryption and signature verification
class CryptoHelper {
    private var publicKey: SecKey?
    
    /// Set public key from PEM string
    func setPublicKey(pem: String) -> Bool {
        // Remove PEM headers and whitespace
        let keyString = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        // Base64 decode
        guard let keyData = Data(base64Encoded: keyString) else {
            Logger.shared.error("Failed to decode public key from base64")
            return false
        }
        
        // Create public key
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            if let error = error {
                Logger.shared.error("Failed to create public key: \(error.takeRetainedValue())")
            }
            return false
        }
        
        self.publicKey = key
        return true
    }
    
    /// Generate random bytes
    func generateRandom(length: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        
        guard status == errSecSuccess else {
            Logger.shared.error("Failed to generate random bytes: \(status)")
            return nil
        }
        
        return Data(bytes)
    }
    
    /// Encrypt data with public key (RSA-OAEP with SHA-256)
    func encrypt(data: Data) -> Data? {
        guard let publicKey = publicKey else {
            Logger.shared.error("Public key not set")
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            data as CFData,
            &error
        ) as Data? else {
            if let error = error {
                Logger.shared.error("Encryption failed: \(error.takeRetainedValue())")
            }
            return nil
        }

        return encryptedData
    }

    /// Verify signature (RSA-PSS with SHA-256)
    func verifySignature(data: Data, signature: Data) -> Bool {
        guard let publicKey = publicKey else {
            Logger.shared.error("Public key not set")
            return false
        }

        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePSSSHA256,
            data as CFData,
            signature as CFData,
            &error
        )

        if let error = error {
            Logger.shared.error("Signature verification error: \(error.takeRetainedValue())")
        }

        return result
    }
}

