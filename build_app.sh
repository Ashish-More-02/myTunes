#!/bin/bash
set -e

APP_NAME="myTunes"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"
ICON_SRC="assets/myTunes_app_image_final.png"
ICONSET="AppIcon.iconset"
ICNS="AppIcon.icns"

cd "$(dirname "$0")"

echo "→ Building release..."
swift build -c release

echo "→ Creating $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/myTunes_app_image_final.png"
fi

if [ -f "$ICON_SRC" ]; then
    echo "→ Generating app icon from $ICON_SRC..."
    rm -rf "$ICONSET" "$ICNS"
    mkdir "$ICONSET"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png"      > /dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"   > /dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png"      > /dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"   > /dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png"    > /dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png"    > /dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png"    > /dev/null
    cp "$ICON_SRC"                 "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" -o "$ICNS"
    rm -rf "$ICONSET"
    cp "$ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    touch "$APP_BUNDLE"
    echo "✓ Icon installed"
else
    echo "⚠ No icon found at $ICON_SRC — skipping"
fi

echo "✓ Built $APP_BUNDLE"
echo "  Run: open $APP_BUNDLE"
