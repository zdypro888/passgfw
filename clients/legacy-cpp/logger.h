#ifndef LOGGER_H
#define LOGGER_H

#include <string>

namespace PassGFW {

// Log levels
enum class LogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR
};

class Logger {
public:
    // Get singleton instance
    static Logger& GetInstance();
    
    // Set minimum log level (logs below this level will be ignored)
    void SetLogLevel(LogLevel level);
    
    // Enable/disable logging
    void SetEnabled(bool enabled);
    
    // Log methods
    void Debug(const std::string& message);
    void Info(const std::string& message);
    void Warning(const std::string& message);
    void Error(const std::string& message);
    
    // Formatted log methods
    void Debugf(const char* format, ...);
    void Infof(const char* format, ...);
    void Warningf(const char* format, ...);
    void Errorf(const char* format, ...);
    
private:
    Logger();
    ~Logger() = default;
    
    // Prevent copying
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;
    
    void Log(LogLevel level, const std::string& message);
    const char* GetLevelString(LogLevel level);
    
    LogLevel min_level_;
    bool enabled_;
};

// Convenience macros
#ifdef NDEBUG
    #define LOG_DEBUG(msg) ((void)0)
    #define LOG_DEBUGF(...) ((void)0)
#else
    #define LOG_DEBUG(msg) PassGFW::Logger::GetInstance().Debug(msg)
    #define LOG_DEBUGF(...) PassGFW::Logger::GetInstance().Debugf(__VA_ARGS__)
#endif

#define LOG_INFO(msg) PassGFW::Logger::GetInstance().Info(msg)
#define LOG_INFOF(...) PassGFW::Logger::GetInstance().Infof(__VA_ARGS__)
#define LOG_WARNING(msg) PassGFW::Logger::GetInstance().Warning(msg)
#define LOG_WARNINGF(...) PassGFW::Logger::GetInstance().Warningf(__VA_ARGS__)
#define LOG_ERROR(msg) PassGFW::Logger::GetInstance().Error(msg)
#define LOG_ERRORF(...) PassGFW::Logger::GetInstance().Errorf(__VA_ARGS__)

} // namespace PassGFW

#endif // LOGGER_H

