#!/bin/bash
#
# build_all.sh
# Builds all components of the Cymax Phone Out MVP
#
# Usage: ./build_all.sh [debug|release]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_CONFIG="${1:-Release}"

echo "=========================================="
echo "  Cymax Phone Out MVP - Build Script"
echo "  Configuration: $BUILD_CONFIG"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    error "xcodebuild not found. Please install Xcode."
    exit 1
fi

echo "Xcode version:"
xcodebuild -version
echo ""

# Build directory
BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

# -----------------------------------
# 1. Build the AudioServerPlugIn
# -----------------------------------
echo ""
echo "Building AudioServerPlugIn (CymaxPhoneOutDriver)..."
echo "-----------------------------------"

DRIVER_PROJECT="$SCRIPT_DIR/mac/CymaxPhoneOutDriver/CymaxPhoneOutDriver.xcodeproj"
DRIVER_BUILD_DIR="$BUILD_DIR/driver"

if [ ! -d "$DRIVER_PROJECT" ]; then
    error "Driver project not found at $DRIVER_PROJECT"
    exit 1
fi

xcodebuild -project "$DRIVER_PROJECT" \
    -scheme CymaxPhoneOutDriver \
    -configuration "$BUILD_CONFIG" \
    -derivedDataPath "$DRIVER_BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|BUILD|Linking)" || true

DRIVER_PATH="$DRIVER_BUILD_DIR/Build/Products/$BUILD_CONFIG/CymaxPhoneOutDriver.driver"

if [ -d "$DRIVER_PATH" ]; then
    success "Driver built: $DRIVER_PATH"
    cp -R "$DRIVER_PATH" "$BUILD_DIR/"
else
    error "Driver build failed. Check the output above."
    exit 1
fi

# -----------------------------------
# 2. Build the macOS Menubar App
# -----------------------------------
echo ""
echo "Building macOS Menubar App..."
echo "-----------------------------------"

MENUBAR_PROJECT="$SCRIPT_DIR/mac/CymaxPhoneOutMenubar/CymaxPhoneOutMenubar.xcodeproj"
MENUBAR_BUILD_DIR="$BUILD_DIR/menubar"

if [ ! -d "$MENUBAR_PROJECT" ]; then
    error "Menubar project not found at $MENUBAR_PROJECT"
    exit 1
fi

xcodebuild -project "$MENUBAR_PROJECT" \
    -scheme CymaxPhoneOutMenubar \
    -configuration "$BUILD_CONFIG" \
    -derivedDataPath "$MENUBAR_BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|BUILD|Linking)" || true

MENUBAR_PATH="$MENUBAR_BUILD_DIR/Build/Products/$BUILD_CONFIG/CymaxPhoneOutMenubar.app"

if [ -d "$MENUBAR_PATH" ]; then
    success "Menubar app built: $MENUBAR_PATH"
    cp -R "$MENUBAR_PATH" "$BUILD_DIR/"
else
    error "Menubar app build failed. Check the output above."
    exit 1
fi

# -----------------------------------
# 3. Build the iOS App
# -----------------------------------
echo ""
echo "Building iOS App (simulator)..."
echo "-----------------------------------"

IOS_PROJECT="$SCRIPT_DIR/ios/CymaxPhoneReceiver/CymaxPhoneReceiver.xcodeproj"
IOS_BUILD_DIR="$BUILD_DIR/ios"

if [ ! -d "$IOS_PROJECT" ]; then
    error "iOS project not found at $IOS_PROJECT"
    exit 1
fi

# Build for simulator first (easier to test without device)
xcodebuild -project "$IOS_PROJECT" \
    -scheme CymaxPhoneReceiver \
    -configuration "$BUILD_CONFIG" \
    -sdk iphonesimulator \
    -derivedDataPath "$IOS_BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|BUILD|Linking)" || true

IOS_SIM_PATH="$IOS_BUILD_DIR/Build/Products/$BUILD_CONFIG-iphonesimulator/CymaxPhoneReceiver.app"

if [ -d "$IOS_SIM_PATH" ]; then
    success "iOS app (simulator) built: $IOS_SIM_PATH"
else
    warn "iOS simulator build may have failed. Check output above."
fi

# Optional: Build for device (requires valid signing)
echo ""
echo "Building iOS App (device)..."
echo "-----------------------------------"
echo "Note: This requires a valid development team in Xcode."

xcodebuild -project "$IOS_PROJECT" \
    -scheme CymaxPhoneReceiver \
    -configuration "$BUILD_CONFIG" \
    -sdk iphoneos \
    -derivedDataPath "$IOS_BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|BUILD|Linking)" || true

IOS_DEVICE_PATH="$IOS_BUILD_DIR/Build/Products/$BUILD_CONFIG-iphoneos/CymaxPhoneReceiver.app"

if [ -d "$IOS_DEVICE_PATH" ]; then
    success "iOS app (device) built: $IOS_DEVICE_PATH"
    cp -R "$IOS_DEVICE_PATH" "$BUILD_DIR/"
else
    warn "iOS device build failed. You may need to configure code signing in Xcode."
fi

# -----------------------------------
# Summary
# -----------------------------------
echo ""
echo "=========================================="
echo "  Build Summary"
echo "=========================================="
echo ""
echo "Build outputs are in: $BUILD_DIR"
echo ""

if [ -d "$BUILD_DIR/CymaxPhoneOutDriver.driver" ]; then
    success "AudioServerPlugIn ready"
fi

if [ -d "$BUILD_DIR/CymaxPhoneOutMenubar.app" ]; then
    success "Menubar app ready"
fi

if [ -d "$BUILD_DIR/CymaxPhoneReceiver.app" ]; then
    success "iOS app ready"
fi

echo ""
echo "Next steps:"
echo "  1. Run ./install_driver.sh to install the audio driver"
echo "  2. Open CymaxPhoneOutMenubar.app"
echo "  3. Install CymaxPhoneReceiver.app on your iPhone"
echo "  4. See README.md for usage instructions"
echo ""



