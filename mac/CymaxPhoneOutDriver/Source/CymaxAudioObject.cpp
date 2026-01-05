//
//  CymaxAudioObject.cpp
//  CymaxPhoneOutDriver
//
//  Base class implementation
//

#include "CymaxAudioObject.hpp"
#include "Logging.hpp"

namespace Cymax {

AudioObject::AudioObject(AudioObjectID objectID)
    : m_objectID(objectID)
{
}

Boolean AudioObject::hasProperty(const AudioObjectPropertyAddress* address) const {
    // Base class has no properties
    return false;
}

OSStatus AudioObject::isPropertySettable(const AudioObjectPropertyAddress* address,
                                         Boolean* outIsSettable) const {
    *outIsSettable = false;
    return kAudioHardwareUnknownPropertyError;
}

OSStatus AudioObject::getPropertyDataSize(const AudioObjectPropertyAddress* address,
                                          UInt32 qualifierDataSize,
                                          const void* qualifierData,
                                          UInt32* outDataSize) const {
    *outDataSize = 0;
    return kAudioHardwareUnknownPropertyError;
}

OSStatus AudioObject::getPropertyData(const AudioObjectPropertyAddress* address,
                                      UInt32 qualifierDataSize,
                                      const void* qualifierData,
                                      UInt32 inDataSize,
                                      UInt32* outDataSize,
                                      void* outData) const {
    *outDataSize = 0;
    return kAudioHardwareUnknownPropertyError;
}

OSStatus AudioObject::setPropertyData(const AudioObjectPropertyAddress* address,
                                      UInt32 qualifierDataSize,
                                      const void* qualifierData,
                                      UInt32 inDataSize,
                                      const void* inData) {
    return kAudioHardwareUnknownPropertyError;
}

} // namespace Cymax


