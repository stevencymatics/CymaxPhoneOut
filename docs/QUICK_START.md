# Quick Start Guide

Get up and running in 5 minutes.

## Prerequisites

- Mac running macOS 13+ (Ventura or newer)
- iPhone running iOS 16+
- Both devices on the same WiFi network
- Xcode 15+ installed

## Step 1: Install the Audio Driver (Mac)

```bash
cd "/Users/stevencymatics/Documents/Phone Audio Project"

# Build the driver
xcodebuild -project mac/CymaxPhoneOutDriver/CymaxPhoneOutDriver.xcodeproj \
  -scheme CymaxPhoneOutDriver -configuration Release

# Install it
sudo cp -R build/DerivedData/Build/Products/Release/CymaxPhoneOutDriver.driver \
  /Library/Audio/Plug-Ins/HAL/

# Restart Core Audio
sudo killall coreaudiod
```

## Step 2: Run the iOS App (iPhone)

1. Open `ios/CymaxPhoneReceiver/CymaxPhoneReceiver.xcodeproj` in Xcode
2. Select your iPhone as the target device
3. Click Run (⌘R)
4. On the iPhone, tap **"Start Receiving"**
5. Note the IP address shown (e.g., `192.168.1.201`)

## Step 3: Run the Mac Menubar App

```bash
cd "/Users/stevencymatics/Documents/Phone Audio Project"

# Build and run
xcodebuild -project mac/CymaxPhoneOutMenubar/CymaxPhoneOutMenubar.xcodeproj \
  -scheme CymaxPhoneOutMenubar -configuration Debug

# Run the app
open build/DerivedData/Build/Products/Debug/CymaxPhoneOutMenubar.app
```

Or open the project in Xcode and press ⌘R.

## Step 4: Connect

1. Click the antenna icon in Mac menubar
2. Enter the iPhone's IP address
3. Click **Connect**
4. iPhone should show "Connected to [Your Mac Name]"

## Step 5: Select Audio Output

1. Open **System Settings → Sound → Output**
2. Select **"Cymax Phone Out (MVP)"**
3. Play any audio on your Mac
4. You should hear it on your iPhone! 🎉

## Using with FL Studio

1. Open FL Studio
2. Go to **Options → Audio Settings**
3. Select **"Cymax Phone Out (MVP)"** as output
4. Set buffer to **2048 samples**
5. Set sample rate to **48000 Hz**

## Troubleshooting

### No sound?

```bash
# Check driver is installed
ls /Library/Audio/Plug-Ins/HAL/ | grep Cymax

# Restart Core Audio
sudo killall coreaudiod

# Verify IP file
cat /tmp/cymax_dest_ip.txt
```

### Pops/clicks?

- Switch to **Stable** mode in iOS app
- Increase FL Studio buffer to 2048+
- Make sure WiFi signal is strong

### Driver not showing up?

```bash
# Reinstall driver
sudo rm -rf /Library/Audio/Plug-Ins/HAL/CymaxPhoneOutDriver.driver
sudo cp -R [path-to-driver]/CymaxPhoneOutDriver.driver /Library/Audio/Plug-Ins/HAL/
sudo killall coreaudiod
```

## Tips

- Keep iPhone screen on while streaming (prevents network throttling)
- For best quality, use 5GHz WiFi
- USB tethering (when implemented) will give lower latency

## Need More Help?

See the full [README.md](../README.md) and [DEVELOPMENT_NOTES.md](DEVELOPMENT_NOTES.md).

