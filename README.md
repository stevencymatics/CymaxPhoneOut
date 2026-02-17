# Mix Link - macOS to iPhone Audio Streaming

Stream system audio from your Mac to your iPhone in real-time over WiFi. **No app install required on your phone** - just scan a QR code and listen!

## 🎯 What It Does

- **Captures ALL system audio** from your Mac using ScreenCaptureKit
- **No audio output switching required** - works with your existing speakers/headphones
- **No iPhone app needed** - uses your phone's web browser
- **QR code connection** - scan and play in seconds
- **Works with iPhone silent mode** - audio plays even when muted
- **Lock screen controls** - play/pause from iOS lock screen
- **Safari & Chrome support** - works on both browsers
- Works with any audio source: Apple Music, Spotify, YouTube, **FL Studio**, Logic Pro, etc.
- ~80-150ms latency over WiFi

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 🔊 System Audio Capture | Uses macOS ScreenCaptureKit - no need to change audio output |
| 📱 No App Required | Phone uses web browser (Chrome/Safari) |
| 📷 QR Code Setup | Instant connection - just scan and tap play |
| 🎵 48kHz Stereo | High-quality Float32 audio streaming |
| 🔇 Silent Mode Support | Bypasses iPhone mute switch |
| 🔒 Lock Screen Controls | Play/pause from iOS lock screen & Control Center |
| 🔄 Auto-Reconnect | Handles network interruptions gracefully |
| 🍎 Safari Compatible | HTTP streaming fallback for Safari |

## 🚀 Quick Start

### Option 1: Use Pre-Built App (Recommended)

1. Download `MixLink.dmg` from Releases
2. Open DMG and drag **Mix Link** to Applications
3. **Right-click → Open** (first time only, to bypass Gatekeeper)
4. Grant Screen Recording permission when prompted
5. Scan QR code with your phone - done!

### Option 2: Build from Source

```bash
cd mac/CymaxPhoneOutMenubar
xcodebuild -scheme CymaxPhoneOutMenubar -configuration Debug
open ~/Library/Developer/Xcode/DerivedData/CymaxPhoneOutMenubar-*/Build/Products/Debug/"Mix Link.app"
```

Or open in Xcode and press ⌘R.

### Grant Screen Recording Permission

The first time you run the app, it will show a permission screen. Click **Open Settings** and add Mix Link to the "Screen & System Audio Recording" list.

### Connect Your Phone

1. Click the waveform icon in your Mac's menubar
2. Scan the QR code with your iPhone camera
3. Open the link in Chrome or Safari
4. Tap the **Play** button
5. Play audio on your Mac - hear it on your phone! 🎉

## 📁 Project Structure

```
Phone Audio Project/
├── mac/
│   └── CymaxPhoneOutMenubar/      # macOS menubar app (SwiftUI)
│       ├── AppState.swift          # Main app state & audio processing
│       ├── MenuBarView.swift       # Menubar UI with QR code
│       ├── SystemAudioCapture.swift # ScreenCaptureKit audio capture
│       ├── HTTPServer.swift        # Combined HTTP + WebSocket server
│       ├── WebPlayerHTML.swift     # Embedded web audio player
│       ├── QRCodeGenerator.swift   # QR code generation
│       └── Assets.xcassets/        # App icon (circular cyan waveform)
│
├── mac/CymaxPhoneOutDriver/       # (Legacy) Virtual audio driver
│
└── docs/                          # Documentation
    ├── QUICK_START.md
    ├── IOS_SILENT_MODE_FIX.md
    └── DEVELOPMENT_NOTES.md
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                          macOS                               │
│                                                              │
│  ┌──────────────┐    ┌─────────────────────────────────┐    │
│  │   Mix Link   │    │     ScreenCaptureKit            │    │
│  │  Menubar App │◄───│  (System Audio Capture)         │    │
│  │              │    │                                  │    │
│  │  - QR Code   │    │  48kHz Stereo Float32           │    │
│  │  - Status    │    │  Non-interleaved → Interleaved  │    │
│  └──────┬───────┘    └─────────────────────────────────┘    │
│         │                                                    │
│  ┌──────▼──────────────────────────────────────────────┐    │
│  │          Combined HTTP + WebSocket Server            │    │
│  │                   (Port 19621)                       │    │
│  │                                                      │    │
│  │  • Serves web player HTML                           │    │
│  │  • WebSocket for Chrome (fast)                      │    │
│  │  • HTTP streaming for Safari (fallback)             │    │
│  │  • 128 frames/packet                                │    │
│  └──────────────────────────┬───────────────────────────┘    │
│                             │                                │
└─────────────────────────────┼────────────────────────────────┘
                              │ WiFi
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         iPhone                               │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Web Browser (Chrome/Safari)             │    │
│  │                                                      │    │
│  │  Chrome: WebSocket ──┐                              │    │
│  │  Safari: HTTP Stream ┼──▶ Circular ──▶ Web Audio    │    │
│  │                      │    Buffer       API          │    │
│  │                      └──────────────────────────────│    │
│  │                                                      │    │
│  │  MediaStreamDestination → <audio> (silent mode fix) │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Audio Packet Format

```
Binary Message (16-byte header + audio data):
┌──────────────────────────────────────────────────────────────┐
│ sequence (4) │ timestamp (4) │ sampleRate (4) │ channels (2) │
├──────────────────────────────────────────────────────────────┤
│ frameCount (2) │           Audio Data (Float32)              │
│                │      (frameCount * channels * 4 bytes)      │
└──────────────────────────────────────────────────────────────┘
```

## 🔧 Requirements

- **macOS 13+ (Ventura)** - for ScreenCaptureKit
- **Xcode 15+** (for building from source)
- **iPhone/iPad** with modern web browser
- **Same WiFi network** for Mac and phone

## ⚙️ Configuration

### Buffer Settings (Web Player)

| Setting | Value | Purpose |
|---------|-------|---------|
| Initial Prebuffer | 5ms | Fast startup |
| Rebuffer Threshold | 45ms | Auto-recovery |
| Target Buffer | 80ms | Low latency target |
| Max Buffer | 3 seconds | Circular buffer capacity |

### Audio Format

| Parameter | Value |
|-----------|-------|
| Sample Rate | 48000 Hz |
| Channels | 2 (stereo) |
| Bit Depth | 32-bit float |
| Frames/Packet | 128 |

## 🐛 Troubleshooting

### No Audio

1. **Check Screen Recording permission** - System Settings → Privacy & Security → Screen & System Audio Recording
2. **Make sure audio is playing** on your Mac
3. **Check the buffer indicator** in the web player

### Permission Issues

If the app keeps asking for permission after you've granted it:
1. Click "I've enabled it - Restart App" to restart
2. macOS requires an app restart to pick up new permissions

### Safari Won't Connect

Safari uses HTTP streaming fallback. If it's slow:
1. Wait for the initial connection (may take 1-2 seconds)
2. Once connected, playback should be smooth
3. Chrome is faster if available

### Audio Cuts Out

The app has auto-reconnect. If audio stops:
1. Check your WiFi connection
2. The web player will show a spinner while reconnecting
3. After 2 failed attempts, it shows "No connection found"

### Mac Goes to Sleep

Mix Link automatically stops when your Mac sleeps and restarts when it wakes. If permission was revoked during sleep, you'll see the permission screen.

## 📦 Distribution

Want to share Mix Link with others?

### Building a DMG

```bash
# Build release version
cd mac/CymaxPhoneOutMenubar
xcodebuild -scheme CymaxPhoneOutMenubar -configuration Release

# Create DMG (use Disk Utility or create-dmg tool)
```

### What Testers Need to Do

1. Download the DMG
2. Open it and drag **Mix Link** to Applications
3. **Right-click → Open** (first time only)
4. Grant Screen Recording permission
5. Scan QR code with phone - done!

## 🔮 Future Improvements

- [ ] USB tethering for lower latency
- [ ] Volume control in web player
- [ ] Latency display
- [ ] Multiple simultaneous listeners
- [x] ~~Safari support~~ - Done with HTTP streaming fallback!
- [x] ~~Silent mode support~~ - Done with MediaStreamDestination trick!
- [x] ~~Lock screen controls~~ - Done with Media Session API!
- [ ] Code signing & notarization for easier distribution

## 📊 Technical Notes

### Why ScreenCaptureKit?

- Captures **all system audio** without changing audio output
- Works alongside your speakers/headphones
- No driver installation required
- Apple's recommended approach for audio capture

### Why Single Port (19621)?

Safari has restrictions on cross-port WebSocket connections. By serving both HTTP and WebSocket on the same port, we ensure Safari compatibility.

### iOS Silent Mode Bypass

See [docs/IOS_SILENT_MODE_FIX.md](docs/IOS_SILENT_MODE_FIX.md) for the technical details on how we bypass iOS's mute switch using MediaStreamDestination.

## 📄 License

MIT License

## 👥 Contributors

- Steven Cymatics - Initial development
- Claude (Anthropic) - Audio engine & debugging

---

**Questions?** Open an issue on GitHub!
