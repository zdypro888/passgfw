package com.passgfw;

import java.io.*;
import java.net.*;
import java.security.*;
import java.security.spec.*;
import javax.crypto.*;
import org.json.*;
import android.util.Base64;

/**
 * Network Helper - Android Platform Implementation
 * 
 * This is a FRAMEWORK class. You need to complete the implementation.
 * 
 * Main Functions:
 * 1. HTTP/HTTPS Requests (POST/GET)
 * 2. JSON Parsing and Generation
 * 3. RSA Encryption and Signature Verification
 * 
 * The C++ layer calls these methods via JNI.
 * 
 * @version 1.0
 * @author PassGFW Team
 */
public class NetworkHelper {
    
    private PublicKey publicKey;
    private int timeoutMs = 10000;
    
    // ==================== Configuration ====================
    
    /**
     * Set Public Key
     * @param publicKeyPem PEM format public key (remove BEGIN/END markers)
     * @return true on success
     */
    public boolean setPublicKey(String publicKeyPem) {
        try {
            // TODO: Parse PEM format public key
            // 1. Remove "-----BEGIN PUBLIC KEY-----" and "-----END PUBLIC KEY-----"
            // 2. Base64 decode
            // 3. Use KeyFactory to generate PublicKey
            
            byte[] keyBytes = Base64.decode(publicKeyPem, Base64.DEFAULT);
            X509EncodedKeySpec spec = new X509EncodedKeySpec(keyBytes);
            KeyFactory keyFactory = KeyFactory.getInstance("RSA");
            this.publicKey = keyFactory.generatePublic(spec);
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }
    
    /**
     * Set Timeout (milliseconds)
     */
    public void setTimeout(int timeoutMs) {
        this.timeoutMs = timeoutMs;
    }
    
    // ==================== HTTP Interface ====================
    
    /**
     * HTTP POST Request
     * @param url Target URL
     * @param jsonBody JSON format request body
     * @return Response { success: boolean, statusCode: int, body: string, error: string }
     */
    public HttpResponse post(String url, String jsonBody) {
        HttpResponse response = new HttpResponse();
        
        try {
            // TODO: Implement HTTP POST using HttpURLConnection
            // 1. Create URL and open connection
            // 2. Set request method to POST
            // 3. Set Content-Type: application/json
            // 4. Set timeout
            // 5. Write request body
            // 6. Read response
            
            URL urlObj = new URL(url);
            HttpURLConnection conn = (HttpURLConnection) urlObj.openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            conn.setDoOutput(true);
            
            // Write request body
            try (OutputStream os = conn.getOutputStream()) {
                byte[] input = jsonBody.getBytes("UTF-8");
                os.write(input, 0, input.length);
            }
            
            // Read response
            response.statusCode = conn.getResponseCode();
            
            if (response.statusCode == 200) {
                BufferedReader br = new BufferedReader(
                    new InputStreamReader(conn.getInputStream(), "UTF-8"));
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = br.readLine()) != null) {
                    sb.append(line);
                }
                response.body = sb.toString();
                response.success = true;
            } else {
                response.error = "HTTP error: " + response.statusCode;
            }
            
            conn.disconnect();
            
        } catch (Exception e) {
            response.success = false;
            response.error = e.getMessage();
        }
        
        return response;
    }
    
    /**
     * HTTP GET Request
     * @param url Target URL
     * @return Response { success: boolean, statusCode: int, body: string, error: string }
     */
    public HttpResponse get(String url) {
        HttpResponse response = new HttpResponse();
        
        try {
            // TODO: Implement HTTP GET using HttpURLConnection
            // 1. Create URL and open connection
            // 2. Set request method to GET
            // 3. Set timeout
            // 4. Read response
            
            URL urlObj = new URL(url);
            HttpURLConnection conn = (HttpURLConnection) urlObj.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            
            response.statusCode = conn.getResponseCode();
            
            if (response.statusCode == 200) {
                BufferedReader br = new BufferedReader(
                    new InputStreamReader(conn.getInputStream(), "UTF-8"));
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = br.readLine()) != null) {
                    sb.append(line).append("\n");
                }
                response.body = sb.toString();
                response.success = true;
            } else {
                response.error = "HTTP error: " + response.statusCode;
            }
            
            conn.disconnect();
            
        } catch (Exception e) {
            response.success = false;
            response.error = e.getMessage();
        }
        
        return response;
    }
    
    // ==================== Cryptography Interface ====================
    
    /**
     * Generate Random Data
     * @param length Random data length (bytes)
     * @return Base64 encoded random data
     */
    public String generateRandom(int length) {
        try {
            // TODO: Use SecureRandom to generate random bytes
            SecureRandom random = new SecureRandom();
            byte[] bytes = new byte[length];
            random.nextBytes(bytes);
            return Base64.encodeToString(bytes, Base64.NO_WRAP);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }
    
    /**
     * Encrypt Data with Public Key
     * @param data Raw data (Base64 encoded)
     * @return Base64 encoded encrypted data
     */
    public String encryptWithPublicKey(String data) {
        try {
            if (publicKey == null) {
                throw new Exception("Public key not set");
            }
            
            // TODO: Use RSA public key to encrypt data
            // 1. Decode input data (if Base64)
            // 2. Use Cipher.getInstance("RSA/ECB/PKCS1Padding") to encrypt
            // 3. Return Base64 encoded result
            
            byte[] dataBytes = Base64.decode(data, Base64.DEFAULT);
            Cipher cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding");
            cipher.init(Cipher.ENCRYPT_MODE, publicKey);
            byte[] encrypted = cipher.doFinal(dataBytes);
            return Base64.encodeToString(encrypted, Base64.NO_WRAP);
            
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }
    
    /**
     * Verify Signature
     * @param data Original data
     * @param signature Base64 encoded signature
     * @return true if signature is valid
     */
    public boolean verifySignature(String data, String signature) {
        try {
            if (publicKey == null) {
                throw new Exception("Public key not set");
            }
            
            // TODO: Use RSA public key to verify signature
            // 1. Decode signature (Base64)
            // 2. Use Signature.getInstance("SHA256withRSA") to verify
            // 3. Return verification result
            
            byte[] dataBytes = data.getBytes("UTF-8");
            byte[] signatureBytes = Base64.decode(signature, Base64.DEFAULT);
            
            Signature sig = Signature.getInstance("SHA256withRSA");
            sig.initVerify(publicKey);
            sig.update(dataBytes);
            return sig.verify(signatureBytes);
            
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }
    
    // ==================== JSON Interface ====================
    
    /**
     * Parse JSON String
     * @param jsonStr JSON string
     * @return Key-value map (only supports string values)
     */
    public java.util.Map<String, String> parseJson(String jsonStr) {
        java.util.Map<String, String> result = new java.util.HashMap<>();
        
        try {
            // TODO: Use org.json.JSONObject to parse JSON
            JSONObject json = new JSONObject(jsonStr);
            java.util.Iterator<String> keys = json.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                result.put(key, json.getString(key));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        
        return result;
    }
    
    /**
     * Convert Map to JSON String
     * @param data Key-value map
     * @return JSON string
     */
    public String toJson(java.util.Map<String, String> data) {
        try {
            // TODO: Use org.json.JSONObject to generate JSON
            JSONObject json = new JSONObject();
            for (java.util.Map.Entry<String, String> entry : data.entrySet()) {
                json.put(entry.getKey(), entry.getValue());
            }
            return json.toString();
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }
    
    // ==================== Data Structures ====================
    
    /**
     * HTTP Response Structure
     */
    public static class HttpResponse {
        public boolean success = false;
        public int statusCode = 0;
        public String body = "";
        public String error = "";
    }
}
