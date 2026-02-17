#!/bin/bash
#
# install_driver.sh
# Installs the Cymax Phone Out AudioServerPlugIn
#
# IMPORTANT: This script requires sudo privileges
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_NAME="CymaxPhoneOutDriver.driver"
DRIVER_SOURCE="$SCRIPT_DIR/build/$DRIVER_NAME"
DRIVER_DEST="/Library/Audio/Plug-Ins/HAL/$DRIVER_NAME"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  Cymax Phone Out Driver - Install"
echo "=========================================="
echo ""

# Check if driver exists
if [ ! -d "$DRIVER_SOURCE" ]; then
    echo -e "${RED}Error: Driver not found at $DRIVER_SOURCE${NC}"
    echo "Please run ./build_all.sh first"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}This script requires sudo privileges to install to /Library/Audio/Plug-Ins/HAL/${NC}"
    echo ""
    exec sudo "$0" "$@"
fi

# Remove existing driver if present
if [ -d "$DRIVER_DEST" ]; then
    echo "Removing existing driver..."
    rm -rf "$DRIVER_DEST"
fi

# Copy new driver
echo "Installing driver to $DRIVER_DEST..."
cp -R "$DRIVER_SOURCE" "$DRIVER_DEST"

# Set permissions
echo "Setting permissions..."
chown -R root:wheel "$DRIVER_DEST"
chmod -R 755 "$DRIVER_DEST"

# Restart coreaudiod
echo ""
echo "Restarting Core Audio daemon..."
echo -e "${YELLOW}Note: This will briefly interrupt all audio on your system.${NC}"
echo ""

launchctl kickstart -k system/com.apple.audio.coreaudiod

# Wait for coreaudiod to restart
sleep 2

# Verify installation
echo ""
echo "Verifying installation..."

# Check if driver is loaded
if system_profiler SPAudioDataType 2>/dev/null | grep -q "Cymax Phone Out"; then
    echo -e "${GREEN}✓ Driver installed successfully!${NC}"
    echo ""
    echo "You should now see 'Cymax Phone Out (MVP)' in:"
    echo "  - System Settings > Sound > Output"
    echo "  - Your DAW's audio device selection"
else
    echo -e "${YELLOW}⚠ Driver installed but not yet visible.${NC}"
    echo ""
    echo "Try one of the following:"
    echo "  1. Wait a few seconds and check System Settings > Sound > Output"
    echo "  2. Log out and log back in"
    echo "  3. Restart your Mac"
    echo ""
    echo "If the driver still doesn't appear, check Console.app for errors"
    echo "related to 'CymaxPhoneOutDriver' or 'coreaudiod'."
fi

echo ""
echo "Driver location: $DRIVER_DEST"
echo ""



