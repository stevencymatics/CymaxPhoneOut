# USB Tethering Setup Guide

This guide explains how to set up IP-over-USB between your Mac and iPhone for the Cymax Phone Out system.

## Prerequisites

- iPhone with iOS 16 or later
- Mac with macOS 13 (Ventura) or later
- Lightning or USB-C cable (use an Apple-certified cable for best results)

## Step-by-Step Setup

### 1. Enable Personal Hotspot on iPhone

1. Open **Settings** on your iPhone
2. Tap **Personal Hotspot**
3. Toggle **Allow Others to Join** to ON

> **Note:** You don't need any devices to actually connect to the hotspot over WiFi. We're just using this feature to enable the USB networking interface.

> **Battery Tip:** Personal Hotspot does use more battery. For long sessions, keep your iPhone plugged into a power source.

### 2. Connect via USB

1. Connect your iPhone to your Mac using a Lightning or USB-C cable
2. If prompted on iPhone, tap **Trust** to trust this computer
3. If prompted, enter your iPhone passcode

### 3. Verify the Connection on Mac

1. Open **System Settings** (or System Preferences on older macOS)
2. Go to **Network**
3. You should see **iPhone USB** in the list of network interfaces
4. It should show as **Connected** with a green dot

If you don't see iPhone USB:
- Try a different USB cable
- Try a different USB port
- Restart Personal Hotspot on iPhone
- Restart your Mac

### 4. Find the iPhone's IP Address

The iPhone is assigned an IP address in the USB tethering network. You can find it by:

**Option A: On Mac (Terminal)**
```bash
# Find the network interface
ifconfig | grep -A5 "bridge"
# or
networksetup -listnetworkserviceorder | grep -A1 "iPhone"
```

**Option B: On iPhone**
1. Settings > Personal Hotspot
2. Look for "Shared via USB"
3. Note the IP address range (usually 172.20.10.x)

Typically:
- iPhone IP: 172.20.10.1
- Mac IP: 172.20.10.2 (or similar)

### 5. Test the Connection

From Mac Terminal:
```bash
ping 172.20.10.1
```

You should see responses with ~1-3ms latency:
```
PING 172.20.10.1 (172.20.10.1): 56 data bytes
64 bytes from 172.20.10.1: icmp_seq=0 ttl=64 time=1.234 ms
```

## Troubleshooting

### iPhone USB doesn't appear in Network settings

1. **Check the cable**: Use an Apple-certified Lightning or USB-C cable. Third-party cables sometimes don't support data.

2. **Check trust status**: On iPhone, go to Settings > General > Transfer or Reset iPhone > Reset > Reset Location & Privacy. Then reconnect and trust again.

3. **Restart services**:
   - Turn off Personal Hotspot, wait 5 seconds, turn it back on
   - Disconnect and reconnect the USB cable

4. **Check for driver issues**: Open Terminal and run:
   ```bash
   system_profiler SPUSBDataType | grep -A10 "iPhone"
   ```
   You should see your iPhone listed.

### Connection drops intermittently

1. Use a shorter USB cable if possible
2. Avoid USB hubs; connect directly to your Mac
3. Check for loose cable connections
4. Close apps that might be using significant USB bandwidth

### High ping latency (>10ms)

1. Close other apps on both devices
2. Disable WiFi on iPhone (forces USB-only mode)
3. Check for background downloads/updates

### Personal Hotspot grayed out

1. Ensure your carrier plan supports hotspot
2. Check for carrier settings update: Settings > General > About
3. Reset network settings: Settings > General > Transfer or Reset iPhone > Reset > Reset Network Settings

## Network Details

When USB tethering is active:

| Parameter | Typical Value |
|-----------|---------------|
| iPhone IP | 172.20.10.1 |
| Mac IP | 172.20.10.x |
| Subnet | 255.255.255.240 (/28) |
| Gateway | 172.20.10.1 |
| MTU | 1500 |

The connection uses RNDIS/CDC-ECM protocols over USB, providing a virtual Ethernet interface.

## Security Notes

- USB tethering creates a private network between just your Mac and iPhone
- Traffic does not go through the internet (unlike WiFi hotspot)
- No firewall configuration needed
- The connection is as secure as your USB cable

## Alternative: WiFi Direct (Not Recommended)

While you can use WiFi instead of USB:
- Latency: 5-20ms vs 1-3ms for USB
- Reliability: More variable
- Bandwidth: Limited by WiFi conditions

For real-time audio, USB is strongly recommended.

