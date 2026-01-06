# Quick Start Guide

Get Cymax Audio running in under 2 minutes!

## Prerequisites

- macOS 13+ (Ventura or later)
- iPhone/iPad with a web browser
- Mac and phone on the same WiFi network

## Step 1: Build & Run (Mac)

### Option A: Using Xcode
1. Open `mac/CymaxPhoneOutMenubar/CymaxPhoneOutMenubar.xcodeproj`
2. Press `⌘R` to build and run

### Option B: Command Line
```bash
cd mac/CymaxPhoneOutMenubar
xcodebuild -scheme CymaxPhoneOutMenubar -configuration Debug
open ~/Library/Developer/Xcode/DerivedData/CymaxPhoneOutMenubar-*/Build/Products/Debug/CymaxPhoneOutMenubar.app
```

## Step 2: Grant Permission

When the app first runs, macOS will ask for **Screen Recording** permission.

1. Click "Open System Settings" when prompted
2. Enable the toggle for "Cymax Audio" (or CymaxPhoneOutMenubar)
3. You may need to restart the app after granting permission

> **Why Screen Recording?** This is how macOS allows apps to capture system audio via ScreenCaptureKit.

## Step 3: Connect Your Phone

1. Look for the 📡 icon in your Mac's menubar
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
- Look at the "Buffer" indicator - should show 100-300ms

### "Screen Recording permission required"
1. Open System Settings → Privacy & Security → Screen Recording
2. Find and enable "Cymax Audio" or "CymaxPhoneOutMenubar"
3. Restart the Mac app

### App won't open (security warning)
Right-click the app → Open → Open

### Phone can't connect
- Make sure both devices are on the **same WiFi network**
- Check that no firewall is blocking ports 8080 and 19622
- Try refreshing the page on your phone

## Tips

- **Keep your phone's screen on** while streaming (or audio may pause)
- **Buffer of 150-250ms** is normal and provides smooth playback
- **Close other browser tabs** playing audio on your phone

## Need More Help?

Check the main [README.md](../README.md) or open an issue on GitHub!
