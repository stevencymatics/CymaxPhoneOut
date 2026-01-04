# Development Notes

Technical details and decisions made during development.

## Why IP-over-USB?

The original goal was to use Apple's "Personal Hotspot" USB tethering feature, which creates an IP network over a USB/Lightning cable. Benefits:

- **Lower latency**: ~5-10ms network latency vs 20-50ms WiFi
- **More reliable**: No packet loss or jitter from WiFi interference
- **No WiFi dependency**: Works in airplane mode or areas with congested WiFi

### How USB Tethering Works

1. Connect iPhone to Mac via USB cable
2. Enable Personal Hotspot on iPhone (Settings → Personal Hotspot → Allow Others to Join)
3. A new network interface appears on Mac (typically `en8` or similar)
4. iPhone gets IP `172.20.10.1`, Mac gets `172.20.10.x`
5. They can communicate over TCP/UDP like any network

### Why We Pivoted to WiFi (MVP)

During initial testing, the USB network interface wasn't activating consistently. Rather than debug hardware/driver issues, we pivoted to WiFi to get a working MVP first. USB tethering remains a future improvement.

## AudioServerPlugIn Architecture

### Why Not a Simple App?

macOS doesn't allow apps to create virtual audio devices. You MUST use the AudioServerPlugIn API, which runs as a kernel extension loaded by `coreaudiod`.

### Plugin Loading

1. Plugin bundle goes in `/Library/Audio/Plug-Ins/HAL/`
2. `coreaudiod` loads plugins at startup (or after `killall coreaudiod`)
3. Plugin registers its devices, which appear in Sound preferences

### Real-Time Constraints

The `doIOOperation` callback runs on a real-time audio thread. You MUST NOT:
- Allocate memory
- Take locks
- Make system calls
- Do any I/O

Our solution: Write samples to a lock-free ring buffer, have a separate thread handle networking.

## In-Process Transport (MVP Tradeoff)

### Current Design

The UDP sender runs inside the AudioServerPlugIn process (which runs inside `coreaudiod`).

```
coreaudiod process
├── CoreAudio Thread (real-time)
│   └── doIOOperation → writes to ring buffer
└── UDP Sender Thread (non-real-time)
    └── reads from ring buffer → sendto()
```

### Why This Is Suboptimal

1. **Security**: Network code in a privileged system process
2. **Stability**: A crash in our UDP code could crash `coreaudiod`
3. **Debugging**: Can't easily attach debugger to `coreaudiod`

### Future: XPC + Shared Memory

Production design would use:
1. **Shared Memory**: Ring buffer in shared memory region
2. **XPC Service**: Separate process for network handling
3. **Menubar App**: Coordinates between driver and XPC service

## Jitter Buffer Design

### The Problem

Network packets don't arrive at a constant rate. WiFi especially has:
- **Jitter**: Packets arrive early or late
- **Bursts**: Multiple packets arrive at once
- **Gaps**: No packets for a while

DAWs (FL Studio) add another problem:
- **Bursty Output**: DAW fills its buffer, sends chunk, processes, repeat
- **Variable Timing**: Render callbacks aren't perfectly spaced

### Our Solution

1. **Large Capacity**: 2 seconds of audio storage
2. **Moderate Prebuffer**: 150-300ms before starting playback
3. **Quick Recovery**: Only 50ms rebuffer after underrun
4. **Fade-In**: 21ms audio fade when resuming to hide pops

### Adaptive Buffering (Future)

A smarter approach would dynamically adjust buffer size based on:
- Measured network jitter
- Underrun frequency
- User latency preference

## Bonjour Auto-Discovery

### The Ideal Flow

1. iPhone advertises `_cymaxaudio._tcp` service via Bonjour
2. Mac discovers service automatically
3. User just clicks "Connect" without entering IP

### Why It's Disabled

Apple requires the **Multicast Networking Entitlement** for Bonjour on iOS. This entitlement requires:
1. Apply to Apple Developer Relations
2. Explain your use case
3. Wait for approval (weeks/months)

For MVP, we use manual IP entry instead.

## Audio Format Decisions

### Why 48kHz?

- Standard for video production
- Native rate for many audio interfaces
- FL Studio defaults to this

### Why Float32?

- CoreAudio native format
- No clipping on values slightly > 1.0
- Easy math for mixing/effects

### Why 256 Frames Per Packet?

- Small enough for low latency (~5ms at 48kHz)
- Large enough to amortize UDP header overhead
- Fits comfortably in typical MTU (1500 bytes)

Packet size: 28 header + 256 frames × 2 channels × 4 bytes = 2076 bytes

## Debugging Tips

### View Driver Logs

```bash
log stream --predicate 'process == "coreaudiod"' --info --debug
```

### Monitor UDP Traffic

```bash
sudo tcpdump -i any udp port 19620 -v
```

### Check Audio Devices

```bash
system_profiler SPAudioDataType
```

### Force Driver Reload

```bash
sudo killall coreaudiod
```

## Common Issues

### "Address already in use" (iOS)

The UDP listener port is still bound from a previous run. Force quit the app and restart.

### No Audio After Sleep

`coreaudiod` may reload plugins after sleep. The IP file in `/tmp` persists, so it should reconnect automatically.

### Crackling with FL Studio

FL Studio's bursty output pattern causes buffer underruns. Increase FL Studio's buffer to 2048+ samples.

## Performance Considerations

### CPU Usage

- **Mac Driver**: Minimal (ring buffer write is O(1))
- **Mac App**: Minimal (just UI and TCP)
- **iPhone**: ~5-10% (audio processing + network)

### Network Bandwidth

At 48kHz stereo Float32:
- Raw audio: 48000 × 2 × 4 = 384 KB/s
- With headers: ~400 KB/s
- Roughly 3.2 Mbps

Easily handled by any WiFi or USB connection.

### Battery Impact (iPhone)

Continuous audio playback + network receive uses moderate battery. Expect 4-6 hours of continuous streaming on a full charge.

## Code Style

- **Swift**: SwiftUI for UI, async/await for networking
- **C++**: Modern C++17, no raw pointers (use unique_ptr)
- **Logging**: Compile-time disabled in render callback

## Testing Checklist

- [ ] Apple Music playback
- [ ] YouTube in browser
- [ ] FL Studio with various buffer sizes
- [ ] Disconnect/reconnect cycle
- [ ] Sleep/wake cycle
- [ ] Format changes (44.1kHz ↔ 48kHz)
