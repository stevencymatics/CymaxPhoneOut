//
//  CymaxAudioDevice.hpp
//  CymaxPhoneOutDriver
//
//  Virtual audio output device "Cymax Phone Out (MVP)"
//

#ifndef CymaxAudioDevice_hpp
#define CymaxAudioDevice_hpp

#include "CymaxAudioObject.hpp"
#include "CymaxAudioStream.hpp"
#include "RingBuffer.hpp"
#include "UDPSender.hpp"
#include <CoreAudio/AudioServerPlugIn.h>
#include <memory>
#include <atomic>

namespace Cymax {

/// Virtual audio output device
class AudioDevice : public AudioObject {
public:
    AudioDevice(AudioObjectID deviceID, AudioObjectID pluginID);
    virtual ~AudioDevice();
    
    // AudioObject overrides
    Boolean hasProperty(const AudioObjectPropertyAddress* address) const override;
    OSStatus isPropertySettable(const AudioObjectPropertyAddress* address,
                               Boolean* outIsSettable) const override;
    OSStatus getPropertyDataSize(const AudioObjectPropertyAddress* address,
                                UInt32 qualifierDataSize,
                                const void* qualifierData,
                                UInt32* outDataSize) const override;
    OSStatus getPropertyData(const AudioObjectPropertyAddress* address,
                            UInt32 qualifierDataSize,
                            const void* qualifierData,
                            UInt32 inDataSize,
                            UInt32* outDataSize,
                            void* outData) const override;
    OSStatus setPropertyData(const AudioObjectPropertyAddress* address,
                            UInt32 qualifierDataSize,
                            const void* qualifierData,
                            UInt32 inDataSize,
                            const void* inData) override;
    
    // Device lifecycle
    OSStatus startIO();
    void stopIO();
    bool isIORunning() const { return m_ioRunning.load(std::memory_order_acquire); }
    
    /// Process audio in the render callback
    /// CRITICAL: This is called from the real-time audio thread
    /// It MUST NOT allocate, lock, log, or make system calls
    OSStatus doIOOperation(UInt32 inIOBufferFrameSize,
                          const AudioServerPlugInIOCycleInfo* inIOCycleInfo,
                          UInt32 inOperationID,
                          UInt32 inIOBufferFrameSize2,
                          void* ioMainBuffer,
                          void* ioSecondaryBuffer);
    
    // Stream access
    AudioStream* getOutputStream() { return m_outputStream.get(); }
    const AudioStream* getOutputStream() const { return m_outputStream.get(); }
    AudioObjectID getOutputStreamID() const;
    
    // Configuration
    Float64 getSampleRate() const { return m_sampleRate; }
    UInt32 getBufferFrameSize() const { return m_bufferFrameSize; }
    void setSampleRate(Float64 rate);
    void setBufferFrameSize(UInt32 frames);
    
    // Custom properties for menubar app communication
    // Property selector for destination IP address (custom property)
    static constexpr AudioObjectPropertySelector kDestinationIPProperty = 'DstI';
    
    /// Set the UDP destination IP address
    bool setDestinationIP(const char* ipAddress);
    
    // Device constants
    static constexpr UInt32 kDefaultBufferFrameSize = 256;
    static constexpr Float64 kDefaultSampleRate = 48000.0;
    static constexpr UInt32 kRingBufferFrames = 48000;  // 1 second at 48kHz for DAW compatibility
    
    // Device name
    static constexpr const char* kDeviceName = "Cymax Phone Out (MVP)";
    static constexpr const char* kDeviceManufacturer = "Cymax";
    static constexpr const char* kDeviceUID = "CymaxPhoneOutMVP";
    static constexpr const char* kDeviceModelUID = "CymaxPhoneOutMVP_Model";
    
private:
    AudioObjectID m_pluginID;
    
    // Stream
    std::unique_ptr<AudioStream> m_outputStream;
    
    // Audio processing
    std::unique_ptr<RingBuffer<float>> m_ringBuffer;
    std::unique_ptr<UDPSender> m_udpSender;
    
    // State
    std::atomic<bool> m_ioRunning{false};
    Float64 m_sampleRate = kDefaultSampleRate;
    UInt32 m_bufferFrameSize = kDefaultBufferFrameSize;
    
    // CFString properties (cached for lifetime)
    CFStringRef m_deviceName = nullptr;
    CFStringRef m_deviceUID = nullptr;
    CFStringRef m_deviceModelUID = nullptr;
    CFStringRef m_manufacturer = nullptr;
    
    // Destination IP storage
    char m_destinationIP[64] = {0};
    
    void createCFStrings();
    void releaseCFStrings();
};

} // namespace Cymax

#endif /* CymaxAudioDevice_hpp */

