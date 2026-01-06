# Cymax Phone Out - macOS to iPhone Audio Streaming

Stream system audio from your Mac to your iPhone in real-time over WiFi. **No app install required on your phone** - just scan a QR code and listen!

## 🎯 What It Does

- **Captures ALL system audio** from your Mac using ScreenCaptureKit
- **No audio output switching required** - works with your existing speakers/headphones
- **No iPhone app needed** - uses your phone's web browser
- **QR code connection** - scan and play in seconds
- Works with any audio source: Apple Music, Spotify, YouTube, **FL Studio**, Logic Pro, etc.
- ~200-300ms latency over WiFi

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 🔊 System Audio Capture | Uses macOS ScreenCaptureKit - no need to change audio output |
| 📱 No App Required | Phone uses web browser (Chrome/Safari) |
| 📷 QR Code Setup | Instant connection - just scan and tap play |
| 🎵 48kHz Stereo | High-quality Float32 audio streaming |
| 🔄 Auto-Reconnect | Handles network interruptions gracefully |

## 🚀 Quick Start

### 1. Build & Run the Mac App

```bash
cd mac/CymaxPhoneOutMenubar
xcodebuild -scheme CymaxPhoneOutMenubar -configuration Debug
open ~/Library/Developer/Xcode/DerivedData/CymaxPhoneOutMenubar-*/Build/Products/Debug/CymaxPhoneOutMenubar.app
```

Or open in Xcode and press ⌘R.

### 2. Grant Screen Recording Permission

The first time you run the app, macOS will ask for **Screen Recording** permission (needed to capture system audio). Grant it in System Settings → Privacy & Security → Screen Recording.

### 3. Connect Your Phone

1. Click the 📡 icon in your Mac's menubar
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
│       ├── WebSocketServer.swift   # WebSocket server for streaming
│       ├── HTTPServer.swift        # HTTP server for web player
│       ├── WebPlayerHTML.swift     # Embedded web audio player
│       └── QRCodeGenerator.swift   # QR code generation
│
├── mac/CymaxPhoneOutDriver/       # (Legacy) Virtual audio driver
│   └── ...                         # For FL Studio/DAW direct output
│
└── ios/CymaxPhoneReceiver/        # (Legacy) Native iOS app
    └── ...                         # Alternative to web player
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                          macOS                               │
│                                                              │
│  ┌──────────────┐    ┌─────────────────────────────────┐    │
│  │  Menubar App │    │     ScreenCaptureKit            │    │
│  │   (SwiftUI)  │◄───│  (System Audio Capture)         │    │
│  │              │    │                                  │    │
│  │  - QR Code   │    │  48kHz Stereo Float32           │    │
│  │  - Status    │    │  Non-interleaved → Interleaved  │    │
│  └──────┬───────┘    └─────────────────────────────────┘    │
│         │                                                    │
│  ┌──────▼───────┐    ┌─────────────────────────────────┐    │
│  │ HTTP Server  │    │      WebSocket Server           │    │
│  │  (Port 8080) │    │       (Port 19622)              │    │
│  │              │    │                                  │    │
│  │ Serves web   │    │  Streams audio packets          │    │
│  │ player HTML  │    │  128 frames/packet              │    │
│  └──────────────┘    └──────────────┬──────────────────┘    │
│                                      │                       │
└──────────────────────────────────────┼───────────────────────┘
                                       │ WiFi
                                       ▼
┌─────────────────────────────────────────────────────────────┐
│                         iPhone                               │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Web Browser (Chrome/Safari)             │    │
│  │                                                      │    │
│  │  ┌──────────┐  ┌──────────┐  ┌─────────────────┐   │    │
│  │  │WebSocket │─▶│ Circular │─▶│ ScriptProcessor │   │    │
│  │  │ Client   │  │  Buffer  │  │  (Web Audio)    │   │    │
│  │  └──────────┘  └──────────┘  └────────┬────────┘   │    │
│  │                                        │            │    │
│  │                              ┌─────────▼─────────┐  │    │
│  │                              │   AudioContext    │  │    │
│  │                              │    (48kHz)        │  │    │
│  │                              └───────────────────┘  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Audio Packet Format

```
WebSocket Binary Message (16-byte header + audio data):
┌──────────────────────────────────────────────────────────────┐
│ sequence (4) │ timestamp (4) │ sampleRate (4) │ channels (2) │
├──────────────────────────────────────────────────────────────┤
│ frameCount (2) │           Audio Data (Float32)              │
│                │      (frameCount * channels * 4 bytes)      │
└──────────────────────────────────────────────────────────────┘
```

## 🔧 Requirements

- **macOS 13+ (Ventura)** - for ScreenCaptureKit
- **Xcode 15+**
- **iPhone/iPad** with modern web browser
- **Same WiFi network** for Mac and phone

## ⚙️ Configuration

### Buffer Settings (Web Player)

| Setting | Value | Purpose |
|---------|-------|---------|
| Prebuffer | 200ms | Wait before starting playback |
| Target Buffer | 300ms | Desired buffer level |
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

1. **Check Screen Recording permission** - System Settings → Privacy & Security → Screen Recording
2. **Make sure audio is playing** on your Mac
3. **Check the buffer indicator** in the web player - should show 100-300ms

### Audio Sounds Wrong (Chipmunk/Distorted)

This was caused by ScreenCaptureKit outputting **non-interleaved** audio. Fixed in latest version by converting to interleaved format before sending.

### Connection Issues

1. **Same WiFi network** - Mac and phone must be on same network
2. **Firewall** - Allow incoming connections for the app
3. **Try refreshing** the web page on your phone

### "Connected Phones: 2" but only one phone

Close any extra browser tabs that may have the player open.

## 📦 Distribution (For Testers)

Want to share Cymax Audio with others? Here's the easy way:

### Creating a DMG

```bash
# Create a staging folder
mkdir -p ~/Desktop/CymaxAudio_DMG_Stage
cp -R "/Applications/CymaxPhoneOutMenubar.app" "~/Desktop/CymaxAudio_DMG_Stage/Cymax Audio.app"
ln -s /Applications ~/Desktop/CymaxAudio_DMG_Stage/Applications

# Create DMG
hdiutil create -volname "Cymax Audio" \
    -srcfolder ~/Desktop/CymaxAudio_DMG_Stage \
    -ov -format UDZO \
    ~/Desktop/CymaxAudio.dmg
```

### What Testers Need to Do

1. Download the DMG
2. Open it and drag "Cymax Audio" to Applications
3. **Right-click → Open** (first time only, to bypass Gatekeeper)
4. Grant Screen Recording permission when prompted
5. Scan QR code with phone - done!

## 🔮 Future Improvements

- [ ] USB tethering for lower latency
- [ ] Volume control in web player
- [ ] Latency display
- [ ] Multiple simultaneous listeners
- [ ] Native iOS app option (for background playback)
- [ ] Code signing & notarization for easier distribution

## 📊 Technical Notes

### Why ScreenCaptureKit?

- Captures **all system audio** without changing audio output
- Works alongside your speakers/headphones
- No driver installation required
- Apple's recommended approach for audio capture

### Why Web Audio API?

- **No app install** on iPhone
- Works on any device with a browser
- Easy to update (just refresh the page)
- Cross-platform potential (Android, tablets, etc.)

### Non-Interleaved to Interleaved Conversion

ScreenCaptureKit outputs audio as:
```
[L0, L1, L2, ..., Ln, R0, R1, R2, ..., Rn]  (non-interleaved)
```

We convert to:
```
[L0, R0, L1, R1, L2, R2, ..., Ln, Rn]  (interleaved)
```

This is required because Web Audio API expects interleaved stereo.

## 📄 License

MIT License

## 👥 Contributors

- Steven Cymatics - Initial development
- Claude (Anthropic) - Audio engine & debugging

---

**Questions?** Open an issue on GitHub!
