#include "logger.h"
#include <cstdio>
#include <cstdarg>
#include <ctime>

namespace PassGFW {

Logger& Logger::GetInstance() {
    static Logger instance;
    return instance;
}

Logger::Logger() 
    : min_level_(LogLevel::DEBUG)
    , enabled_(true) {
}

void Logger::SetLogLevel(LogLevel level) {
    min_level_ = level;
}

void Logger::SetEnabled(bool enabled) {
    enabled_ = enabled;
}

void Logger::Debug(const std::string& message) {
    Log(LogLevel::DEBUG, message);
}

void Logger::Info(const std::string& message) {
    Log(LogLevel::INFO, message);
}

void Logger::Warning(const std::string& message) {
    Log(LogLevel::WARNING, message);
}

void Logger::Error(const std::string& message) {
    Log(LogLevel::ERROR, message);
}

void Logger::Debugf(const char* format, ...) {
    if (!enabled_ || min_level_ > LogLevel::DEBUG) {
        return;
    }
    
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    Log(LogLevel::DEBUG, buffer);
}

void Logger::Infof(const char* format, ...) {
    if (!enabled_ || min_level_ > LogLevel::INFO) {
        return;
    }
    
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    Log(LogLevel::INFO, buffer);
}

void Logger::Warningf(const char* format, ...) {
    if (!enabled_ || min_level_ > LogLevel::WARNING) {
        return;
    }
    
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    Log(LogLevel::WARNING, buffer);
}

void Logger::Errorf(const char* format, ...) {
    if (!enabled_ || min_level_ > LogLevel::ERROR) {
        return;
    }
    
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    Log(LogLevel::ERROR, buffer);
}

void Logger::Log(LogLevel level, const std::string& message) {
    if (!enabled_ || level < min_level_) {
        return;
    }
    
    // Get current time
    time_t now = time(nullptr);
    struct tm* timeinfo = localtime(&now);
    char time_buffer[32];
    strftime(time_buffer, sizeof(time_buffer), "%Y-%m-%d %H:%M:%S", timeinfo);
    
    // Print log message
    fprintf(stderr, "[%s] [%s] %s\n", time_buffer, GetLevelString(level), message.c_str());
    fflush(stderr);
}

const char* Logger::GetLevelString(LogLevel level) {
    switch (level) {
        case LogLevel::DEBUG:   return "DEBUG";
        case LogLevel::INFO:    return "INFO";
        case LogLevel::WARNING: return "WARNING";
        case LogLevel::ERROR:   return "ERROR";
        default:                return "UNKNOWN";
    }
}

} // namespace PassGFW

