#!/bin/bash
#
# create_dmg.sh
# Creates a styled DMG installer with vertical drag-to-Applications UI
#
# Usage: ./create_dmg.sh [path-to-app]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# App to package
APP_PATH="${1:-$PROJECT_ROOT/build/CymaxPhoneOutMenubar.app}"
APP_NAME="Cymatics Link"
DMG_NAME="CymaticsLink"
DMG_OUTPUT="$PROJECT_ROOT/${DMG_NAME}.dmg"
VOLUME_NAME="$APP_NAME"

# Installer styling - VERTICAL LAYOUT
WINDOW_WIDTH=540
WINDOW_HEIGHT=540
ICON_SIZE=100

# App position (top center)
APP_X=270
APP_Y=90

# Applications position (bottom center)
APPS_X=270
APPS_Y=340

# Hidden files position (far below visible area)
HIDDEN_Y=750

# Background image size
BG_WIDTH=1200
BG_HEIGHT=900

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

success() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; exit 1; }

echo "=========================================="
echo "  Cymatics Link - DMG Installer Creator"
echo "=========================================="
echo ""

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    error "App not found at: $APP_PATH"
fi

# Create temp directory for DMG contents
TEMP_DIR=$(mktemp -d)
DMG_TEMP="$TEMP_DIR/dmg"
mkdir -p "$DMG_TEMP"

echo "Creating DMG contents..."

# Copy app
cp -R "$APP_PATH" "$DMG_TEMP/$APP_NAME.app"
success "Copied app"

# DO NOT create symlink here — we create a Finder alias after mounting
# (symlinks don't show the folder icon reliably on ARM Macs)

# Generate background image
BACKGROUND_DIR="$DMG_TEMP/.background"
mkdir -p "$BACKGROUND_DIR"
BACKGROUND_PATH="$BACKGROUND_DIR/installer_background.png"

echo "Generating installer background..."
/usr/bin/python3 "$SCRIPT_DIR/generate_background.py" "$BACKGROUND_PATH" $BG_WIDTH $BG_HEIGHT $APP_X $APP_Y $APPS_X $APPS_Y $WINDOW_WIDTH $WINDOW_HEIGHT
success "Generated background image"

# Create volume icon from app icon
echo "Creating volume icon..."
APP_ICON_DIR="$PROJECT_ROOT/mac/CymaxPhoneOutMenubar/CymaxPhoneOutMenubar/Assets.xcassets/AppIcon.appiconset"
VOLUME_ICON="$DMG_TEMP/.VolumeIcon.icns"
HAS_VOLUME_ICON=false

if [ -f "$APP_ICON_DIR/icon_1024x1024.png" ]; then
    ICONSET_DIR="$TEMP_DIR/VolumeIcon.iconset"
    mkdir -p "$ICONSET_DIR"

    sips -z 16 16 "$APP_ICON_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_16x16.png" 2>/dev/null
    sips -z 32 32 "$APP_ICON_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_16x16@2x.png" 2>/dev/null
    sips -z 32 32 "$APP_ICON_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_32x32.png" 2>/dev/null
    sips -z 64 64 "$APP_ICON_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_32x32@2x.png" 2>/dev/null
    sips -z 128 128 "$APP_ICON_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_128x128.png" 2>/dev/null
    sips -z 256 256 "$APP_ICON_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_128x128@2x.png" 2>/dev/null
    sips -z 256 256 "$APP_ICON_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_256x256.png" 2>/dev/null
    sips -z 512 512 "$APP_ICON_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_256x256@2x.png" 2>/dev/null
    sips -z 512 512 "$APP_ICON_DIR/icon_1024x1024.png" --out "$ICONSET_DIR/icon_512x512.png" 2>/dev/null
    cp "$APP_ICON_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"

    if iconutil -c icns "$ICONSET_DIR" -o "$VOLUME_ICON" 2>/dev/null; then
        HAS_VOLUME_ICON=true
        success "Created volume icon"
    else
        warn "iconutil failed, skipping volume icon"
    fi
else
    warn "App icon not found, skipping volume icon"
fi

# Remove old DMG if exists
rm -f "$DMG_OUTPUT"
rm -f "${DMG_OUTPUT%.dmg}_temp.dmg"

echo "Creating DMG..."

# Create temporary DMG (read-write)
TEMP_DMG="${DMG_OUTPUT%.dmg}_temp.dmg"
hdiutil create -srcfolder "$DMG_TEMP" -volname "$VOLUME_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size 15m "$TEMP_DMG"
success "Created temporary DMG"

# Mount the temp DMG
echo "Mounting DMG for styling..."
MOUNT_DIR="/Volumes/$VOLUME_NAME"

# Unmount if already mounted
if [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    sleep 1
fi

hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse
success "Mounted DMG"

# Set volume to use custom icon
if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# Create Applications alias using Finder (not symlink!)
# Finder aliases carry icon metadata and work reliably on ARM Macs
echo "Creating Applications alias..."
osascript <<EOF
tell application "Finder"
    set targetFolder to (POSIX file "/Applications") as alias
    set dmgVolume to (POSIX file "$MOUNT_DIR") as alias
    make new alias file at dmgVolume to targetFolder with properties {name:"Applications"}
end tell
EOF
success "Created Applications alias (Finder alias, not symlink)"

# Build the hidden-items positioning block
POSITION_HIDDEN_ITEMS=""
if [ "$HAS_VOLUME_ICON" = true ]; then
    POSITION_HIDDEN_ITEMS="
        try
            set position of item \".VolumeIcon.icns\" of container window to {250, $HIDDEN_Y}
        end try"
fi

# Apply visual styling using AppleScript (run twice for .DS_Store reliability)
echo "Applying visual styling..."
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        delay 1

        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, $((100 + WINDOW_WIDTH)), $((100 + WINDOW_HEIGHT))}

        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to $ICON_SIZE

        try
            set background picture of theViewOptions to file ".background:installer_background.png"
        end try

        set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$APPS_X, $APPS_Y}

        try
            set position of item ".background" of container window to {100, $HIDDEN_Y}
        end try
        $POSITION_HIDDEN_ITEMS

        close
        open

        -- Re-apply to ensure .DS_Store persistence
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, $((100 + WINDOW_WIDTH)), $((100 + WINDOW_HEIGHT))}

        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to $ICON_SIZE

        try
            set background picture of theViewOptions to file ".background:installer_background.png"
        end try

        set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$APPS_X, $APPS_Y}

        try
            set position of item ".background" of container window to {100, $HIDDEN_Y}
        end try
        $POSITION_HIDDEN_ITEMS

        update without registering applications
        delay 5

        close
    end tell
end tell
EOF
success "Applied visual styling"

# Wait for Finder to flush .DS_Store
sleep 3

# Sync and unmount
sync
sleep 1
hdiutil detach "$MOUNT_DIR"
success "Unmounted DMG"

# Convert to compressed read-only DMG
echo "Compressing final DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUTPUT"
success "Created compressed DMG"

# Set custom icon on the DMG file itself
echo "Setting DMG file icon..."
if [ -f "$APP_ICON_DIR/icon_1024x1024.png" ]; then
    osascript -l JavaScript << JXASCRIPT
ObjC.import('AppKit');
var iconPath = '$APP_ICON_DIR/icon_1024x1024.png';
var dmgPath = '$DMG_OUTPUT';
var workspace = \$.NSWorkspace.sharedWorkspace;
var icon = \$.NSImage.alloc.initWithContentsOfFile(iconPath);
if (icon.isNil()) {
    console.log('Failed to load icon');
} else {
    var result = workspace.setIconForFileOptions(icon, dmgPath, 0);
    if (result) {
        console.log('Icon set successfully');
    } else {
        console.log('Failed to set icon');
    }
}
JXASCRIPT
    if [ $? -eq 0 ]; then
        success "Set DMG file icon"
    else
        warn "Could not set DMG file icon"
    fi
fi

# Clean up
rm -f "$TEMP_DMG"
rm -rf "$TEMP_DIR"

# Final info
DMG_SIZE=$(ls -lh "$DMG_OUTPUT" | awk '{print $5}')

echo ""
echo "=========================================="
echo "  DMG Created Successfully!"
echo "=========================================="
echo ""
echo "  Output: $DMG_OUTPUT"
echo "  Size:   $DMG_SIZE"
echo ""
echo "  The installer includes:"
echo "    - $APP_NAME.app (top)"
echo "    - Applications folder alias (bottom)"
echo "    - Downward arrow background"
if [ "$HAS_VOLUME_ICON" = true ]; then
echo "    - Custom volume icon"
fi
echo ""
