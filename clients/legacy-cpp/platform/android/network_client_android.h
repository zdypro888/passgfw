#ifndef PASSGFW_NETWORK_CLIENT_ANDROID_H
#define PASSGFW_NETWORK_CLIENT_ANDROID_H

#include "../../http_interface.h"
#include <string>

namespace passgfw {

/**
 * Android Platform Network Client Implementation
 * Using HttpURLConnection + JNI bridge
 */
class NetworkClientAndroid : public INetworkClient {
public:
    NetworkClientAndroid();
    ~NetworkClientAndroid() override;
    
    // Configuration interface
    bool SetPublicKey(const std::string& public_key_pem) override;
    void SetTimeout(int timeout_sec) override;
    
    // HTTP interface
    HttpResponse Post(const std::string& url, const std::string& json_body) override;
    HttpResponse Get(const std::string& url) override;
    
    // Encryption interface
    std::string GenerateRandom(int length) override;
    std::string EncryptWithPublicKey(const std::string& data) override;
    bool VerifySignature(const std::string& data, const std::string& signature) override;
    
    // JSON interface
    std::map<std::string, std::string> ParseJson(const std::string& json_str) override;
    std::string ToJson(const std::map<std::string, std::string>& data) override;
    
private:
    std::string public_key_pem_;
    int timeout_sec_;
};

} // namespace passgfw

#endif // PASSGFW_NETWORK_CLIENT_ANDROID_H
