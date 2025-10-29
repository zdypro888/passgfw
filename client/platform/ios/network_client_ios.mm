#import "network_client_ios.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>

namespace passgfw {

// Helper function: Safely convert NSString to std::string
// MUST be called inside @autoreleasepool
static std::string NSStringToStdString(NSString* nsStr) {
    if (!nsStr) {
        return "";
    }
    const char* utf8Str = [nsStr UTF8String];
    if (!utf8Str) {
        return "";
    }
    return std::string(utf8Str);
}

// Factory function implementation
INetworkClient* CreatePlatformNetworkClient() {
    return new NetworkClientIOS();
}

NetworkClientIOS::NetworkClientIOS() 
    : public_key_(nullptr), timeout_sec_(10) {
}

NetworkClientIOS::~NetworkClientIOS() {
    if (public_key_) {
        CFRelease((SecKeyRef)public_key_);
        public_key_ = nullptr;
    }
}

// ==================== Configuration Interface ====================

bool NetworkClientIOS::SetPublicKey(const std::string& public_key_pem) {
    @autoreleasepool {
        // Remove PEM header/footer and newlines
        NSString* pemString = [NSString stringWithUTF8String:public_key_pem.c_str()];
        pemString = [pemString stringByReplacingOccurrencesOfString:@"-----BEGIN PUBLIC KEY-----" withString:@""];
        pemString = [pemString stringByReplacingOccurrencesOfString:@"-----END PUBLIC KEY-----" withString:@""];
        pemString = [pemString stringByReplacingOccurrencesOfString:@"\n" withString:@""];
        pemString = [pemString stringByReplacingOccurrencesOfString:@"\r" withString:@""];
        pemString = [pemString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Base64 decode
        NSData* keyData = [[NSData alloc] initWithBase64EncodedString:pemString options:0];
        if (!keyData) {
            return false;
        }
        
        // Create public key
        NSDictionary* attributes = @{
            (id)kSecAttrKeyType: (id)kSecAttrKeyTypeRSA,
            (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPublic
        };
        
        CFErrorRef error = NULL;
        SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)keyData, 
                                            (__bridge CFDictionaryRef)attributes, 
                                            &error);
        
        if (error || !key) {
            if (error) CFRelease(error);
            return false;
        }
        
        // Release old public key
        if (public_key_) {
            CFRelease((SecKeyRef)public_key_);
        }
        
        public_key_ = (void*)key;
        return true;
    }
}

void NetworkClientIOS::SetTimeout(int timeout_sec) {
    timeout_sec_ = timeout_sec;
}

// ==================== HTTP Interface ====================

HttpResponse NetworkClientIOS::Post(const std::string& url, const std::string& json_body) {
    @autoreleasepool {
        HttpResponse response;
        
        // Debug: Print parameters
        printf("[DEBUG] Post() called\n");
        printf("[DEBUG]   URL: %s (length: %zu)\n", url.c_str(), url.length());
        printf("[DEBUG]   JSON body: %s (length: %zu)\n", json_body.c_str(), json_body.length());
        
        // Create URL
        NSURL* nsURL = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]];
        if (!nsURL) {
            response.error_msg = "Invalid URL";
            return response;
        }
        
        // Create request
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:nsURL];
        [request setHTTPMethod:@"POST"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setTimeoutInterval:timeout_sec_];
        
        // Set request body
        NSString* bodyString = nil;
        if (!json_body.empty()) {
            bodyString = [NSString stringWithUTF8String:json_body.c_str()];
        }
        
        if (bodyString) {
            NSData* bodyData = [bodyString dataUsingEncoding:NSUTF8StringEncoding];
            [request setHTTPBody:bodyData];
        }
        
        // Synchronous request
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSData* responseData = nil;
        __block NSHTTPURLResponse* httpResponse = nil;
        __block NSError* error = nil;
        
        NSURLSession* session = [NSURLSession sharedSession];
        NSURLSessionDataTask* task = [session dataTaskWithRequest:request 
            completionHandler:^(NSData* data, NSURLResponse* urlResponse, NSError* taskError) {
                responseData = data;
                httpResponse = (NSHTTPURLResponse*)urlResponse;
                error = taskError;
                dispatch_semaphore_signal(semaphore);
            }];
        
        [task resume];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        // Handle response
        if (error) {
            response.error_msg = NSStringToStdString([error localizedDescription]);
            return response;
        }
        
        response.success = true;
        response.status_code = (int)[httpResponse statusCode];
        
        if (responseData) {
            NSString* responseString = [[NSString alloc] initWithData:responseData 
                                                             encoding:NSUTF8StringEncoding];
            response.body = NSStringToStdString(responseString);
        }
        
        return response;
    }
}

HttpResponse NetworkClientIOS::Get(const std::string& url) {
    @autoreleasepool {
        HttpResponse response;
        
        // Create URL
        NSURL* nsURL = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]];
        if (!nsURL) {
            response.error_msg = "Invalid URL";
            return response;
        }
        
        // Create request
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:nsURL];
        [request setHTTPMethod:@"GET"];
        [request setTimeoutInterval:timeout_sec_];
        
        // Synchronous request
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSData* responseData = nil;
        __block NSHTTPURLResponse* httpResponse = nil;
        __block NSError* error = nil;
        
        NSURLSession* session = [NSURLSession sharedSession];
        NSURLSessionDataTask* task = [session dataTaskWithRequest:request 
            completionHandler:^(NSData* data, NSURLResponse* urlResponse, NSError* taskError) {
                responseData = data;
                httpResponse = (NSHTTPURLResponse*)urlResponse;
                error = taskError;
                dispatch_semaphore_signal(semaphore);
            }];
        
        [task resume];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        // Handle response
        if (error) {
            response.error_msg = NSStringToStdString([error localizedDescription]);
            return response;
        }
        
        response.success = true;
        response.status_code = (int)[httpResponse statusCode];
        
        if (responseData) {
            NSString* responseString = [[NSString alloc] initWithData:responseData 
                                                             encoding:NSUTF8StringEncoding];
            response.body = NSStringToStdString(responseString);
        }
        
        return response;
    }
}

// ==================== Encryption Interface ====================

std::string NetworkClientIOS::GenerateRandom(int length) {
    @autoreleasepool {
        // Generate random bytes
        NSMutableData* randomData = [NSMutableData dataWithLength:length];
        int result = SecRandomCopyBytes(kSecRandomDefault, length, 
                                       [randomData mutableBytes]);
        
        if (result != errSecSuccess) {
            return "";
        }
        
        // Base64 encode
        NSString* base64String = [randomData base64EncodedStringWithOptions:0];
        return NSStringToStdString(base64String);
    }
}

std::string NetworkClientIOS::EncryptWithPublicKey(const std::string& data) {
    @autoreleasepool {
        if (!public_key_) {
            return "";
        }
        
        SecKeyRef publicKey = (SecKeyRef)public_key_;
        
        // Prepare data
        NSData* plainData = [[NSString stringWithUTF8String:data.c_str()] 
                            dataUsingEncoding:NSUTF8StringEncoding];
        
        // Encrypt with public key
        CFErrorRef error = NULL;
        NSData* encryptedData = (__bridge_transfer NSData*)SecKeyCreateEncryptedData(
            publicKey,
            kSecKeyAlgorithmRSAEncryptionPKCS1,
            (__bridge CFDataRef)plainData,
            &error);
        
        if (error || !encryptedData) {
            if (error) CFRelease(error);
            return "";
        }
        
        // Base64 encode
        NSString* base64String = [encryptedData base64EncodedStringWithOptions:0];
        return NSStringToStdString(base64String);
    }
}

bool NetworkClientIOS::VerifySignature(const std::string& data, 
                                       const std::string& signature) {
    @autoreleasepool {
        if (!public_key_) {
            return false;
        }
        
        SecKeyRef publicKey = (SecKeyRef)public_key_;
        
        // Prepare data
        NSData* plainData = [[NSString stringWithUTF8String:data.c_str()] 
                            dataUsingEncoding:NSUTF8StringEncoding];
        
        // Base64 decode signature
        NSString* signatureBase64 = [NSString stringWithUTF8String:signature.c_str()];
        NSData* signatureData = [[NSData alloc] initWithBase64EncodedString:signatureBase64 
                                                                   options:0];
        if (!signatureData) {
            return false;
        }
        
        // Verify signature
        CFErrorRef error = NULL;
        Boolean verified = SecKeyVerifySignature(
            publicKey,
            kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
            (__bridge CFDataRef)plainData,
            (__bridge CFDataRef)signatureData,
            &error);
        
        if (error) {
            CFRelease(error);
            return false;
        }
        
        return verified == true;
    }
}

// ==================== JSON Interface ====================

std::map<std::string, std::string> NetworkClientIOS::ParseJson(
    const std::string& json_str) {
    @autoreleasepool {
        std::map<std::string, std::string> result;
        
        NSString* jsonString = [NSString stringWithUTF8String:json_str.c_str()];
        NSData* jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        
        if (!jsonData) {
            return result;
        }
        
        NSError* error = nil;
        NSDictionary* jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData 
                                                                  options:0 
                                                                    error:&error];
        
        if (error || ![jsonDict isKindOfClass:[NSDictionary class]]) {
            return result;
        }
        
        // Convert to std::map
        for (NSString* key in jsonDict) {
            std::string keyStr = NSStringToStdString(key);
            id value = jsonDict[key];
            if ([value isKindOfClass:[NSString class]]) {
                result[keyStr] = NSStringToStdString((NSString*)value);
            } else if ([value isKindOfClass:[NSNumber class]]) {
                result[keyStr] = NSStringToStdString([(NSNumber*)value stringValue]);
            }
        }
        
        return result;
    }
}

std::string NetworkClientIOS::ToJson(
    const std::map<std::string, std::string>& data) {
    @autoreleasepool {
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        
        for (const auto& pair : data) {
            NSString* key = [NSString stringWithUTF8String:pair.first.c_str()];
            NSString* value = [NSString stringWithUTF8String:pair.second.c_str()];
            dict[key] = value;
        }
        
        NSError* error = nil;
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:dict 
                                                          options:0 
                                                            error:&error];
        
        if (error || !jsonData) {
            return "";
        }
        
        NSString* jsonString = [[NSString alloc] initWithData:jsonData 
                                                     encoding:NSUTF8StringEncoding];
        return NSStringToStdString(jsonString);
    }
}

} // namespace passgfw
