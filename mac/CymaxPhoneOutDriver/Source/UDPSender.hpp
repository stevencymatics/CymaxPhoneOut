//
//  UDPSender.hpp
//  CymaxPhoneOutDriver
//
//  Non-blocking UDP audio packet sender
//
//  SAFETY CONSTRAINTS:
//  - Runs on a dedicated non-real-time thread
//  - Uses non-blocking sockets only
//  - NO TCP sockets in this class
//  - If it falls behind, it drops audio frames (never blocks render)
//
//  MVP TRADEOFF DOCUMENTATION:
//  This UDP sender runs inside the AudioServerPlugIn process.
//  For production, this should migrate to a user-space app
//  communicating via XPC + shared memory for:
//  - Better security isolation
//  - Easier debugging
//  - More flexible networking options
//

#ifndef UDPSender_hpp
#define UDPSender_hpp

#include <atomic>
#include <thread>
#include <cstdint>
#include <netinet/in.h>

namespace Cymax {

// Forward declaration
template<typename T> class RingBuffer;

/// Configuration for the UDP sender
struct UDPSenderConfig {
    /// Sample rate in Hz
    uint32_t sampleRate = 48000;
    
    /// Number of channels
    uint16_t channels = 2;
    
    /// Frames per UDP packet (128 fits under MTU: 28 header + 128*2*4 = 1052 bytes)
    uint16_t framesPerPacket = 128;
    
    /// Target destination port
    uint16_t destPort = 19620;
    
    /// Destination IP address (set via setDestination)
    char destIP[64] = {0};
    
    /// Whether to use Float32 (true) or Int16 (false)
    bool useFloat32 = true;
};

/// UDP audio packet sender
class UDPSender {
public:
    UDPSender();
    ~UDPSender();
    
    // Non-copyable
    UDPSender(const UDPSender&) = delete;
    UDPSender& operator=(const UDPSender&) = delete;
    
    /// Initialize the sender with a ring buffer to read from
    /// @param ringBuffer The ring buffer containing audio data
    /// @param config Sender configuration
    /// @return true if initialization succeeded
    bool initialize(RingBuffer<float>* ringBuffer, const UDPSenderConfig& config);
    
    /// Set the destination IP address
    /// @param ipAddress IPv4 address string (e.g., "172.20.10.1")
    /// @return true if address is valid
    bool setDestination(const char* ipAddress);
    
    /// Start the sender thread
    /// @return true if started successfully
    bool start();
    
    /// Stop the sender thread
    void stop();
    
    /// Check if sender is running
    bool isRunning() const { return m_running.load(std::memory_order_acquire); }
    
    /// Check if sender has a valid destination
    bool hasDestination() const { return m_hasDestination.load(std::memory_order_acquire); }
    
    /// Get current sequence number
    uint32_t currentSequence() const { return m_sequence.load(std::memory_order_relaxed); }
    
    /// Get packets sent count
    uint64_t packetsSent() const { return m_packetsSent.load(std::memory_order_relaxed); }
    
    /// Get packets dropped count (due to network errors)
    uint64_t packetsDropped() const { return m_packetsDropped.load(std::memory_order_relaxed); }
    
    /// Get frames dropped count (due to falling behind)
    uint64_t framesDropped() const { return m_framesDropped.load(std::memory_order_relaxed); }
    
    /// Get ring buffer high water mark (peak fill level in frames)
    size_t ringBufferHighWater() const;
    
    /// Reset ring buffer high water mark
    void resetRingBufferHighWater();
    
    /// Update configuration (call when not running)
    void updateConfig(const UDPSenderConfig& config);
    
private:
    /// Main sender thread function
    void senderThreadFunc();
    
    /// Create and configure the UDP socket
    bool createSocket();
    
    /// Close the socket
    void closeSocket();
    
    /// Build and send one audio packet
    /// @return true if packet was sent successfully
    bool sendPacket();
    
    // Ring buffer reference (owned by device)
    RingBuffer<float>* m_ringBuffer = nullptr;
    
    // Configuration
    UDPSenderConfig m_config;
    
    // Socket
    int m_socket = -1;
    struct sockaddr_in m_destAddr;
    
    // Sender thread
    std::thread m_senderThread;
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_shouldStop{false};
    std::atomic<bool> m_hasDestination{false};
    
    // Packet sequence number
    std::atomic<uint32_t> m_sequence{0};
    
    // Statistics
    std::atomic<uint64_t> m_packetsSent{0};
    std::atomic<uint64_t> m_packetsDropped{0};
    std::atomic<uint64_t> m_framesDropped{0};
    
    // Preallocated packet buffer (no allocation in hot path)
    // Size = 28 byte header + max audio payload
    // For 128 frames stereo float32: 28 + 128*2*4 = 1052 bytes
    // Keep at 1500 to match MTU and allow some headroom
    static constexpr size_t kMaxPacketSize = 1500;
    uint8_t m_packetBuffer[kMaxPacketSize];
};

} // namespace Cymax

#endif /* UDPSender_hpp */

