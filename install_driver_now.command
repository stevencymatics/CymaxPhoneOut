#!/bin/bash
# Install the Cymax audio driver

echo "Installing Cymax Phone Out driver..."
echo "You may need to enter your password."
echo ""

sudo cp -R ~/Library/Developer/Xcode/DerivedData/CymaxPhoneOutDriver-*/Build/Products/Release/CymaxPhoneOutDriver.driver /Library/Audio/Plug-Ins/HAL/

if [ $? -eq 0 ]; then
    echo ""
    echo "Restarting audio system..."
    sudo killall coreaudiod
    echo ""
    echo "✅ Done! Driver installed successfully."
    echo ""
    echo "Now:"
    echo "1. Force quit iPhone app"
    echo "2. Run iPhone app from Xcode"
    echo "3. Connect from Mac menubar"
else
    echo ""
    echo "❌ Failed to install driver"
fi

echo ""
echo "Press any key to close..."
read -n 1


