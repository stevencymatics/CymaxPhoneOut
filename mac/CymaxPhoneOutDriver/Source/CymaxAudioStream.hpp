//
//  CymaxAudioStream.hpp
//  CymaxPhoneOutDriver
//
//  Audio stream object representing the stereo output stream
//

#ifndef CymaxAudioStream_hpp
#define CymaxAudioStream_hpp

#include "CymaxAudioObject.hpp"
#include <CoreAudio/AudioServerPlugIn.h>

namespace Cymax {

// Forward declaration
class AudioDevice;

/// Audio stream object representing a stereo output stream
class AudioStream : public AudioObject {
public:
    AudioStream(AudioObjectID streamID, AudioObjectID owningDeviceID, bool isInput);
    virtual ~AudioStream() = default;
    
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
    
    // Stream-specific methods
    bool isInput() const { return m_isInput; }
    bool isActive() const { return m_isActive; }
    void setActive(bool active) { m_isActive = active; }
    
    UInt32 getChannelCount() const { return kChannelCount; }
    Float64 getSampleRate() const { return m_sampleRate; }
    void setSampleRate(Float64 rate) { m_sampleRate = rate; }
    
    /// Get the physical format description
    AudioStreamBasicDescription getPhysicalFormat() const;
    
    /// Get the virtual format description
    AudioStreamBasicDescription getVirtualFormat() const;
    
    // Constants
    static constexpr UInt32 kChannelCount = 2;  // Stereo
    
private:
    AudioObjectID m_owningDeviceID;
    bool m_isInput;
    bool m_isActive = false;
    Float64 m_sampleRate = 48000.0;
};

} // namespace Cymax

#endif /* CymaxAudioStream_hpp */



