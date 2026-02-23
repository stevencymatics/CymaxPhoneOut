# Cymatics Mix Link

Stream system audio from your Mac or PC to your iPhone in real-time over WiFi. **No app install required on your phone** - just scan a QR code and listen.

## What It Does

- Captures all system audio from your Mac (ScreenCaptureKit) or PC (WASAPI loopback)
- No audio output switching required - works with your existing speakers/headphones
- No iPhone app needed - uses your phone's web browser
- QR code connection - scan and play in seconds
- Works with iPhone silent mode - audio plays even when muted
- Lock screen controls - play/pause from iOS lock screen and Control Center
- Safari and Chrome support (HTTP streaming fallback for Safari)
- License verification via Cloudflare Workers - no API keys stored in the app
- Works with any audio source: Apple Music, Spotify, YouTube, FL Studio, Logic Pro, etc.
- ~80-150ms latency over WiFi

## Platforms

| Platform | Framework | Audio Capture | Status |
|----------|-----------|---------------|--------|
| macOS | SwiftUI | ScreenCaptureKit | Complete |
| Windows | .NET 9 / Windows Forms | WASAPI Loopback | Complete |

## Quick Start

### macOS

1. Download `MixLink.dmg` from Releases
2. Open DMG and drag **Mix Link** to Applications
3. **Right-click > Open** (first time only, to bypass Gatekeeper)
4. Grant Screen Recording permission when prompted
5. Scan QR code with your phone

Or build from source:

```bash
cd mac/CymaxPhoneOutMenubar
xcodebuild -scheme CymaxPhoneOutMenubar -configuration Release
```

### Windows

1. Install [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0)
2. Build and publish:

```powershell
cd Windows
dotnet publish src\MixLink.App\MixLink.App.csproj -c Release -r win-x64 --self-contained -o publish
```

3. Run `publish\Cymatics Mix Link.exe`
4. Sign in with your Cymatics account
5. Complete the onboarding steps
6. Scan the QR code with your phone

The Windows app produces a single self-contained `.exe` with no external dependencies.

## Project Structure

```
CymaxPhoneOut/
├── mac/
│   └── CymaxPhoneOutMenubar/           # macOS menubar app (SwiftUI)
│       ├── AppState.swift               # Main app state & audio processing
│       ├── MenuBarView.swift            # Menubar UI with QR code
│       ├── SystemAudioCapture.swift     # ScreenCaptureKit audio capture
│       ├── HTTPServer.swift             # Combined HTTP + WebSocket server
│       ├── WebPlayerHTML.swift          # Embedded web audio player
│       ├── QRCodeGenerator.swift        # QR code generation
│       └── Assets.xcassets/             # App icon
│
├── Windows/
│   └── src/
│       ├── MixLink.App/                 # Windows desktop app (.NET 9 WinForms)
│       │   ├── Program.cs               # Entry point, DPI config
│       │   ├── LoginForm.cs             # Login UI (matches macOS style)
│       │   ├── QrPopupForm.cs           # QR code tray popup
│       │   ├── OnboardingForm.cs        # 3-step onboarding flow
│       │   ├── SubscriptionInactiveForm.cs  # Subscription expired view
│       │   ├── TrayApplication.cs       # System tray icon & lifecycle
│       │   ├── LicenseService.cs        # Cloudflare Worker API client
│       │   ├── MixLinkUi.cs             # Shared UI components & theme
│       │   ├── AppState.cs              # App state management
│       │   └── app.ico                  # Application icon
│       │
│       └── MixLink.Core/               # Core audio & networking library
│           ├── Audio/
│           │   ├── WasapiLoopbackCapture.cs  # WASAPI system audio capture
│           │   └── AudioPacket.cs            # Audio packet format
│           ├── Network/
│           │   ├── HttpWebSocketServer.cs    # HTTP + WebSocket server
│           │   └── WebPlayerHtml.cs          # Embedded phone web player
│           └── Utilities/
│               ├── QrCodeGenerator.cs        # QR code generation
│               └── NetworkUtils.cs           # IP address discovery
│
├── mac/CymaxPhoneOutDriver/             # (Legacy) Virtual audio driver
│
└── docs/
    ├── QUICK_START.md
    ├── IOS_SILENT_MODE_FIX.md
    └── DEVELOPMENT_NOTES.md
```

## Architecture

Both platforms share the same architecture and audio packet format. The phone web player is identical across macOS and Windows.

```
┌─────────────────────────────────────────────────────────────┐
│                    Mac or Windows PC                         │
│                                                              │
│  ┌──────────────┐    ┌─────────────────────────────────┐    │
│  │   Mix Link   │    │  System Audio Capture            │    │
│  │   Desktop    │◄───│  macOS: ScreenCaptureKit         │    │
│  │   App        │    │  Windows: WASAPI Loopback        │    │
│  │              │    │                                   │    │
│  │  - QR Code   │    │  48kHz Stereo Float32            │    │
│  │  - Status    │    └─────────────────────────────────┘    │
│  └──────┬───────┘                                           │
│         │                                                    │
│  ┌──────▼──────────────────────────────────────────────┐    │
│  │          Combined HTTP + WebSocket Server            │    │
│  │                   (Port 19621)                       │    │
│  │                                                      │    │
│  │  - Serves web player HTML                            │    │
│  │  - WebSocket for Chrome (fast)                       │    │
│  │  - HTTP streaming for Safari (fallback)              │    │
│  │  - 128 frames/packet                                 │    │
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
│  │  Chrome: WebSocket ──┐                               │    │
│  │  Safari: HTTP Stream ┼──▶ Circular ──▶ Web Audio     │    │
│  │                      │    Buffer       API           │    │
│  │                      └───────────────────────────────│    │
│  │                                                      │    │
│  │  MediaStreamDestination → <audio> (silent mode fix)  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## License Verification

The Windows app authenticates users through a Cloudflare Worker that acts as a proxy to Shopify and Recharge APIs. No API keys or product IDs are stored in the desktop application.

```
Desktop App  ──POST /verify-license──▶  Cloudflare Worker  ──▶  Shopify API
  (email +                               (KV config store      Recharge API
   password)                              + secret keys)
```

- Product rules and API credentials are stored in Cloudflare KV and Worker secrets
- The desktop app only knows the public worker endpoint URL
- Products can be added or modified server-side without rebuilding the app
- Worker deployed at `license-verification-worker.teamcymatics.workers.dev`

## Audio Packet Format

```
Binary Message (16-byte header + audio data):
┌──────────────────────────────────────────────────────────────┐
│ sequence (4) │ timestamp (4) │ sampleRate (4) │ channels (2) │
├──────────────────────────────────────────────────────────────┤
│ frameCount (2) │           Audio Data (Float32)              │
│                │      (frameCount * channels * 4 bytes)      │
└──────────────────────────────────────────────────────────────┘
```

## Phone Web Player

The embedded web player served to the phone features:

- Cymatics branding with SVG wordmark and "Mix Link" title
- Large play/pause button with cyan-to-teal gradient
- 16-bar audio visualizer with real-time levels
- Connection status indicator with signal strength bars
- Auto-reconnect with spinner overlay
- Media Session API for iOS lock screen controls
- Viewport-locked layout (no scrolling) using `100dvh` and flex distribution
- Safe area support for iPhone notch and home bar

## Configuration

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

## Requirements

### macOS
- macOS 13+ (Ventura) for ScreenCaptureKit
- Xcode 15+ (for building from source)

### Windows
- Windows 10 or later
- .NET 9 SDK (for building from source)

### Phone
- iPhone or iPad with a modern web browser (Chrome or Safari)
- Same WiFi network as the computer

## Windows UI

The Windows app is visually matched to the macOS SwiftUI version:

- Dark theme (RGB 20,20,20 background) with cyan/teal accents
- Custom-drawn Cymatics SVG wordmark
- Rounded input fields and gradient buttons
- macOS-style traffic light close/minimize buttons
- System tray icon with cyan waveform bars
- 3-step onboarding flow (Welcome, Requirements, Ready)
- Subscription-inactive screen with "View Plans" redirect
- DPI-aware rendering via `DpiUnawareGdiScaled` mode

## Troubleshooting

### No Audio
1. **macOS**: Check Screen Recording permission in System Settings > Privacy & Security
2. **Windows**: Ensure system audio is playing (WASAPI captures the default output device)
3. Check the signal strength indicator in the web player

### Safari Won't Connect
Safari uses HTTP streaming fallback. Wait 1-2 seconds for the initial connection. Chrome connects faster via WebSocket.

### Audio Cuts Out
The app auto-reconnects on network interruptions. After 2 failed attempts it shows "No connection found" - check your WiFi connection.

### Windows Login Issues
- Verify your Cymatics account credentials at cymatics.fm
- The app connects to the Cloudflare license server - ensure internet access
- Credentials are cached locally in `%APPDATA%\Cymatics\credentials.json`

## Future Improvements

- [ ] USB tethering for lower latency
- [ ] Volume control in web player
- [ ] Latency display
- [ ] Multiple simultaneous listeners
- [ ] Code signing and notarization (macOS) / signing (Windows)
- [x] ~~Safari support~~ - HTTP streaming fallback
- [x] ~~Silent mode support~~ - MediaStreamDestination bypass
- [x] ~~Lock screen controls~~ - Media Session API
- [x] ~~Windows support~~ - .NET 9 with WASAPI loopback capture
- [x] ~~License verification~~ - Cloudflare Workers with KV config
- [x] ~~Windows UI parity~~ - Custom-drawn WinForms matching SwiftUI design

## Technical Notes

### Why ScreenCaptureKit (macOS)?
Captures all system audio without changing audio output, no driver installation, Apple's recommended approach.

### Why WASAPI Loopback (Windows)?
Captures the system audio output mix directly. No virtual audio driver needed, low latency, built into Windows.

### Why Single Port (19621)?
Safari has restrictions on cross-port WebSocket connections. Serving both HTTP and WebSocket on the same port ensures Safari compatibility.

### iOS Silent Mode Bypass
See [docs/IOS_SILENT_MODE_FIX.md](docs/IOS_SILENT_MODE_FIX.md) for details on bypassing the iOS mute switch using MediaStreamDestination.

## License

MIT License

## Contributors

- Steven Cymatics - Initial development
- Cursor AI - Windows implementation, license server, audio engine & debugging

---

**Questions?** Open an issue on GitHub.
