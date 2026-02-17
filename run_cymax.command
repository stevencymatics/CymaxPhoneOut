#!/bin/bash
# Run Cymax Audio - Stream Mac audio to your phone
pkill -f CymaxPhoneOutMenubar 2>/dev/null
sleep 0.5
open ~/Library/Developer/Xcode/DerivedData/CymaxPhoneOutMenubar-*/Build/Products/Debug/CymaxPhoneOutMenubar.app
echo "✓ Cymax Audio launched! Look for waveform icon in menubar."



