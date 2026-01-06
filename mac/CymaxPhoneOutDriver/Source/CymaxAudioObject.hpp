//
//  CymaxAudioObject.hpp
//  CymaxPhoneOutDriver
//
//  Base class for audio objects (Plugin, Device, Stream)
//

#ifndef CymaxAudioObject_hpp
#define CymaxAudioObject_hpp

#include <CoreAudio/AudioServerPlugIn.h>
#include <vector>
#include <mutex>

namespace Cymax {

/// Base class for all audio objects in the plugin
class AudioObject {
public:
    explicit AudioObject(AudioObjectID objectID);
    virtual ~AudioObject() = default;
    
    // Non-copyable
    AudioObject(const AudioObject&) = delete;
    AudioObject& operator=(const AudioObject&) = delete;
    
    /// Get this object's ID
    AudioObjectID getObjectID() const { return m_objectID; }
    
    /// Check if this object has a property
    virtual Boolean hasProperty(const AudioObjectPropertyAddress* address) const;
    
    /// Check if a property is settable
    virtual OSStatus isPropertySettable(const AudioObjectPropertyAddress* address,
                                        Boolean* outIsSettable) const;
    
    /// Get the size of a property's data
    virtual OSStatus getPropertyDataSize(const AudioObjectPropertyAddress* address,
                                         UInt32 qualifierDataSize,
                                         const void* qualifierData,
                                         UInt32* outDataSize) const;
    
    /// Get a property's data
    virtual OSStatus getPropertyData(const AudioObjectPropertyAddress* address,
                                     UInt32 qualifierDataSize,
                                     const void* qualifierData,
                                     UInt32 inDataSize,
                                     UInt32* outDataSize,
                                     void* outData) const;
    
    /// Set a property's data
    virtual OSStatus setPropertyData(const AudioObjectPropertyAddress* address,
                                     UInt32 qualifierDataSize,
                                     const void* qualifierData,
                                     UInt32 inDataSize,
                                     const void* inData);
    
protected:
    AudioObjectID m_objectID;
};

} // namespace Cymax

#endif /* CymaxAudioObject_hpp */



