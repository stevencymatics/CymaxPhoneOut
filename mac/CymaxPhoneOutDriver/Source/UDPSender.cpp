//
//  UDPSender.cpp
//  CymaxPhoneOutDriver
//
//  Implementation of non-blocking UDP audio packet sender
//

#include "UDPSender.hpp"
#include "RingBuffer.hpp"
#include "Logging.hpp"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <mach/mach_time.h>
#include <cstring>

namespace Cymax {

// Audio packet header structure matching the Swift definition
// Total size: 28 bytes
#pragma pack(push, 1)
struct AudioPacketHeader {
    uint32_t magic;         // 'CMAX' = 0x584D4143 little-endian
    uint32_t sequence;
    uint64_t timestamp;
    uint32_t sampleRate;
    uint16_t channels;
    uint16_t frameCount;
    uint16_t format;        // 1 = float32, 2 = int16
    uint16_t flags;
    
    static constexpr uint32_t kMagic = 0x584D4143;  // 'XMAC' in LE = 'CMAX'
    static constexpr size_t kSize = 28;
};
#pragma pack(pop)

static_assert(sizeof(AudioPacketHeader) == 28, "AudioPacketHeader must be 28 bytes");

// Convert mach_absolute_time to nanoseconds
static uint64_t machTimeToNanos(uint64_t machTime) {
    static mach_timebase_info_data_t timebaseInfo = {0, 0};
    if (timebaseInfo.denom == 0) {
        mach_timebase_info(&timebaseInfo);
    }
    return machTime * timebaseInfo.numer / timebaseInfo.denom;
}

UDPSender::UDPSender() {
    std::memset(&m_destAddr, 0, sizeof(m_destAddr));
    std::memset(m_packetBuffer, 0, sizeof(m_packetBuffer));
}

UDPSender::~UDPSender() {
    stop();
    closeSocket();
}

bool UDPSender::initialize(RingBuffer<float>* ringBuffer, const UDPSenderConfig& config) {
    if (!ringBuffer) {
        CYMAX_LOG_ERROR("UDPSender::initialize - null ring buffer");
        return false;
    }
    
    m_ringBuffer = ringBuffer;
    m_config = config;
    
    CYMAX_LOG_INFO("UDPSender initialized: %u Hz, %u ch, %u frames/packet",
                   config.sampleRate, config.channels, config.framesPerPacket);
    
    return true;
}

bool UDPSender::setDestination(const char* ipAddress) {
    if (!ipAddress || strlen(ipAddress) == 0) {
        m_hasDestination.store(false, std::memory_order_release);
        CYMAX_LOG_INFO("UDPSender: destination cleared");
        return false;
    }
    
    // Parse IP address
    struct in_addr addr;
    if (inet_pton(AF_INET, ipAddress, &addr) != 1) {
        CYMAX_LOG_ERROR("UDPSender: invalid IP address: %{public}s", ipAddress);
        m_hasDestination.store(false, std::memory_order_release);
        return false;
    }
    
    // Store destination
    std::memset(&m_destAddr, 0, sizeof(m_destAddr));
    m_destAddr.sin_family = AF_INET;
    m_destAddr.sin_addr = addr;
    m_destAddr.sin_port = htons(m_config.destPort);
    
    strncpy(m_config.destIP, ipAddress, sizeof(m_config.destIP) - 1);
    m_hasDestination.store(true, std::memory_order_release);
    
    CYMAX_LOG_INFO("UDPSender: destination set to %{public}s:%u", ipAddress, m_config.destPort);
    return true;
}

bool UDPSender::createSocket() {
    if (m_socket >= 0) {
        return true;  // Already created
    }
    
    // Create UDP socket
    m_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (m_socket < 0) {
        CYMAX_LOG_ERROR("UDPSender: failed to create socket: %{public}s", strerror(errno));
        return false;
    }
    
    // Set non-blocking mode
    int flags = fcntl(m_socket, F_GETFL, 0);
    if (flags < 0 || fcntl(m_socket, F_SETFL, flags | O_NONBLOCK) < 0) {
        CYMAX_LOG_ERROR("UDPSender: failed to set non-blocking: %{public}s", strerror(errno));
        closeSocket();
        return false;
    }
    
    // Set send buffer size
    int sendBufSize = 262144;  // 256KB
    if (setsockopt(m_socket, SOL_SOCKET, SO_SNDBUF, &sendBufSize, sizeof(sendBufSize)) < 0) {
        CYMAX_LOG_DEBUG("UDPSender: couldn't set send buffer size (non-fatal)");
    }
    
    // Disable SIGPIPE
    int nosigpipe = 1;
    setsockopt(m_socket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, sizeof(nosigpipe));
    
    CYMAX_LOG_INFO("UDPSender: socket created");
    return true;
}

void UDPSender::closeSocket() {
    if (m_socket >= 0) {
        close(m_socket);
        m_socket = -1;
        CYMAX_LOG_INFO("UDPSender: socket closed");
    }
}

bool UDPSender::start() {
    if (m_running.load(std::memory_order_acquire)) {
        CYMAX_LOG_DEBUG("UDPSender: already running");
        return true;
    }
    
    if (!m_ringBuffer) {
        CYMAX_LOG_ERROR("UDPSender: cannot start without ring buffer");
        return false;
    }
    
    if (!createSocket()) {
        return false;
    }
    
    // Reset state
    m_shouldStop.store(false, std::memory_order_release);
    m_sequence.store(0, std::memory_order_relaxed);
    m_packetsSent.store(0, std::memory_order_relaxed);
    m_packetsDropped.store(0, std::memory_order_relaxed);
    m_framesDropped.store(0, std::memory_order_relaxed);
    
    // Start sender thread
    m_senderThread = std::thread(&UDPSender::senderThreadFunc, this);
    m_running.store(true, std::memory_order_release);
    
    CYMAX_LOG_INFO("UDPSender: started");
    return true;
}

void UDPSender::stop() {
    if (!m_running.load(std::memory_order_acquire)) {
        return;
    }
    
    // Signal thread to stop
    m_shouldStop.store(true, std::memory_order_release);
    
    // Wait for thread to finish
    if (m_senderThread.joinable()) {
        m_senderThread.join();
    }
    
    m_running.store(false, std::memory_order_release);
    CYMAX_LOG_INFO("UDPSender: stopped (sent: %llu, dropped: %llu)",
                   m_packetsSent.load(), m_packetsDropped.load());
}

void UDPSender::updateConfig(const UDPSenderConfig& config) {
    // Only update when not running
    if (m_running.load(std::memory_order_acquire)) {
        CYMAX_LOG_ERROR("UDPSender: cannot update config while running");
        return;
    }
    
    m_config = config;
    CYMAX_LOG_INFO("UDPSender: config updated - %u Hz, %u ch",
                   config.sampleRate, config.channels);
}

void UDPSender::senderThreadFunc() {
    CYMAX_LOG_INFO("UDPSender: thread started");
    
    // Set thread priority (not real-time, but elevated)
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    
    // Calculate timing
    const double packetDurationSecs = static_cast<double>(m_config.framesPerPacket) / 
                                       static_cast<double>(m_config.sampleRate);
    const uint64_t targetIntervalNanos = static_cast<uint64_t>(packetDurationSecs * 1e9);
    
    // Preallocate read buffer for audio samples
    const size_t samplesPerPacket = m_config.framesPerPacket * m_config.channels;
    std::vector<float> audioSamples(samplesPerPacket);
    
    uint64_t nextSendTime = mach_absolute_time();
    
    while (!m_shouldStop.load(std::memory_order_acquire)) {
        // Check if we have a destination
        if (!m_hasDestination.load(std::memory_order_acquire)) {
            // No destination, just drain the ring buffer to prevent buildup
            size_t available = m_ringBuffer->availableForRead();
            if (available > 0) {
                m_ringBuffer->dropFrames(available);
                m_framesDropped.fetch_add(available, std::memory_order_relaxed);
            }
            
            // Sleep briefly and continue
            struct timespec ts = {0, 1000000};  // 1ms
            nanosleep(&ts, nullptr);
            continue;
        }
        
        // Try to read enough frames for a packet
        size_t framesRead = m_ringBuffer->read(audioSamples.data(), m_config.framesPerPacket);
        
        if (framesRead < m_config.framesPerPacket) {
            // Not enough data yet, wait a bit
            // This is normal during startup or low-activity periods
            struct timespec ts = {0, 500000};  // 0.5ms
            nanosleep(&ts, nullptr);
            continue;
        }
        
        // Build the packet header
        AudioPacketHeader* header = reinterpret_cast<AudioPacketHeader*>(m_packetBuffer);
        header->magic = AudioPacketHeader::kMagic;
        header->sequence = m_sequence.fetch_add(1, std::memory_order_relaxed);
        header->timestamp = machTimeToNanos(mach_absolute_time());
        header->sampleRate = m_config.sampleRate;
        header->channels = m_config.channels;
        header->frameCount = m_config.framesPerPacket;
        header->format = m_config.useFloat32 ? 1 : 2;
        header->flags = 0;
        
        // Copy audio data after header
        const size_t audioBytes = framesRead * m_config.channels * sizeof(float);
        std::memcpy(m_packetBuffer + AudioPacketHeader::kSize, audioSamples.data(), audioBytes);
        
        // Send the packet
        const size_t packetSize = AudioPacketHeader::kSize + audioBytes;
        ssize_t sent = sendto(m_socket, m_packetBuffer, packetSize, 0,
                              reinterpret_cast<struct sockaddr*>(&m_destAddr),
                              sizeof(m_destAddr));
        
        if (sent < 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                // Real error
                m_packetsDropped.fetch_add(1, std::memory_order_relaxed);
                CYMAX_LOG_NETWORK("UDPSender: send failed: %{public}s", strerror(errno));
            }
            // For EAGAIN/EWOULDBLOCK, packet is dropped (non-blocking behavior)
        } else {
            m_packetsSent.fetch_add(1, std::memory_order_relaxed);
        }
        
        // Pace ourselves to avoid busy-looping
        // Use a simple timing approach - send when we have data
        // The ring buffer naturally rate-limits based on render callback rate
        
        // Small yield to prevent CPU spinning if we're ahead
        struct timespec ts = {0, 100000};  // 0.1ms
        nanosleep(&ts, nullptr);
    }
    
    CYMAX_LOG_INFO("UDPSender: thread exiting");
}

bool UDPSender::sendPacket() {
    // This method is not used in the current implementation
    // Keeping for potential future refactoring
    return false;
}

} // namespace Cymax

