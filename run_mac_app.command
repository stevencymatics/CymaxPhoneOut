#!/bin/bash
# Quick launcher for Cymax Phone Out Menubar App

# Kill any existing instance
pkill -f CymaxPhoneOutMenubar 2>/dev/null

# Find and launch the app
APP_PATH="/Users/stevencymatics/Library/Developer/Xcode/DerivedData/CymaxPhoneOutMenubar-feolirtedlicufclxmwwuejulzow/Build/Products/Debug/CymaxPhoneOutMenubar.app"

if [ -d "$APP_PATH" ]; then
    echo "Launching Cymax Phone Out..."
    open "$APP_PATH"
    echo "✓ App launched! Look for the antenna icon in your menubar."
else
    echo "App not found at: $APP_PATH"
    echo "Please build the app first in Xcode."
fi
