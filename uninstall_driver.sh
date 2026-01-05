#!/bin/bash
#
# uninstall_driver.sh
# Removes the Cymax Phone Out AudioServerPlugIn
#

set -e

DRIVER_NAME="CymaxPhoneOutDriver.driver"
DRIVER_PATH="/Library/Audio/Plug-Ins/HAL/$DRIVER_NAME"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  Cymax Phone Out Driver - Uninstall"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}This script requires sudo privileges.${NC}"
    echo ""
    exec sudo "$0" "$@"
fi

# Check if driver exists
if [ ! -d "$DRIVER_PATH" ]; then
    echo -e "${YELLOW}Driver not found at $DRIVER_PATH${NC}"
    echo "Nothing to uninstall."
    exit 0
fi

# Remove driver
echo "Removing driver from $DRIVER_PATH..."
rm -rf "$DRIVER_PATH"

# Restart coreaudiod
echo ""
echo "Restarting Core Audio daemon..."
launchctl kickstart -k system/com.apple.audio.coreaudiod

sleep 2

echo ""
echo -e "${GREEN}✓ Driver uninstalled successfully!${NC}"
echo ""
echo "The 'Cymax Phone Out (MVP)' device has been removed."
echo ""


