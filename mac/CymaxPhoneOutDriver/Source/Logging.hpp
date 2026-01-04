//
//  Logging.hpp
//  CymaxPhoneOutDriver
//
//  Compile-time controlled logging for the AudioServerPlugIn
//
//  CRITICAL RULES:
//  - Logging in the render callback (DoIOOperation) is COMPILE-TIME DISABLED
//  - Logging NEVER allocates memory
//  - Logging NEVER touches the filesystem from within the plugin
//  - For MVP, we use os_log which is lock-free and designed for real-time contexts
//    BUT we still disable it in the render path to be extra safe
//

#ifndef Logging_hpp
#define Logging_hpp

#include <os/log.h>
#include <cstdio>
#include <cstdarg>

// Compile-time switches for logging levels
// Set to 0 to completely remove logging code from binary
#define CYMAX_LOG_ENABLED 1
#define CYMAX_LOG_DEBUG_ENABLED 1
#define CYMAX_LOG_VERBOSE_ENABLED 0

// NEVER enable this in production - allows logging in render callback
// This should ONLY be used for debugging in development builds
#define CYMAX_LOG_RENDER_CALLBACK 0

namespace CymaxLog {

// os_log subsystem and categories
inline os_log_t getLogHandle() {
    static os_log_t log = os_log_create("com.cymax.phoneoutdriver", "driver");
    return log;
}

inline os_log_t getAudioLogHandle() {
    static os_log_t log = os_log_create("com.cymax.phoneoutdriver", "audio");
    return log;
}

inline os_log_t getNetworkLogHandle() {
    static os_log_t log = os_log_create("com.cymax.phoneoutdriver", "network");
    return log;
}

} // namespace CymaxLog

// Main logging macros
#if CYMAX_LOG_ENABLED

#define CYMAX_LOG_ERROR(fmt, ...) \
    os_log_error(CymaxLog::getLogHandle(), fmt, ##__VA_ARGS__)

#define CYMAX_LOG_INFO(fmt, ...) \
    os_log_info(CymaxLog::getLogHandle(), fmt, ##__VA_ARGS__)

#define CYMAX_LOG_AUDIO(fmt, ...) \
    os_log_info(CymaxLog::getAudioLogHandle(), fmt, ##__VA_ARGS__)

#define CYMAX_LOG_NETWORK(fmt, ...) \
    os_log_info(CymaxLog::getNetworkLogHandle(), fmt, ##__VA_ARGS__)

#else

#define CYMAX_LOG_ERROR(fmt, ...) ((void)0)
#define CYMAX_LOG_INFO(fmt, ...) ((void)0)
#define CYMAX_LOG_AUDIO(fmt, ...) ((void)0)
#define CYMAX_LOG_NETWORK(fmt, ...) ((void)0)

#endif

// Debug logging (can be disabled separately)
#if CYMAX_LOG_ENABLED && CYMAX_LOG_DEBUG_ENABLED

#define CYMAX_LOG_DEBUG(fmt, ...) \
    os_log_debug(CymaxLog::getLogHandle(), fmt, ##__VA_ARGS__)

#else

#define CYMAX_LOG_DEBUG(fmt, ...) ((void)0)

#endif

// Verbose logging for detailed tracing
#if CYMAX_LOG_ENABLED && CYMAX_LOG_VERBOSE_ENABLED

#define CYMAX_LOG_VERBOSE(fmt, ...) \
    os_log_debug(CymaxLog::getLogHandle(), fmt, ##__VA_ARGS__)

#else

#define CYMAX_LOG_VERBOSE(fmt, ...) ((void)0)

#endif

// Render callback logging - DISABLED BY DEFAULT
// This macro exists ONLY for development debugging
// NEVER ship with this enabled
#if CYMAX_LOG_RENDER_CALLBACK

#define CYMAX_LOG_RENDER(fmt, ...) \
    os_log_debug(CymaxLog::getAudioLogHandle(), fmt, ##__VA_ARGS__)

#else

// This is the production setting - render callback logging is a no-op
#define CYMAX_LOG_RENDER(fmt, ...) ((void)0)

#endif

// Utility macro to log with function name
#define CYMAX_LOG_FUNC() \
    CYMAX_LOG_DEBUG("%{public}s", __FUNCTION__)

// Assert macro for development
#if DEBUG
#define CYMAX_ASSERT(condition, msg) \
    do { \
        if (!(condition)) { \
            CYMAX_LOG_ERROR("Assertion failed: %{public}s - %{public}s", #condition, msg); \
            __builtin_trap(); \
        } \
    } while(0)
#else
#define CYMAX_ASSERT(condition, msg) ((void)0)
#endif

#endif /* Logging_hpp */

