# Cymax Phone Out - macOS to iPhone Audio Streaming

Stream system audio from your Mac to your iPhone in near-real-time over WiFi (or USB tethering).

## 🎯 What It Does

- Creates a virtual audio output device on macOS called **"Cymax Phone Out (MVP)"**
- Any audio sent to this device is streamed over UDP to an iPhone app
- Works with any audio source: Apple Music, Spotify, YouTube, **FL Studio**, Logic Pro, etc.
- ~150-300ms latency over WiFi (can be reduced with USB tethering)

## 📁 Project Structure

```
Phone Audio Project/
├── mac/
│   ├── CymaxPhoneOutDriver/     # macOS AudioServerPlugIn (virtual audio device)
│   │   ├── Source/
│   │   │   ├── PluginEntry.cpp      # Plugin entry point
│   │   │   ├── CymaxAudioDevice.cpp # Main device implementation
│   │   │   ├── CymaxAudioStream.cpp # Audio stream handling
│   │   │   ├── RingBuffer.hpp       # Lock-free ring buffer
│   │   │   ├── UDPSender.cpp        # UDP packet sender thread
│   │   │   └── Logging.hpp          # Debug logging
│   │   └── CymaxPhoneOutDriver.xcodeproj
│   │
│   └── CymaxPhoneOutMenubar/    # macOS menubar control app (SwiftUI)
│       ├── CymaxPhoneOutMenubar/
│       │   ├── AppState.swift           # Main app state
│       │   ├── MenuBarView.swift        # Menubar UI
│       │   ├── BonjourBrowser.swift     # Service discovery (disabled)
│       │   ├── ControlChannelClient.swift # TCP client
│       │   └── DriverCommunication.swift  # IPC with driver
│       └── CymaxPhoneOutMenubar.xcodeproj
│
├── ios/
│   └── CymaxPhoneReceiver/      # iOS receiver app (SwiftUI)
│       ├── CymaxPhoneReceiver/
│       │   ├── ReceiverState.swift      # Main app state
│       │   ├── ContentView.swift        # Main UI
│       │   ├── AudioReceiver.swift      # UDP packet receiver
│       │   ├── JitterBuffer.swift       # Audio buffering
│       │   ├── AudioPlayer.swift        # AVAudioEngine playback
│       │   └── ControlChannelServer.swift # TCP server
│       └── CymaxPhoneReceiver.xcodeproj
│
├── shared/
│   └── CymaxAudioProtocol/      # Shared Swift Package
│       ├── Package.swift
│       └── Sources/
│           ├── AudioPacket.swift        # Packet format definitions
│           ├── ControlMessage.swift     # Control protocol messages
│           └── BonjourConstants.swift   # Network constants
│
├── build/                       # Build output directory
├── docs/                        # Additional documentation
└── README.md                    # This file
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              macOS                                       │
│  ┌──────────────────┐    ┌─────────────────────────────────────────┐    │
│  │   Menubar App    │    │        AudioServerPlugIn (Driver)       │    │
│  │  (SwiftUI)       │    │                                         │    │
│  │                  │    │  ┌─────────┐   ┌────────┐   ┌────────┐  │    │
│  │  - Connect UI    │───▶│  │ CoreAudio│──▶│ Ring   │──▶│  UDP   │  │    │
│  │  - IP entry      │ IP │  │ Callback │   │ Buffer │   │ Sender │  │    │
│  │  - Status        │file│  └─────────┘   └────────┘   └───┬────┘  │    │
│  └──────────────────┘    └─────────────────────────────────┼───────┘    │
│           │                                                 │            │
│           │ TCP (control)                      UDP (audio)  │            │
└───────────┼─────────────────────────────────────────────────┼────────────┘
            │                    WiFi                         │
            ▼                                                 ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                              iPhone                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                      CymaxPhoneReceiver App                          │  │
│  │                                                                      │  │
│  │  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────────────┐   │  │
│  │  │   UDP   │───▶│ Jitter  │───▶│ Audio   │───▶│  AVAudioEngine  │   │  │
│  │  │Receiver │    │ Buffer  │    │ Player  │    │ (SourceNode)    │   │  │
│  │  └─────────┘    └─────────┘    └─────────┘    └─────────────────┘   │  │
│  │       ▲                                                              │  │
│  │       │ TCP (control: HELLO, format negotiation)                     │  │
│  │  ┌────┴────┐                                                         │  │
│  │  │  TCP    │                                                         │  │
│  │  │ Server  │                                                         │  │
│  │  └─────────┘                                                         │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Audio Capture**: macOS routes audio to "Cymax Phone Out (MVP)" device
2. **Ring Buffer**: Driver's render callback writes samples to lock-free ring buffer
3. **UDP Sender**: Background thread reads from ring buffer, creates packets, sends via UDP
4. **Network**: Packets travel over WiFi (port 19620) to iPhone
5. **Jitter Buffer**: iPhone app buffers packets to absorb network jitter
6. **Playback**: AVAudioEngine pulls samples from jitter buffer and plays them

### Packet Format

```
Audio Packet (28-byte header + audio data):
┌──────────────────────────────────────────────────────────────┐
│ magic (4)  │ sequence (4) │ timestamp (8) │ sampleRate (4)  │
├──────────────────────────────────────────────────────────────┤
│ channels (2) │ frameCount (2) │ format (2) │ flags (2)      │
├──────────────────────────────────────────────────────────────┤
│                    Audio Data (Float32 interleaved)          │
│                    (frameCount * channels * 4 bytes)         │
└──────────────────────────────────────────────────────────────┘
```

## 🔧 Building

### Prerequisites

- **Xcode 15+**
- **macOS 13+ (Ventura)**
- **iOS 16+** device for testing
- **Apple Developer account** (for iOS code signing)

### Build Steps

#### 1. Build the macOS Audio Driver

```bash
cd mac/CymaxPhoneOutDriver
xcodebuild -scheme CymaxPhoneOutDriver -configuration Release
```

#### 2. Install the Driver

```bash
# Copy to system plugins folder
sudo cp -R build/Release/CymaxPhoneOutDriver.driver /Library/Audio/Plug-Ins/HAL/

# Restart Core Audio daemon
sudo killall coreaudiod
```

#### 3. Build the macOS Menubar App

```bash
cd mac/CymaxPhoneOutMenubar
xcodebuild -scheme CymaxPhoneOutMenubar -configuration Debug
```

#### 4. Build the iOS App

Open `ios/CymaxPhoneReceiver/CymaxPhoneReceiver.xcodeproj` in Xcode and:
- Set your development team in Signing & Capabilities
- Build and run on your iPhone (⌘R)

## 📱 Usage

### First Time Setup

1. **Start the iPhone app** - Tap "Start Receiving"
2. **Note the iPhone's IP address** shown in the app (e.g., `192.168.1.201`)
3. **Start the Mac menubar app** - Click the antenna icon in menubar
4. **Enter the iPhone's IP** in the Mac app and click "Connect"
5. **Select "Cymax Phone Out (MVP)"** as your Mac's audio output:
   - System Settings → Sound → Output → Cymax Phone Out (MVP)
6. **Play audio** on your Mac - it should come out of your iPhone!

### Using with FL Studio / DAWs

1. Open FL Studio → Options → Audio Settings
2. Select "Cymax Phone Out (MVP)" as the output device
3. Set buffer to **1024-2048 samples** (smaller may cause issues)
4. Sample rate: **48000 Hz**

## ⚙️ Configuration

### Latency Modes (iOS App)

| Mode | Prebuffer | Use Case |
|------|-----------|----------|
| Low Latency | 150ms | Music listening, casual use |
| Stable | 300ms | DAWs, unreliable WiFi |

### Buffer Sizes

| Component | Size | Purpose |
|-----------|------|---------|
| Mac Ring Buffer | 48000 frames (1s) | Handle DAW burst output |
| iOS Jitter Buffer | 2s capacity | Absorb network jitter |
| iOS Prebuffer | 150-300ms | Initial latency target |

## 🐛 Known Issues & Solutions

### No Audio Coming Through

1. **Check the driver is loaded**: Look for "Cymax Phone Out (MVP)" in System Settings → Sound → Output
2. **Restart Core Audio**: `sudo killall coreaudiod`
3. **Check IP file exists**: `cat /tmp/cymax_dest_ip.txt`
4. **Verify connection**: iPhone should show "Connected to [Mac name]"

### Audio Pops/Clicks

- **Over WiFi**: Some pops are unavoidable due to network jitter
- **Try Stable mode** in the iOS app for larger buffer
- **USB tethering** (future) will reduce this significantly

### FL Studio Issues

- **No sound with small buffer**: Increase FL Studio buffer to 2048+ samples
- **Delayed playback**: This is expected (~150-300ms latency)

### Driver Not Appearing

```bash
# Check driver is installed
ls -la /Library/Audio/Plug-Ins/HAL/ | grep Cymax

# Check driver logs
log show --last 5m --predicate 'process == "coreaudiod"' | grep -i cymax
```

## 🔮 Future Improvements

### Planned

- [ ] **USB Tethering Support** - Lower latency (20-50ms) via wired connection
- [ ] **Bonjour Auto-Discovery** - Requires Apple entitlement approval
- [ ] **Volume Control** - Independent volume in iOS app
- [ ] **Multi-Device** - Stream to multiple phones simultaneously

### Technical Debt

- [ ] Move UDP sender out of driver process (use XPC + shared memory)
- [ ] Add proper error recovery for network disconnections
- [ ] Implement adaptive jitter buffer sizing
- [ ] Add audio format conversion (currently 48kHz stereo only)

## 📊 Technical Details

### Audio Format

- **Sample Rate**: 48000 Hz (44100 Hz also supported)
- **Channels**: 2 (stereo)
- **Bit Depth**: 32-bit float
- **Packet Size**: 256 frames per packet (512 samples for stereo)

### Network

- **UDP Port 19620**: Audio data
- **TCP Port 19621**: Control channel (HELLO, format negotiation, stats)
- **Packet Size**: ~2076 bytes (28 header + 2048 audio)

### IPC (Driver ↔ Menubar App)

The menubar app writes the destination IP to `/tmp/cymax_dest_ip.txt`, which the driver reads when audio starts playing. This is an MVP solution - production would use XPC or custom AudioObject properties.

## 🧪 Testing

### Verify UDP Packets Are Being Sent

```bash
sudo tcpdump -i any host 192.168.1.201 and udp port 19620
```

### Check Driver Status

```bash
cat /tmp/cymax_driver_status.txt
```

### View iOS App Logs

Run the iOS app from Xcode to see console output with packet counts and buffer levels.

## 📄 License

MIT License - See LICENSE file

## 👥 Contributors

- Initial development: [Your Name]
- Audio engine work: Claude (AI Assistant)

---

**Questions?** Check the `/docs` folder for additional technical documentation.
