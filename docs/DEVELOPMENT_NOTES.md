# Development Notes

Technical details and decisions made during development.

## Architecture Overview

Cymax Audio has evolved through two approaches:

### V1: Virtual Audio Driver + Native iOS App (Legacy)
- Custom AudioServerPlugIn creates virtual audio output
- UDP streaming to native iOS app
- Required users to change their audio output device

### V2: ScreenCaptureKit + Web Player (Current)
- Uses ScreenCaptureKit to capture ALL system audio
- No audio output switching required
- WebSocket streaming to web browser on phone
- QR code for instant connection

## The Critical Non-Interleaved Audio Bug

### The Problem
Audio sounded like a chipmunk (high-pitched) with constant glitchiness and distortion.

### Root Cause
**ScreenCaptureKit outputs non-interleaved audio**, but we were treating it as interleaved.

```
Non-interleaved (what SCK outputs):
[L0, L1, L2, ..., L959, R0, R1, R2, ..., R959]

Interleaved (what we expected):
[L0, R0, L1, R1, L2, R2, ..., L959, R959]
```

### The Fix (SystemAudioCapture.swift)
```swift
// Convert from NON-INTERLEAVED to INTERLEAVED format
var interleavedSamples = [Float](repeating: 0, count: sampleCount)
for frame in 0..<frameCount {
    let leftSample = floatPointer[frame]                // Left: first half
    let rightSample = floatPointer[frameCount + frame]  // Right: second half
    interleavedSamples[frame * 2] = leftSample
    interleavedSamples[frame * 2 + 1] = rightSample
}
```

### How We Found It
Added debug instrumentation to log the AudioStreamBasicDescription:
```
"isInterleaved": false  ← This was the clue!
```

## ScreenCaptureKit Notes

### Why ScreenCaptureKit?
- Captures system audio without changing audio output
- Works alongside existing speakers/headphones
- Apple's recommended API for audio capture (macOS 13+)
- No kernel extension or driver installation required

### Audio Format from SCK
- 48000 Hz (configurable)
- 2 channels (stereo)
- Float32 samples
- **Non-interleaved** (critical!)
- 960 frames per buffer typically (~20ms)

### Permissions Required
- **Screen Recording** permission (despite only capturing audio)
- User must grant in System Settings → Privacy & Security → Screen Recording
- App needs `NSScreenCaptureUsageDescription` in Info.plist

## Web Audio Architecture

### Why Web Audio Instead of Native App?
- **No app install** on phone
- **Cross-platform** - works on iOS, Android, any browser
- **Easy updates** - just refresh the page
- **Lower friction** - scan QR and play

### WebSocket vs UDP
We switched from UDP (for native app) to WebSocket (for web):
- Browsers can't do raw UDP
- WebSocket is reliable (TCP-based) but adds ~10-20ms latency
- Acceptable tradeoff for the convenience of browser-based playback

### ScriptProcessorNode vs AudioWorklet
Currently using ScriptProcessorNode (deprecated but widely supported):
- Works on all browsers including iOS Safari
- Known timing issues on mobile
- AudioWorklet would be better but has compatibility issues on iOS

### Buffering Strategy
```javascript
PREBUFFER_MS = 200   // Wait for 200ms before starting playback
TARGET_BUFFER_MS = 300  // Try to maintain 300ms buffer
BUFFER_SIZE = 3 seconds // Max circular buffer capacity
```

## Network Architecture

### Ports Used
| Port | Protocol | Purpose |
|------|----------|---------|
| 19621 | HTTP | Serves web player HTML |
| 19622 | WebSocket | Audio streaming |

### Packet Format (WebSocket)
```
16-byte header:
- sequence (4 bytes) - packet counter
- timestamp (4 bytes) - milliseconds
- sampleRate (4 bytes) - e.g., 48000
- channels (2 bytes) - e.g., 2
- frameCount (2 bytes) - e.g., 128

Followed by:
- Float32 audio samples (interleaved)
- frameCount * channels * 4 bytes
```

## AudioServerPlugIn Architecture (Legacy)

### Why a Driver?
macOS doesn't allow apps to create virtual audio devices. The AudioServerPlugIn API runs as a plugin loaded by `coreaudiod`.

### Real-Time Constraints
The `doIOOperation` callback runs on a real-time audio thread. You MUST NOT:
- Allocate memory
- Take locks  
- Make system calls
- Do any I/O

Solution: Lock-free ring buffer for audio data, separate thread for networking.

## Debugging Tips

### View ScreenCaptureKit Logs
```bash
log stream --predicate 'subsystem == "com.apple.screencapturekit"' --info
```

### Monitor WebSocket Traffic
Use browser DevTools → Network → WS tab

### Check Audio Format
Add logging in `stream(_:didOutputSampleBuffer:of:)`:
```swift
let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
print("Format flags: \(asbd.mFormatFlags)")
print("Is interleaved: \((asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0)")
```

### Test Audio Locally
```bash
# Check if app can capture audio
log show --last 5m --predicate 'process == "CymaxPhoneOutMenubar"' | grep -i audio
```

## Performance Notes

### CPU Usage
- **Mac**: ~3-5% (ScreenCaptureKit + WebSocket server)
- **Phone Browser**: ~5-10% (Web Audio API playback)

### Network Bandwidth
At 48kHz stereo Float32:
- ~400 KB/s or ~3.2 Mbps
- Easily handled by any WiFi network

### Latency Breakdown
| Component | Latency |
|-----------|---------|
| ScreenCaptureKit capture | ~20ms |
| Network (WiFi) | ~10-30ms |
| Browser prebuffer | 200ms |
| Web Audio processing | ~40ms |
| **Total** | **~300ms** |

## Testing Checklist

- [x] Apple Music playback
- [x] YouTube in browser
- [x] Spotify
- [x] Multiple browser tabs
- [x] Phone screen lock behavior
- [ ] FL Studio / DAW testing
- [ ] USB tethering (future)
- [ ] Multiple simultaneous listeners

## Known Issues

### iOS Safari Audio Context
Safari requires a user gesture (tap) to start AudioContext. The play button handles this.

### Phone Screen Lock
Audio may pause when phone screen locks. Keep screen on while streaming.

### "Connected Phones: 2"
Can show duplicate count if browser reconnects. Cosmetic issue only.

## Future Improvements

- [ ] AudioWorklet instead of ScriptProcessorNode
- [ ] Adaptive buffering based on network conditions
- [ ] USB tethering for lower latency
- [ ] Code signing & notarization
- [ ] Volume control in web player
