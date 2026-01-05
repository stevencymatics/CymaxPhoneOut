//
//  PluginEntry.cpp
//  CymaxPhoneOutDriver
//
//  AudioServerPlugIn entry point and interface implementation
//
//  This is the main entry point that CoreAudio uses to communicate with
//  the virtual audio device. It implements the AudioServerPlugIn interface.
//

#include "CymaxPluginInterface.hpp"
#include "CymaxAudioDevice.hpp"
#include "CymaxAudioStream.hpp"
#include "Logging.hpp"

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <mutex>
#include <memory>

// Object ID assignments
static constexpr AudioObjectID kPluginObjectID = kAudioObjectPlugInObject;  // Usually 1
static constexpr AudioObjectID kDeviceObjectID = 2;
static constexpr AudioObjectID kOutputStreamObjectID = 3;

// Plugin state
static std::unique_ptr<Cymax::AudioDevice> gDevice;
static std::mutex gPluginMutex;
static AudioServerPlugInHostRef gHost = nullptr;
static UInt32 gRefCount = 0;

// Forward declarations of plugin interface methods
static HRESULT CymaxQueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface);
static ULONG CymaxAddRef(void* inDriver);
static ULONG CymaxRelease(void* inDriver);
static OSStatus CymaxInitialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost);
static OSStatus CymaxCreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID);
static OSStatus CymaxDestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID);
static OSStatus CymaxAddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
static OSStatus CymaxRemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
static OSStatus CymaxPerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);
static OSStatus CymaxAbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);
static Boolean CymaxHasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress);
static OSStatus CymaxIsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable);
static OSStatus CymaxGetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32* outDataSize);
static OSStatus CymaxGetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData);
static OSStatus CymaxSetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, const void* inData);
static OSStatus CymaxStartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus CymaxStopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus CymaxGetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed);
static OSStatus CymaxWillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outWillDoInPlace);
static OSStatus CymaxBeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);
static OSStatus CymaxDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer);
static OSStatus CymaxEndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);

// Plugin interface struct
static AudioServerPlugInDriverInterface gPluginInterface = {
    nullptr,  // _reserved
    CymaxQueryInterface,
    CymaxAddRef,
    CymaxRelease,
    CymaxInitialize,
    CymaxCreateDevice,
    CymaxDestroyDevice,
    CymaxAddDeviceClient,
    CymaxRemoveDeviceClient,
    CymaxPerformDeviceConfigurationChange,
    CymaxAbortDeviceConfigurationChange,
    CymaxHasProperty,
    CymaxIsPropertySettable,
    CymaxGetPropertyDataSize,
    CymaxGetPropertyData,
    CymaxSetPropertyData,
    CymaxStartIO,
    CymaxStopIO,
    CymaxGetZeroTimeStamp,
    CymaxWillDoIOOperation,
    CymaxBeginIOOperation,
    CymaxDoIOOperation,
    CymaxEndIOOperation
};

// Pointer to interface (what we return from Create)
static AudioServerPlugInDriverInterface* gPluginInterfacePtr = &gPluginInterface;

#pragma mark - Plugin Entry Point

extern "C" void* CymaxPhoneOut_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    // Verify the requested type is the AudioServerPlugIn type
    if (!CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        CYMAX_LOG_ERROR("CymaxPhoneOut_Create: Wrong type UUID requested");
        return nullptr;
    }
    
    CYMAX_LOG_INFO("CymaxPhoneOut_Create: Plugin created");
    
    // Return pointer to pointer to interface
    return &gPluginInterfacePtr;
}

#pragma mark - IUnknown Methods

static HRESULT CymaxQueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface) {
    // Check for the AudioServerPlugIn interface
    CFUUIDRef requestedUUID = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, inUUID);
    
    if (CFEqual(requestedUUID, IUnknownUUID) || 
        CFEqual(requestedUUID, kAudioServerPlugInDriverInterfaceUUID)) {
        CFRelease(requestedUUID);
        CymaxAddRef(inDriver);
        *outInterface = inDriver;
        return S_OK;
    }
    
    CFRelease(requestedUUID);
    *outInterface = nullptr;
    return E_NOINTERFACE;
}

static ULONG CymaxAddRef(void* inDriver) {
    std::lock_guard<std::mutex> lock(gPluginMutex);
    ++gRefCount;
    CYMAX_LOG_DEBUG("CymaxAddRef: refcount=%u", gRefCount);
    return gRefCount;
}

static ULONG CymaxRelease(void* inDriver) {
    std::lock_guard<std::mutex> lock(gPluginMutex);
    
    if (gRefCount > 0) {
        --gRefCount;
    }
    
    CYMAX_LOG_DEBUG("CymaxRelease: refcount=%u", gRefCount);
    
    if (gRefCount == 0) {
        // Cleanup
        gDevice.reset();
        gHost = nullptr;
    }
    
    return gRefCount;
}

#pragma mark - Plugin Methods

static OSStatus CymaxInitialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost) {
    CYMAX_LOG_INFO("CymaxInitialize");
    
    std::lock_guard<std::mutex> lock(gPluginMutex);
    
    gHost = inHost;
    
    // Create the device
    gDevice = std::make_unique<Cymax::AudioDevice>(kDeviceObjectID, kPluginObjectID);
    
    return noErr;
}

static OSStatus CymaxCreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, 
                                  const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID) {
    // This plugin doesn't support dynamic device creation
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus CymaxDestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID) {
    // This plugin doesn't support dynamic device destruction
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus CymaxAddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, 
                                     const AudioServerPlugInClientInfo* inClientInfo) {
    CYMAX_LOG_DEBUG("CymaxAddDeviceClient: device=%u, pid=%d", inDeviceObjectID, inClientInfo->mProcessID);
    return noErr;
}

static OSStatus CymaxRemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, 
                                        const AudioServerPlugInClientInfo* inClientInfo) {
    CYMAX_LOG_DEBUG("CymaxRemoveDeviceClient: device=%u, pid=%d", inDeviceObjectID, inClientInfo->mProcessID);
    return noErr;
}

static OSStatus CymaxPerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, 
                                                      UInt64 inChangeAction, void* inChangeInfo) {
    CYMAX_LOG_DEBUG("CymaxPerformDeviceConfigurationChange: action=%llu", inChangeAction);
    return noErr;
}

static OSStatus CymaxAbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, 
                                                    UInt64 inChangeAction, void* inChangeInfo) {
    CYMAX_LOG_DEBUG("CymaxAbortDeviceConfigurationChange: action=%llu", inChangeAction);
    return noErr;
}

#pragma mark - Property Methods

// Helper to get the right object
static Cymax::AudioObject* GetObjectForID(AudioObjectID objectID) {
    switch (objectID) {
        case kDeviceObjectID:
            return gDevice.get();
        case kOutputStreamObjectID:
            return gDevice ? gDevice->getOutputStream() : nullptr;
        default:
            return nullptr;
    }
}

static Boolean CymaxHasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, 
                                pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress) {
    // Plugin object properties
    if (inObjectID == kPluginObjectID) {
        switch (inAddress->mSelector) {
            case kAudioObjectPropertyBaseClass:
            case kAudioObjectPropertyClass:
            case kAudioPlugInPropertyDeviceList:
            case kAudioPlugInPropertyTranslateUIDToDevice:
            case kAudioPlugInPropertyResourceBundle:
            case kAudioObjectPropertyManufacturer:
                return true;
            default:
                return false;
        }
    }
    
    Cymax::AudioObject* obj = GetObjectForID(inObjectID);
    if (obj) {
        return obj->hasProperty(inAddress);
    }
    
    return false;
}

static OSStatus CymaxIsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, 
                                        pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, 
                                        Boolean* outIsSettable) {
    // Plugin object properties are not settable
    if (inObjectID == kPluginObjectID) {
        *outIsSettable = false;
        return noErr;
    }
    
    Cymax::AudioObject* obj = GetObjectForID(inObjectID);
    if (obj) {
        return obj->isPropertySettable(inAddress, outIsSettable);
    }
    
    *outIsSettable = false;
    return kAudioHardwareBadObjectError;
}

static OSStatus CymaxGetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, 
                                         pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, 
                                         UInt32 inQualifierDataSize, const void* inQualifierData, 
                                         UInt32* outDataSize) {
    // Plugin object properties
    if (inObjectID == kPluginObjectID) {
        switch (inAddress->mSelector) {
            case kAudioObjectPropertyBaseClass:
            case kAudioObjectPropertyClass:
                *outDataSize = sizeof(AudioClassID);
                return noErr;
            
            case kAudioPlugInPropertyDeviceList:
                *outDataSize = sizeof(AudioObjectID);  // One device
                return noErr;
            
            case kAudioPlugInPropertyTranslateUIDToDevice:
                *outDataSize = sizeof(AudioObjectID);
                return noErr;
            
            case kAudioPlugInPropertyResourceBundle:
            case kAudioObjectPropertyManufacturer:
                *outDataSize = sizeof(CFStringRef);
                return noErr;
            
            default:
                *outDataSize = 0;
                return kAudioHardwareUnknownPropertyError;
        }
    }
    
    Cymax::AudioObject* obj = GetObjectForID(inObjectID);
    if (obj) {
        return obj->getPropertyDataSize(inAddress, inQualifierDataSize, inQualifierData, outDataSize);
    }
    
    *outDataSize = 0;
    return kAudioHardwareBadObjectError;
}

static OSStatus CymaxGetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, 
                                     pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, 
                                     UInt32 inQualifierDataSize, const void* inQualifierData, 
                                     UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    // Plugin object properties
    if (inObjectID == kPluginObjectID) {
        switch (inAddress->mSelector) {
            case kAudioObjectPropertyBaseClass:
                if (inDataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
                *static_cast<AudioClassID*>(outData) = kAudioObjectClassID;
                *outDataSize = sizeof(AudioClassID);
                return noErr;
            
            case kAudioObjectPropertyClass:
                if (inDataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
                *static_cast<AudioClassID*>(outData) = kAudioPlugInClassID;
                *outDataSize = sizeof(AudioClassID);
                return noErr;
            
            case kAudioPlugInPropertyDeviceList:
                if (inDataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
                *static_cast<AudioObjectID*>(outData) = kDeviceObjectID;
                *outDataSize = sizeof(AudioObjectID);
                return noErr;
            
            case kAudioPlugInPropertyTranslateUIDToDevice: {
                if (inQualifierDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
                if (inDataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
                
                CFStringRef uid = *static_cast<const CFStringRef*>(inQualifierData);
                if (CFStringCompare(uid, CFSTR("CymaxPhoneOutMVP"), 0) == kCFCompareEqualTo) {
                    *static_cast<AudioObjectID*>(outData) = kDeviceObjectID;
                } else {
                    *static_cast<AudioObjectID*>(outData) = kAudioObjectUnknown;
                }
                *outDataSize = sizeof(AudioObjectID);
                return noErr;
            }
            
            case kAudioPlugInPropertyResourceBundle:
                if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
                *static_cast<CFStringRef*>(outData) = CFSTR("");  // No resource bundle
                *outDataSize = sizeof(CFStringRef);
                return noErr;
            
            case kAudioObjectPropertyManufacturer:
                if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
                *static_cast<CFStringRef*>(outData) = CFSTR("Cymax");
                *outDataSize = sizeof(CFStringRef);
                return noErr;
            
            default:
                *outDataSize = 0;
                return kAudioHardwareUnknownPropertyError;
        }
    }
    
    Cymax::AudioObject* obj = GetObjectForID(inObjectID);
    if (obj) {
        return obj->getPropertyData(inAddress, inQualifierDataSize, inQualifierData, 
                                   inDataSize, outDataSize, outData);
    }
    
    *outDataSize = 0;
    return kAudioHardwareBadObjectError;
}

static OSStatus CymaxSetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, 
                                     pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, 
                                     UInt32 inQualifierDataSize, const void* inQualifierData, 
                                     UInt32 inDataSize, const void* inData) {
    // Plugin object has no settable properties
    if (inObjectID == kPluginObjectID) {
        return kAudioHardwareUnknownPropertyError;
    }
    
    Cymax::AudioObject* obj = GetObjectForID(inObjectID);
    if (obj) {
        return obj->setPropertyData(inAddress, inQualifierDataSize, inQualifierData, 
                                   inDataSize, inData);
    }
    
    return kAudioHardwareBadObjectError;
}

#pragma mark - IO Methods

static OSStatus CymaxStartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    CYMAX_LOG_INFO("CymaxStartIO: device=%u, client=%u", inDeviceObjectID, inClientID);
    
    if (inDeviceObjectID != kDeviceObjectID || !gDevice) {
        return kAudioHardwareBadObjectError;
    }
    
    return gDevice->startIO();
}

static OSStatus CymaxStopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    CYMAX_LOG_INFO("CymaxStopIO: device=%u, client=%u", inDeviceObjectID, inClientID);
    
    if (inDeviceObjectID != kDeviceObjectID || !gDevice) {
        return kAudioHardwareBadObjectError;
    }
    
    gDevice->stopIO();
    return noErr;
}

// Timing state for GetZeroTimeStamp
static uint64_t gZeroTimeStampHostTime = 0;
static uint64_t gZeroTimeStampSeed = 1;
static Float64 gZeroTimeStampSampleTime = 0;

static OSStatus CymaxGetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, 
                                      UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, 
                                      UInt64* outSeed) {
    if (inDeviceObjectID != kDeviceObjectID || !gDevice) {
        return kAudioHardwareBadObjectError;
    }
    
    // Get current host time
    uint64_t currentHostTime = mach_absolute_time();
    
    // Initialize zero timestamp if needed
    if (gZeroTimeStampHostTime == 0) {
        gZeroTimeStampHostTime = currentHostTime;
        gZeroTimeStampSampleTime = 0;
        gZeroTimeStampSeed = 1;
    }
    
    // Calculate elapsed time and samples
    Float64 sampleRate = gDevice->getSampleRate();
    
    // Convert mach time to seconds
    static mach_timebase_info_data_t timebaseInfo = {0, 0};
    if (timebaseInfo.denom == 0) {
        mach_timebase_info(&timebaseInfo);
    }
    
    Float64 elapsedNanos = static_cast<Float64>(currentHostTime - gZeroTimeStampHostTime) * 
                          timebaseInfo.numer / timebaseInfo.denom;
    Float64 elapsedSamples = (elapsedNanos / 1e9) * sampleRate;
    
    // Advance the zero timestamp periodically (once per second of samples)
    Float64 zeroTimeStampPeriod = sampleRate;  // 1 second worth of samples
    while (gZeroTimeStampSampleTime + zeroTimeStampPeriod < elapsedSamples) {
        gZeroTimeStampSampleTime += zeroTimeStampPeriod;
        gZeroTimeStampHostTime += static_cast<uint64_t>((zeroTimeStampPeriod / sampleRate) * 1e9 * 
                                                        timebaseInfo.denom / timebaseInfo.numer);
        gZeroTimeStampSeed++;
    }
    
    *outSampleTime = gZeroTimeStampSampleTime;
    *outHostTime = gZeroTimeStampHostTime;
    *outSeed = gZeroTimeStampSeed;
    
    return noErr;
}

static OSStatus CymaxWillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, 
                                       UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, 
                                       Boolean* outWillDoInPlace) {
    if (inDeviceObjectID != kDeviceObjectID) {
        return kAudioHardwareBadObjectError;
    }
    
    // We handle WriteMix for output
    switch (inOperationID) {
        case kAudioServerPlugInIOOperationWriteMix:
            *outWillDo = true;
            *outWillDoInPlace = true;
            break;
        
        default:
            *outWillDo = false;
            *outWillDoInPlace = true;
            break;
    }
    
    return noErr;
}

static OSStatus CymaxBeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, 
                                      UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, 
                                      const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    // Nothing to do at begin
    return noErr;
}

static OSStatus CymaxDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, 
                                   AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, 
                                   UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, 
                                   void* ioMainBuffer, void* ioSecondaryBuffer) {
    // CRITICAL: This is the real-time render callback
    // DO NOT allocate, lock, log, or make system calls here
    
    if (inDeviceObjectID != kDeviceObjectID || !gDevice) {
        return kAudioHardwareBadObjectError;
    }
    
    return gDevice->doIOOperation(inIOBufferFrameSize, inIOCycleInfo, inOperationID,
                                  inIOBufferFrameSize, ioMainBuffer, ioSecondaryBuffer);
}

static OSStatus CymaxEndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, 
                                    UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, 
                                    const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    // Nothing to do at end
    return noErr;
}


