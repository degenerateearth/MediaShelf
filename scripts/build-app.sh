#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$PROJECT_DIR/dist/MediaShelf.app"
CONTENTS_DIR="$APP_DIR/Contents"
EXECUTABLE="$PROJECT_DIR/.build/x86_64-apple-macosx/release/MediaShelf"

cd "$PROJECT_DIR"
swift build -c release --arch x86_64

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$CONTENTS_DIR/Frameworks"
cp "$EXECUTABLE" "$CONTENTS_DIR/MacOS/MediaShelf"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
chmod 755 "$CONTENTS_DIR/MacOS/MediaShelf"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
file "$CONTENTS_DIR/MacOS/MediaShelf"
echo "$APP_DIR"
