#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$PROJECT_DIR/dist/MediaShelf.app"
ARCHIVE_PATH="$PROJECT_DIR/dist/MediaShelf-macOS-Intel.zip"
CONTENTS_DIR="$APP_DIR/Contents"
EXECUTABLE="$PROJECT_DIR/.build/x86_64-apple-macosx/release/MediaShelf"
SHADER_SOURCE="$PROJECT_DIR/Vendor/KSPlayer/KSPlayer/Metal/Shaders.metal"
BUILD_TEMP=$(mktemp -d)
trap 'rm -rf "$BUILD_TEMP"' EXIT

cd "$PROJECT_DIR"
swift build -c release --arch x86_64

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$CONTENTS_DIR/Frameworks"
cp "$EXECUTABLE" "$CONTENTS_DIR/MacOS/MediaShelf"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
xcrun -sdk macosx metal -c "$SHADER_SOURCE" -o "$BUILD_TEMP/KSPlayerShaders.air"
xcrun -sdk macosx metallib "$BUILD_TEMP/KSPlayerShaders.air" \
    -o "$CONTENTS_DIR/Resources/KSPlayerShaders.metallib"
cp "$PROJECT_DIR/Vendor/KSPlayer/LICENSE" "$CONTENTS_DIR/Resources/KSPlayer-LICENSE.txt"
cp "$PROJECT_DIR/.build/checkouts/FFmpegKit/LICENSE" "$CONTENTS_DIR/Resources/FFmpegKit-LICENSE.txt"
chmod 755 "$CONTENTS_DIR/MacOS/MediaShelf"

codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
rm -f "$ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE_PATH"
file "$CONTENTS_DIR/MacOS/MediaShelf"
echo "$APP_DIR"
echo "$ARCHIVE_PATH"
