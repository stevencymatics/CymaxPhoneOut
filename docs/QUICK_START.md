# Quick Start Guide

Get Mix Link running in under 2 minutes!

## Prerequisites

- macOS 13+ (Ventura or later)
- iPhone/iPad with a web browser
- Mac and phone on the same WiFi network

## Step 1: Install the App

### Option A: Pre-Built DMG (Recommended)
1. Download `MixLink.dmg`
2. Open it and drag **Mix Link** to Applications
3. **Right-click → Open** (first time only, to bypass Gatekeeper)

### Option B: Build from Source
```bash
cd mac/CymaxPhoneOutMenubar
xcodebuild -scheme CymaxPhoneOutMenubar -configuration Debug
open ~/Library/Developer/Xcode/DerivedData/CymaxPhoneOutMenubar-*/Build/Products/Debug/"Mix Link.app"
```

## Step 2: Grant Permission

When Mix Link first runs, it will show a permission screen.

1. Click **"Open Settings"**
2. In System Settings, find **"Screen & System Audio Recording"**
3. Click the **+** button and add **Mix Link**
4. Enter your password if prompted
5. Click **"I've enabled it - Restart App"**

> **Why Screen Recording?** This is how macOS allows apps to capture system audio via ScreenCaptureKit. Mix Link only captures audio, not your screen.

## Step 3: Connect Your Phone

1. Look for the **waveform icon** in your Mac's menubar
2. Click it to see the QR code
3. **Scan the QR code** with your iPhone camera
4. Tap the link to open in your browser
5. Tap the **Play** button

## Step 4: Play Audio

Play any audio on your Mac - it will stream to your phone!

- ✅ Apple Music
- ✅ Spotify
- ✅ YouTube
- ✅ FL Studio / Logic Pro
- ✅ Any app that plays audio

## Troubleshooting

### No audio on phone
- Make sure audio is actually playing on your Mac
- Check that the phone's volume is up
- Look at the buffer indicator in the web player

### "Permission Required" keeps showing
1. Make sure you added Mix Link to Screen & System Audio Recording (not just Screen Recording)
2. Click "Restart App" after granting permission
3. macOS requires an app restart to recognize new permissions

### App won't open (security warning)
Right-click the app → Open → Open

### Phone can't connect
- Make sure both devices are on the **same WiFi network**
- Check that no firewall is blocking port 19621
- Try refreshing the page on your phone

### Safari is slow to connect
Safari uses HTTP streaming instead of WebSocket. The first connection may take 1-2 seconds, but once connected it works smoothly. Chrome connects faster if available.

## Tips

- **Silent mode works!** - Audio plays even when iPhone mute switch is on
- **Lock screen controls** - Play/pause from lock screen or Control Center
- **Screen can turn off** - Audio continues playing when phone screen locks
- **Tab switching mutes** - Audio mutes when you switch tabs, unmutes when you return
- **Auto-reconnect** - If connection drops, Mix Link will automatically try to reconnect

## Need More Help?

Check the main [README.md](../README.md) or open an issue on GitHub!
