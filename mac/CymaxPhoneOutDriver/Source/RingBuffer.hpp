//
//  RingBuffer.hpp
//  CymaxPhoneOutDriver
//
//  Lock-free Single-Producer Single-Consumer (SPSC) ring buffer
//
//  CRITICAL SAFETY GUARANTEES:
//  - No memory allocation after construction
//  - No locks, mutexes, or blocking operations
//  - No system calls in the hot path
//  - Safe for real-time audio render callback
//
//  OVERWRITE POLICY (per requirements):
//  - If the sender thread falls behind, OLDEST frames are dropped
//  - The reader (sender) advances its read index to keep up
//  - The writer (render callback) NEVER blocks
//

#ifndef RingBuffer_hpp
#define RingBuffer_hpp

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <algorithm>

namespace Cymax {

/// Lock-free SPSC ring buffer for audio frames
/// Template parameter T should be the sample type (float or int16_t)
template<typename T>
class RingBuffer {
public:
    /// Construct a ring buffer with the given capacity
    /// @param frameCapacity Number of frames (not samples) the buffer can hold
    /// @param channelCount Number of interleaved channels per frame
    /// @note Capacity will be rounded up to the nearest power of 2
    RingBuffer(size_t frameCapacity, size_t channelCount)
        : m_channelCount(channelCount)
        , m_writeIndex(0)
        , m_readIndex(0)
    {
        // Round up to power of 2 for efficient modulo via bitwise AND
        m_frameCapacity = nextPowerOf2(frameCapacity);
        m_mask = m_frameCapacity - 1;
        
        // Allocate sample buffer
        m_sampleCapacity = m_frameCapacity * m_channelCount;
        m_buffer = static_cast<T*>(std::aligned_alloc(64, m_sampleCapacity * sizeof(T)));
        
        // Zero-initialize
        std::memset(m_buffer, 0, m_sampleCapacity * sizeof(T));
    }
    
    ~RingBuffer() {
        std::free(m_buffer);
    }
    
    // Non-copyable, non-movable
    RingBuffer(const RingBuffer&) = delete;
    RingBuffer& operator=(const RingBuffer&) = delete;
    RingBuffer(RingBuffer&&) = delete;
    RingBuffer& operator=(RingBuffer&&) = delete;
    
    /// Write frames to the buffer (called from render callback)
    /// @param frames Pointer to interleaved audio frames
    /// @param frameCount Number of frames to write
    /// @return Number of frames actually written
    /// @note This will OVERWRITE old data if buffer is full
    ///       The render callback NEVER blocks
    size_t write(const T* frames, size_t frameCount) {
        // This method is called from the real-time render thread
        // It must not allocate, lock, or make system calls
        
        const size_t writeIdx = m_writeIndex.load(std::memory_order_relaxed);
        
        // Calculate how many frames we can write
        // If we would overwrite unread data, we still write (dropping old frames)
        const size_t samplesToWrite = frameCount * m_channelCount;
        
        // Write the samples with wrap-around
        for (size_t i = 0; i < samplesToWrite; ++i) {
            const size_t bufferIdx = ((writeIdx * m_channelCount) + i) & (m_sampleCapacity - 1);
            m_buffer[bufferIdx] = frames[i];
        }
        
        // Update write index (with wrap using mask)
        const size_t newWriteIdx = (writeIdx + frameCount) & m_mask;
        m_writeIndex.store(newWriteIdx, std::memory_order_release);
        
        return frameCount;
    }
    
    /// Read frames from the buffer (called from sender thread)
    /// @param frames Output buffer for interleaved audio frames
    /// @param frameCount Maximum number of frames to read
    /// @return Number of frames actually read
    size_t read(T* frames, size_t frameCount) {
        const size_t writeIdx = m_writeIndex.load(std::memory_order_acquire);
        const size_t readIdx = m_readIndex.load(std::memory_order_relaxed);
        
        // Calculate available frames
        const size_t available = (writeIdx - readIdx) & m_mask;
        const size_t toRead = std::min(frameCount, available);
        
        if (toRead == 0) {
            return 0;
        }
        
        // Read the samples with wrap-around
        const size_t samplesToRead = toRead * m_channelCount;
        for (size_t i = 0; i < samplesToRead; ++i) {
            const size_t bufferIdx = ((readIdx * m_channelCount) + i) & (m_sampleCapacity - 1);
            frames[i] = m_buffer[bufferIdx];
        }
        
        // Update read index
        const size_t newReadIdx = (readIdx + toRead) & m_mask;
        m_readIndex.store(newReadIdx, std::memory_order_release);
        
        return toRead;
    }
    
    /// Get number of frames available for reading
    size_t availableForRead() const {
        const size_t writeIdx = m_writeIndex.load(std::memory_order_acquire);
        const size_t readIdx = m_readIndex.load(std::memory_order_relaxed);
        const size_t available = (writeIdx - readIdx) & m_mask;
        
        // Update high water mark (relaxed is fine, this is just stats)
        size_t current = m_highWaterMark.load(std::memory_order_relaxed);
        while (available > current) {
            if (m_highWaterMark.compare_exchange_weak(current, available, 
                    std::memory_order_relaxed, std::memory_order_relaxed)) {
                break;
            }
        }
        
        return available;
    }
    
    /// Get number of frames available for writing (before overwrite)
    size_t availableForWrite() const {
        return m_frameCapacity - availableForRead() - 1;
    }
    
    /// Check if buffer is empty
    bool isEmpty() const {
        return availableForRead() == 0;
    }
    
    /// Get total frame capacity
    size_t capacity() const {
        return m_frameCapacity;
    }
    
    /// Get channel count
    size_t channelCount() const {
        return m_channelCount;
    }
    
    /// Get the high water mark (peak buffer fill level in frames)
    size_t highWaterMark() const {
        return m_highWaterMark.load(std::memory_order_relaxed);
    }
    
    /// Reset high water mark (call periodically to get peak over time window)
    void resetHighWaterMark() {
        m_highWaterMark.store(0, std::memory_order_relaxed);
    }
    
    /// Reset the buffer (called when stopping IO)
    /// @warning Only call when no read/write operations are in progress
    void reset() {
        m_writeIndex.store(0, std::memory_order_relaxed);
        m_readIndex.store(0, std::memory_order_relaxed);
        m_highWaterMark.store(0, std::memory_order_relaxed);
        std::memset(m_buffer, 0, m_sampleCapacity * sizeof(T));
    }
    
    /// Advance read index, dropping frames
    /// Used when sender falls behind
    /// @param frameCount Number of frames to drop
    void dropFrames(size_t frameCount) {
        const size_t readIdx = m_readIndex.load(std::memory_order_relaxed);
        const size_t newReadIdx = (readIdx + frameCount) & m_mask;
        m_readIndex.store(newReadIdx, std::memory_order_release);
    }
    
private:
    /// Round up to next power of 2
    static size_t nextPowerOf2(size_t v) {
        v--;
        v |= v >> 1;
        v |= v >> 2;
        v |= v >> 4;
        v |= v >> 8;
        v |= v >> 16;
        v |= v >> 32;
        v++;
        return v;
    }
    
    T* m_buffer;
    size_t m_frameCapacity;     // Number of frames (power of 2)
    size_t m_sampleCapacity;    // Number of samples (frames * channels)
    size_t m_channelCount;
    size_t m_mask;              // For efficient modulo: index & mask
    
    // Atomic indices on separate cache lines to avoid false sharing
    alignas(64) std::atomic<size_t> m_writeIndex;
    alignas(64) std::atomic<size_t> m_readIndex;
    
    // Statistics
    mutable std::atomic<size_t> m_highWaterMark{0};
};

} // namespace Cymax

#endif /* RingBuffer_hpp */

