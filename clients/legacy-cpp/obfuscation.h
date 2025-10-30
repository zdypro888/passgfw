#ifndef PASSGFW_OBFUSCATION_H
#define PASSGFW_OBFUSCATION_H

#include <string>
#include <vector>
#include <cstdint>

namespace passgfw {

/**
 * Simple XOR-based string decryption
 * 简单的XOR解密（运行时）
 */
class Obfuscation {
public:
    // Generate XOR key based on index and seed
    static inline uint8_t xor_key(size_t index, uint64_t seed) {
        // Simple pseudo-random key generation
        uint64_t val = seed ^ (index * 0x9E3779B97F4A7C15ULL);
        val = (val ^ (val >> 30)) * 0xBF58476D1CE4E5B9ULL;
        val = (val ^ (val >> 27)) * 0x94D049BB133111EBULL;
        return static_cast<uint8_t>((val ^ (val >> 31)) & 0xFF);
    }
    
    // Decrypt a single string
    static std::string decrypt_string(const uint8_t* data, size_t length, uint64_t seed) {
        std::string result;
        result.reserve(length);
        for (size_t i = 0; i < length; ++i) {
            result += static_cast<char>(data[i] ^ xor_key(i, seed));
        }
        return result;
    }
    
    // Decrypt array of strings
    static std::vector<std::string> decrypt_strings(
        const uint8_t* data,
        const size_t* lengths,
        const size_t* offsets,
        size_t count,
        uint64_t seed)
    {
        std::vector<std::string> result;
        result.reserve(count);
        for (size_t i = 0; i < count; ++i) {
            result.push_back(decrypt_string(data + offsets[i], lengths[i], seed));
        }
        return result;
    }
};

} // namespace passgfw

#endif // PASSGFW_OBFUSCATION_H

