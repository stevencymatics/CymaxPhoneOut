//
//  CymaxAudioDevice.cpp
//  CymaxPhoneOutDriver
//
//  Virtual audio output device implementation
//

#include "CymaxAudioDevice.hpp"
#include "Logging.hpp"
#include <cstring>

// Define buffer frame size properties if not available in SDK
#ifndef kAudioDevicePropertyBufferFrameSize
#define kAudioDevicePropertyBufferFrameSize 'fsiz'
#endif

#ifndef kAudioDevicePropertyBufferFrameSizeRange
#define kAudioDevicePropertyBufferFrameSizeRange 'fsrn'
#endif

// Object ID assignments (must be unique within the plugin)
// Plugin = 1 (kAudioObjectPlugInObject, but we use a different value)
// Device = 2
// Stream = 3
static constexpr AudioObjectID kOutputStreamObjectID = 3;

namespace Cymax {

AudioDevice::AudioDevice(AudioObjectID deviceID, AudioObjectID pluginID)
    : AudioObject(deviceID)
    , m_pluginID(pluginID)
{
    CYMAX_LOG_INFO("AudioDevice creating: ID=%u", deviceID);
    
    createCFStrings();
    
    // Create output stream
    m_outputStream = std::make_unique<AudioStream>(kOutputStreamObjectID, deviceID, false);
    
    // Create ring buffer (2 channels, Float32)
    m_ringBuffer = std::make_unique<RingBuffer<float>>(kRingBufferFrames, 2);
    
    // Create UDP sender
    m_udpSender = std::make_unique<UDPSender>();
    
    UDPSenderConfig config;
    config.sampleRate = static_cast<uint32_t>(m_sampleRate);
    config.channels = 2;
    config.framesPerPacket = 256;
    config.destPort = 19620;
    config.useFloat32 = true;
    
    m_udpSender->initialize(m_ringBuffer.get(), config);
    
    CYMAX_LOG_INFO("AudioDevice created: %{public}s", kDeviceName);
}

AudioDevice::~AudioDevice() {
    CYMAX_LOG_INFO("AudioDevice destroying: ID=%u", m_objectID);
    
    stopIO();
    
    m_udpSender.reset();
    m_ringBuffer.reset();
    m_outputStream.reset();
    
    releaseCFStrings();
}

void AudioDevice::createCFStrings() {
    m_deviceName = CFStringCreateWithCString(kCFAllocatorDefault, kDeviceName, kCFStringEncodingUTF8);
    m_deviceUID = CFStringCreateWithCString(kCFAllocatorDefault, kDeviceUID, kCFStringEncodingUTF8);
    m_deviceModelUID = CFStringCreateWithCString(kCFAllocatorDefault, kDeviceModelUID, kCFStringEncodingUTF8);
    m_manufacturer = CFStringCreateWithCString(kCFAllocatorDefault, kDeviceManufacturer, kCFStringEncodingUTF8);
}

void AudioDevice::releaseCFStrings() {
    if (m_deviceName) { CFRelease(m_deviceName); m_deviceName = nullptr; }
    if (m_deviceUID) { CFRelease(m_deviceUID); m_deviceUID = nullptr; }
    if (m_deviceModelUID) { CFRelease(m_deviceModelUID); m_deviceModelUID = nullptr; }
    if (m_manufacturer) { CFRelease(m_manufacturer); m_manufacturer = nullptr; }
}

AudioObjectID AudioDevice::getOutputStreamID() const {
    return m_outputStream ? m_outputStream->getObjectID() : kAudioObjectUnknown;
}

void AudioDevice::setSampleRate(Float64 rate) {
    if (rate != 44100.0 && rate != 48000.0) {
        CYMAX_LOG_ERROR("Invalid sample rate: %.0f", rate);
        return;
    }
    
    m_sampleRate = rate;
    if (m_outputStream) {
        m_outputStream->setSampleRate(rate);
    }
    
    // Update UDP sender config
    if (m_udpSender) {
        UDPSenderConfig config;
        config.sampleRate = static_cast<uint32_t>(rate);
        config.channels = 2;
        config.framesPerPacket = 256;
        config.destPort = 19620;
        config.useFloat32 = true;
        m_udpSender->updateConfig(config);
    }
    
    CYMAX_LOG_INFO("Sample rate set to %.0f Hz", rate);
}

void AudioDevice::setBufferFrameSize(UInt32 frames) {
    // Clamp to valid range
    if (frames < 64) frames = 64;
    if (frames > 512) frames = 512;
    
    m_bufferFrameSize = frames;
    CYMAX_LOG_INFO("Buffer frame size set to %u", frames);
}

bool AudioDevice::setDestinationIP(const char* ipAddress) {
    if (!ipAddress) {
        m_destinationIP[0] = '\0';
        if (m_udpSender) {
            m_udpSender->setDestination(nullptr);
        }
        return true;
    }
    
    strncpy(m_destinationIP, ipAddress, sizeof(m_destinationIP) - 1);
    m_destinationIP[sizeof(m_destinationIP) - 1] = '\0';
    
    if (m_udpSender) {
        return m_udpSender->setDestination(ipAddress);
    }
    return false;
}

// Helper to write debug status
static void writeDebugStatus(const char* status) {
    FILE* f = fopen("/tmp/cymax_driver_status.txt", "a");
    if (f) {
        time_t now = time(nullptr);
        fprintf(f, "[%ld] %s\n", now, status);
        fclose(f);
    }
}

OSStatus AudioDevice::startIO() {
    writeDebugStatus("startIO called");
    
    if (m_ioRunning.load(std::memory_order_acquire)) {
        CYMAX_LOG_DEBUG("IO already running");
        writeDebugStatus("IO already running");
        return noErr;
    }
    
    CYMAX_LOG_INFO("Starting IO");
    writeDebugStatus("Starting IO - reading IP file");
    
    // Try to read destination IP from shared file (set by menubar app)
    // Using /tmp which is accessible to coreaudiod
    const char* homePaths[] = {
        "/tmp/cymax_dest_ip.txt",
        nullptr
    };
    
    bool foundIP = false;
    for (int i = 0; homePaths[i] != nullptr && !foundIP; i++) {
        FILE* file = fopen(homePaths[i], "r");
        if (file) {
            char ipBuffer[64] = {0};
            if (fgets(ipBuffer, sizeof(ipBuffer), file)) {
                // Remove trailing newline if present
                size_t len = strlen(ipBuffer);
                if (len > 0 && ipBuffer[len-1] == '\n') {
                    ipBuffer[len-1] = '\0';
                }
                if (strlen(ipBuffer) > 0) {
                    CYMAX_LOG_INFO("Read destination IP from %{public}s: %{public}s", homePaths[i], ipBuffer);
                    char msg[128];
                    snprintf(msg, sizeof(msg), "Found IP: %s", ipBuffer);
                    writeDebugStatus(msg);
                    setDestinationIP(ipBuffer);
                    foundIP = true;
                }
            }
            fclose(file);
        }
    }
    
    if (!foundIP) {
        CYMAX_LOG_INFO("No destination IP file found");
        writeDebugStatus("No IP file found!");
    }
    
    // Reset ring buffer
    if (m_ringBuffer) {
        m_ringBuffer->reset();
    }
    
    // Start UDP sender
    if (m_udpSender) {
        if (!m_udpSender->start()) {
            CYMAX_LOG_ERROR("Failed to start UDP sender");
            // Continue anyway - we can still capture audio even if network isn't ready
        }
    }
    
    m_ioRunning.store(true, std::memory_order_release);
    return noErr;
}

void AudioDevice::stopIO() {
    if (!m_ioRunning.load(std::memory_order_acquire)) {
        return;
    }
    
    CYMAX_LOG_INFO("Stopping IO");
    
    m_ioRunning.store(false, std::memory_order_release);
    
    // Stop UDP sender
    if (m_udpSender) {
        m_udpSender->stop();
    }
}

OSStatus AudioDevice::doIOOperation(UInt32 inIOBufferFrameSize,
                                    const AudioServerPlugInIOCycleInfo* inIOCycleInfo,
                                    UInt32 inOperationID,
                                    UInt32 inIOBufferFrameSize2,
                                    void* ioMainBuffer,
                                    void* ioSecondaryBuffer) {
    // CRITICAL: This is the real-time render callback
    // DO NOT: allocate, lock, log (unless CYMAX_LOG_RENDER is enabled), make syscalls
    
    // We only handle the WriteMix operation (output)
    if (inOperationID != kAudioServerPlugInIOOperationWriteMix) {
        return noErr;
    }
    
    // ioMainBuffer contains interleaved Float32 stereo samples
    // Write directly to ring buffer
    if (m_ringBuffer && ioMainBuffer) {
        const float* audioData = static_cast<const float*>(ioMainBuffer);
        m_ringBuffer->write(audioData, inIOBufferFrameSize);
    }
    
    // CYMAX_LOG_RENDER is disabled by default, this is a no-op:
    CYMAX_LOG_RENDER("doIO: %u frames", inIOBufferFrameSize);
    
    return noErr;
}

// Property implementations

Boolean AudioDevice::hasProperty(const AudioObjectPropertyAddress* address) const {
    switch (address->mSelector) {
        // Object properties
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertySerialNumber:
        case kAudioObjectPropertyFirmwareVersion:
        case kAudioObjectPropertyIdentify:
        
        // Device properties
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertyStreams:
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyPreferredChannelsForStereo:
        case kAudioDevicePropertyPreferredChannelLayout:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyIcon:
        
        // Buffer frame size
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyBufferFrameSizeRange:
        
        // Custom property
        case kDestinationIPProperty:
            return true;
        
        default:
            return false;
    }
}

OSStatus AudioDevice::isPropertySettable(const AudioObjectPropertyAddress* address,
                                         Boolean* outIsSettable) const {
    switch (address->mSelector) {
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyBufferFrameSize:
        case kDestinationIPProperty:
            *outIsSettable = true;
            return noErr;
        
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertyStreams:
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyPreferredChannelsForStereo:
        case kAudioDevicePropertyPreferredChannelLayout:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyBufferFrameSizeRange:
            *outIsSettable = false;
            return noErr;
        
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

OSStatus AudioDevice::getPropertyDataSize(const AudioObjectPropertyAddress* address,
                                          UInt32 qualifierDataSize,
                                          const void* qualifierData,
                                          UInt32* outDataSize) const {
    switch (address->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioObjectPropertyIdentify:
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioObjectPropertyOwnedObjects:
            // One output stream
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        
        case kAudioDevicePropertyStreams:
            // Output only
            if (address->mScope == kAudioObjectPropertyScopeOutput ||
                address->mScope == kAudioObjectPropertyScopeGlobal) {
                *outDataSize = sizeof(AudioObjectID);
            } else {
                *outDataSize = 0;
            }
            return noErr;
        
        case kAudioDevicePropertyRelatedDevices:
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        
        case kAudioObjectPropertyControlList:
            *outDataSize = 0;  // No controls
            return noErr;
        
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioObjectPropertySerialNumber:
        case kAudioObjectPropertyFirmwareVersion:
            *outDataSize = sizeof(CFStringRef);
            return noErr;
        
        case kAudioDevicePropertyNominalSampleRate:
            *outDataSize = sizeof(Float64);
            return noErr;
        
        case kAudioDevicePropertyAvailableNominalSampleRates:
            // Two sample rates: 44.1kHz and 48kHz
            *outDataSize = 2 * sizeof(AudioValueRange);
            return noErr;
        
        case kAudioDevicePropertyPreferredChannelsForStereo:
            *outDataSize = 2 * sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyPreferredChannelLayout:
            *outDataSize = offsetof(AudioChannelLayout, mChannelDescriptions) + 
                          2 * sizeof(AudioChannelDescription);
            return noErr;
        
        case kAudioDevicePropertyBufferFrameSizeRange:
            *outDataSize = sizeof(AudioValueRange);
            return noErr;
        
        case kAudioDevicePropertyIcon:
            *outDataSize = sizeof(CFURLRef);
            return noErr;
        
        case kDestinationIPProperty:
            *outDataSize = sizeof(m_destinationIP);
            return noErr;
        
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

OSStatus AudioDevice::getPropertyData(const AudioObjectPropertyAddress* address,
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
            *static_cast<AudioClassID*>(outData) = kAudioDeviceClassID;
            *outDataSize = sizeof(AudioClassID);
            return noErr;
        
        case kAudioObjectPropertyOwner:
            if (inDataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = m_pluginID;
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        
        case kAudioObjectPropertyOwnedObjects:
            if (inDataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = getOutputStreamID();
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        
        case kAudioObjectPropertyName:
            if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
            *static_cast<CFStringRef*>(outData) = m_deviceName;
            if (m_deviceName) CFRetain(m_deviceName);
            *outDataSize = sizeof(CFStringRef);
            return noErr;
        
        case kAudioObjectPropertyManufacturer:
            if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
            *static_cast<CFStringRef*>(outData) = m_manufacturer;
            if (m_manufacturer) CFRetain(m_manufacturer);
            *outDataSize = sizeof(CFStringRef);
            return noErr;
        
        case kAudioObjectPropertySerialNumber:
        case kAudioObjectPropertyFirmwareVersion:
            if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
            *static_cast<CFStringRef*>(outData) = CFSTR("1.0");
            *outDataSize = sizeof(CFStringRef);
            return noErr;
        
        case kAudioObjectPropertyIdentify:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = 0;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyDeviceUID:
            if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
            *static_cast<CFStringRef*>(outData) = m_deviceUID;
            if (m_deviceUID) CFRetain(m_deviceUID);
            *outDataSize = sizeof(CFStringRef);
            return noErr;
        
        case kAudioDevicePropertyModelUID:
            if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
            *static_cast<CFStringRef*>(outData) = m_deviceModelUID;
            if (m_deviceModelUID) CFRetain(m_deviceModelUID);
            *outDataSize = sizeof(CFStringRef);
            return noErr;
        
        case kAudioDevicePropertyTransportType:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = kAudioDeviceTransportTypeVirtual;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyRelatedDevices:
            if (inDataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = m_objectID;  // Only related to itself
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        
        case kAudioDevicePropertyClockDomain:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = 0;  // Clock domain 0
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyDeviceIsAlive:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = 1;  // Always alive
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyDeviceIsRunning:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = m_ioRunning.load(std::memory_order_acquire) ? 1 : 0;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            // Yes, we can be the default output device
            *static_cast<UInt32*>(outData) = (address->mScope == kAudioObjectPropertyScopeOutput ||
                                              address->mScope == kAudioObjectPropertyScopeGlobal) ? 1 : 0;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyLatency:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            // Report latency in frames (buffer size + network estimate)
            // For MVP, we report just the buffer size
            *static_cast<UInt32*>(outData) = m_bufferFrameSize;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyStreams:
            if (address->mScope == kAudioObjectPropertyScopeOutput ||
                address->mScope == kAudioObjectPropertyScopeGlobal) {
                if (inDataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
                *static_cast<AudioObjectID*>(outData) = getOutputStreamID();
                *outDataSize = sizeof(AudioObjectID);
            } else {
                *outDataSize = 0;  // No input streams
            }
            return noErr;
        
        case kAudioObjectPropertyControlList:
            *outDataSize = 0;
            return noErr;
        
        case kAudioDevicePropertySafetyOffset:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = 0;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyNominalSampleRate:
            if (inDataSize < sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
            *static_cast<Float64*>(outData) = m_sampleRate;
            *outDataSize = sizeof(Float64);
            return noErr;
        
        case kAudioDevicePropertyAvailableNominalSampleRates: {
            if (inDataSize < 2 * sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
            AudioValueRange* ranges = static_cast<AudioValueRange*>(outData);
            ranges[0].mMinimum = 44100.0;
            ranges[0].mMaximum = 44100.0;
            ranges[1].mMinimum = 48000.0;
            ranges[1].mMaximum = 48000.0;
            *outDataSize = 2 * sizeof(AudioValueRange);
            return noErr;
        }
        
        case kAudioDevicePropertyIsHidden:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = 0;  // Not hidden
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyPreferredChannelsForStereo:
            if (inDataSize < 2 * sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            static_cast<UInt32*>(outData)[0] = 1;  // Left
            static_cast<UInt32*>(outData)[1] = 2;  // Right
            *outDataSize = 2 * sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyPreferredChannelLayout: {
            size_t layoutSize = offsetof(AudioChannelLayout, mChannelDescriptions) + 
                               2 * sizeof(AudioChannelDescription);
            if (inDataSize < layoutSize) return kAudioHardwareBadPropertySizeError;
            
            AudioChannelLayout* layout = static_cast<AudioChannelLayout*>(outData);
            layout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
            layout->mChannelBitmap = 0;
            layout->mNumberChannelDescriptions = 2;
            
            layout->mChannelDescriptions[0].mChannelLabel = kAudioChannelLabel_Left;
            layout->mChannelDescriptions[0].mChannelFlags = 0;
            layout->mChannelDescriptions[0].mCoordinates[0] = 0;
            layout->mChannelDescriptions[0].mCoordinates[1] = 0;
            layout->mChannelDescriptions[0].mCoordinates[2] = 0;
            
            layout->mChannelDescriptions[1].mChannelLabel = kAudioChannelLabel_Right;
            layout->mChannelDescriptions[1].mChannelFlags = 0;
            layout->mChannelDescriptions[1].mCoordinates[0] = 0;
            layout->mChannelDescriptions[1].mCoordinates[1] = 0;
            layout->mChannelDescriptions[1].mCoordinates[2] = 0;
            
            *outDataSize = static_cast<UInt32>(layoutSize);
            return noErr;
        }
        
        case kAudioDevicePropertyZeroTimeStampPeriod:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            // Number of frames between zero timestamps
            *static_cast<UInt32*>(outData) = static_cast<UInt32>(m_sampleRate);  // 1 second
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyBufferFrameSize:
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            *static_cast<UInt32*>(outData) = m_bufferFrameSize;
            *outDataSize = sizeof(UInt32);
            return noErr;
        
        case kAudioDevicePropertyBufferFrameSizeRange: {
            if (inDataSize < sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
            AudioValueRange* range = static_cast<AudioValueRange*>(outData);
            range->mMinimum = 64;
            range->mMaximum = 512;
            *outDataSize = sizeof(AudioValueRange);
            return noErr;
        }
        
        case kAudioDevicePropertyIcon:
            // Return null for no custom icon
            *static_cast<CFURLRef*>(outData) = nullptr;
            *outDataSize = sizeof(CFURLRef);
            return noErr;
        
        case kDestinationIPProperty:
            if (inDataSize < sizeof(m_destinationIP)) return kAudioHardwareBadPropertySizeError;
            memcpy(outData, m_destinationIP, sizeof(m_destinationIP));
            *outDataSize = sizeof(m_destinationIP);
            return noErr;
        
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

OSStatus AudioDevice::setPropertyData(const AudioObjectPropertyAddress* address,
                                      UInt32 qualifierDataSize,
                                      const void* qualifierData,
                                      UInt32 inDataSize,
                                      const void* inData) {
    switch (address->mSelector) {
        case kAudioDevicePropertyNominalSampleRate: {
            if (inDataSize < sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
            Float64 rate = *static_cast<const Float64*>(inData);
            if (rate != 44100.0 && rate != 48000.0) {
                return kAudioHardwareIllegalOperationError;
            }
            // Note: const_cast is needed because we're in a const-ish context
            const_cast<AudioDevice*>(this)->setSampleRate(rate);
            return noErr;
        }
        
        case kAudioDevicePropertyBufferFrameSize: {
            if (inDataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            UInt32 frames = *static_cast<const UInt32*>(inData);
            const_cast<AudioDevice*>(this)->setBufferFrameSize(frames);
            return noErr;
        }
        
        case kDestinationIPProperty: {
            if (inDataSize > sizeof(m_destinationIP)) return kAudioHardwareBadPropertySizeError;
            const_cast<AudioDevice*>(this)->setDestinationIP(static_cast<const char*>(inData));
            return noErr;
        }
        
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

} // namespace Cymax

