//
//  CymaxPluginInterface.hpp
//  CymaxPhoneOutDriver
//
//  AudioServerPlugIn interface header
//
//  This file defines the C interface required by CoreAudio to load our plugin.
//  The plugin follows Apple's AudioServerPlugIn architecture.
//

#ifndef CymaxPluginInterface_hpp
#define CymaxPluginInterface_hpp

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>

// Plugin entry point - exported symbol that CoreAudio looks for
extern "C" {
    void* CymaxPhoneOut_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID);
}

#endif /* CymaxPluginInterface_hpp */


