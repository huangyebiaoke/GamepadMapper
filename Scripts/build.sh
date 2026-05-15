#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "=== Building GamepadMapper ==="

# Build release
swift build -c release

# Determine build output directory
BUILD_DIR=""
if [ -d ".build/apple/Products/Release" ]; then
    BUILD_DIR=".build/apple/Products/Release"
elif [ -d ".build/arm64-apple-macosx/release" ]; then
    BUILD_DIR=".build/arm64-apple-macosx/release"
elif [ -d ".build/x86_64-apple-macosx/release" ]; then
    BUILD_DIR=".build/x86_64-apple-macosx/release"
else
    echo "Could not find release build directory"
    exit 1
fi

APP_NAME="GamepadMapper"
APP_PATH="build/${APP_NAME}.app"

echo "=== Packaging ${APP_NAME} ==="

# Create .app bundle structure
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

# Copy binary
cp "${BUILD_DIR}/${APP_NAME}" "${APP_PATH}/Contents/MacOS/"

# Copy Info.plist
cp "Config/Info.plist" "${APP_PATH}/Contents/"

# Copy Resources if any
if [ -d "Sources/GamepadMapper/Resources" ]; then
    cp -R Sources/GamepadMapper/Resources/* "${APP_PATH}/Contents/Resources/" 2>/dev/null || true
fi

# Sign (ad-hoc for local use)
codesign --force --deep --sign - \
    --entitlements "GamepadMapper.entitlements" \
    --options runtime \
    "${APP_PATH}"

echo "App bundle created: ${APP_PATH}"

# Create DMG
DMG_NAME="${APP_NAME}.dmg"
DMG_STAGING="build/dmg-staging"

rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"

# Copy app to staging
cp -R "${APP_PATH}" "${DMG_STAGING}/"

# Add Applications symlink
ln -sf /Applications "${DMG_STAGING}/Applications"

# Create DMG
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "build/${DMG_NAME}"

echo "=== Done ==="
echo "App:  ${APP_PATH}"
echo "DMG:  build/${DMG_NAME}"
