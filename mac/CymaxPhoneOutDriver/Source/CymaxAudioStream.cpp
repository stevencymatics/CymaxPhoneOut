//
//  CymaxAudioStream.cpp
//  CymaxPhoneOutDriver
//
//  Audio stream implementation
//

#include "CymaxAudioStream.hpp"
#include "Logging.hpp"

namespace Cymax {

AudioStream::AudioStream(AudioObjectID streamID, AudioObjectID owningDeviceID, bool isInput)
    : AudioObject(streamID)
    , m_owningDeviceID(owningDeviceID)
    , m_isInput(isInput)
{
    CYMAX_LOG_DEBUG("AudioStream created: ID=%u, device=%u, isInput=%d",
                   streamID, owningDeviceID, isInput);
}

AudioStreamBasicDescription AudioStream::getPhysicalFormat() const {
    AudioStreamBasicDescription format = {};
    format.mSampleRate = m_sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = kChannelCount * sizeof(Float32);
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = kChannelCount * sizeof(Float32);
    format.mChannelsPerFrame = kChannelCount;
    format.mBitsPerChannel = 32;
    return format;
}

AudioStreamBasicDescription AudioStream::getVirtualFormat() const {
    // Virtual format matches physical format for this simple device
    return getPhysicalFormat();
}

Boolean AudioStream::hasProperty(const AudioObjectPropertyAddress* address) const {
    switch (address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            return true;
        default:
            return false;
    }
}

OSStatus AudioStream::isPropertySettable(const AudioObjectPropertyAddress* address,
                                         Boolean* outIsSettable) const {
    switch (address->mSelector) {
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            *outIsSettable = true;
            return noErr;
        
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            *outIsSettable = false;
            return noErr;
        
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

OSStatus AudioStream::getPropertyDataSize(const AudioObjectPropertyAddress* address,
                                          UInt32 qualifierDataSize,
                                          const void* qualifierData,
                                          UInt32* outDataSize) const {
    switch (address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioStreamPropertyIsActive:
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioObjectPropertyOwnedObjects:
            *outDataSize = 0;  // Stream owns nothing
            return noErr;
        
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            *outDataSize = sizeof(AudioStreamBasicDescription);
            return noErr;
        
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            // Two formats: 48kHz and 44.1kHz
            *outDataSize = 2 * sizeof(AudioStreamRangedDescription);
            return noErr;
        
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

OSStatus AudioStream::getPropertyData(const AudioObjectPropertyAddress* address,
                                      UInt32 qualifierDataSize,
                                      const void* qualifierData,
                                      UInt32 inDataSize,
                                      UInt32* outDataSize,
                                      void* outData) const {
    switch (address->mSelector) {
        case kAudioObjectPropertyBaseClass:
            if (inDataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioClassID*>(outData) = kAudioObjectClassID;
            *outDataSize = sizeof(AudioClassID);
            return noErr;
        
        case kAudioObjectPropertyClass:
            if (inDataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioClassID*>(outData) = kAudioStreamClassID;
            *outDataSize = sizeof(AudioClassID);
            return noErr;
        
        case kAudioObjectPropertyOwner:
            if (inDataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = m_owningDeviceID;
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        
        case kAudioObjectPropertyOwnedObjects:
            *outDataSize = 0;
            return noErr;
        
        case kAudioStreamPropertyIsActive:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = m_isActive ? 1 : 0;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioStreamPropertyDirection:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            // 0 = output, 1 = input
            *static_cast<UInt32*>(outData) = m_isInput ? 1 : 0;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioStreamPropertyTerminalType:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = kAudioStreamTerminalTypeLine;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioStreamPropertyStartingChannel:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = 1;  // 1-based channel numbering
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioStreamPropertyLatency:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = 0;  // Additional stream latency in frames
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioStreamPropertyVirtualFormat:
            if (inDataSize < sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioStreamBasicDescription*>(outData) = getVirtualFormat();
            *outDataSize = sizeof(AudioStreamBasicDescription);
            return noErr;
        
        case kAudioStreamPropertyPhysicalFormat:
            if (inDataSize < sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioStreamBasicDescription*>(outData) = getPhysicalFormat();
            *outDataSize = sizeof(AudioStreamBasicDescription);
            return noErr;
        
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: {
            // Only 48kHz supported - iOS hardware requires it
            if (inDataSize < sizeof(AudioStreamRangedDescription)) {
                return kAudioHardwareBadPropertySizeError;
            }
            
            AudioStreamRangedDescription* formats = static_cast<AudioStreamRangedDescription*>(outData);
            
            // 48kHz format only
            formats[0].mFormat = getPhysicalFormat();
            formats[0].mFormat.mSampleRate = 48000.0;
            formats[0].mSampleRateRange.mMinimum = 48000.0;
            formats[0].mSampleRateRange.mMaximum = 48000.0;
            
            *outDataSize = sizeof(AudioStreamRangedDescription);
            return noErr;
        }
        
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

OSStatus AudioStream::setPropertyData(const AudioObjectPropertyAddress* address,
                                      UInt32 qualifierDataSize,
                                      const void* qualifierData,
                                      UInt32 inDataSize,
                                      const void* inData) {
    switch (address->mSelector) {
        case kAudioStreamPropertyIsActive:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            m_isActive = *static_cast<const UInt32*>(inData) != 0;
            CYMAX_LOG_DEBUG("Stream %u active: %d", m_objectID, m_isActive);
            return noErr;
        
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: {
            if (inDataSize < sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
            const AudioStreamBasicDescription* format = static_cast<const AudioStreamBasicDescription*>(inData);
            
            // Only 48000Hz supported - iOS hardware requires it
            if (format->mSampleRate != 48000.0) {
                CYMAX_LOG_INFO("Ignoring sample rate %.0f, keeping 48000Hz", format->mSampleRate);
                // Don't return error, just silently keep 48000Hz
            } else {
                m_sampleRate = format->mSampleRate;
            }
            CYMAX_LOG_INFO("Stream %u format set: %.0f Hz", m_objectID, m_sampleRate);
            return noErr;
        }
        
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

} // namespace Cymax

