#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/appimage}"
APPDIR="$BUILD_DIR/MediaShelf.AppDir"
TOOLS="$BUILD_DIR/tools"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
PYTHON_VERSION="$(python3 -c 'import sys; print(f"python{sys.version_info.major}.{sys.version_info.minor}")')"
ARCH="$(uname -m)"

if [[ "$ARCH" != "x86_64" ]]; then
    echo "AppImage packaging currently supports x86_64; detected $ARCH" >&2
    exit 2
fi

rm -rf "$APPDIR" "$TOOLS"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib/$PYTHON_VERSION/dist-packages" \
    "$APPDIR/usr/share/mediashelf" "$APPDIR/usr/share/applications" \
    "$APPDIR/usr/share/icons/hicolor/512x512/apps" "$APPDIR/usr/share/metainfo" \
    "$TOOLS" "$OUTPUT_DIR"

install -m 0755 /usr/bin/python3 "$APPDIR/usr/bin/python3"
cp -a "/usr/lib/$PYTHON_VERSION" "$APPDIR/usr/lib/"
rm -rf "$APPDIR/usr/lib/$PYTHON_VERSION/dist-packages"
mkdir -p "$APPDIR/usr/lib/$PYTHON_VERSION/dist-packages"
cp -a /usr/lib/python3/dist-packages/gi "$APPDIR/usr/lib/$PYTHON_VERSION/dist-packages/"
install -m 0644 "$ROOT/linux/mediashelf.py" "$APPDIR/usr/share/mediashelf/mediashelf.py"
install -m 0644 "$ROOT/linux/MediaShelf.desktop" "$APPDIR/usr/share/applications/MediaShelf.desktop"
convert "$ROOT/linux/Resources/AppIcon.png" -resize 512x512 \
    "$APPDIR/usr/share/icons/hicolor/512x512/apps/mediashelf.png"
install -m 0644 "$ROOT/linux/appimage/earth.degenerate.MediaShelf.metainfo.xml" "$APPDIR/usr/share/metainfo/earth.degenerate.MediaShelf.metainfo.xml"
cp "$ROOT/linux/MediaShelf.desktop" "$APPDIR/MediaShelf.desktop"
cp "$APPDIR/usr/share/icons/hicolor/512x512/apps/mediashelf.png" "$APPDIR/mediashelf.png"

curl --fail --location --retry 3 --output "$TOOLS/linuxdeploy-x86_64.AppImage" \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
curl --fail --location --retry 3 --output "$TOOLS/linuxdeploy-plugin-gtk.sh" \
    https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
curl --fail --location --retry 3 --output "$TOOLS/appimagetool-x86_64.AppImage" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x "$TOOLS"/*

GI_EXTENSION="$(find "$APPDIR/usr/lib/$PYTHON_VERSION/dist-packages/gi" -maxdepth 1 -name '_gi*.so' -print -quit)"
test -n "$GI_EXTENSION" || { echo "PyGObject extension was not found" >&2; exit 3; }
export APPIMAGE_EXTRACT_AND_RUN=1 DEPLOY_GTK_VERSION=3
"$TOOLS/linuxdeploy-x86_64.AppImage" --appdir "$APPDIR" \
    --executable "$APPDIR/usr/bin/python3" --library "$GI_EXTENSION" \
    --desktop-file "$APPDIR/usr/share/applications/MediaShelf.desktop" \
    --icon-file "$APPDIR/usr/share/icons/hicolor/512x512/apps/mediashelf.png" --plugin gtk

sed "s/@PYTHON_VERSION@/$PYTHON_VERSION/g" "$ROOT/linux/appimage/AppRun" > "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always --dirty)}"
OUTPUT="$OUTPUT_DIR/MediaShelf-${VERSION}-x86_64.AppImage"
rm -f "$OUTPUT"
ARCH=x86_64 VERSION="$VERSION" APPIMAGE_EXTRACT_AND_RUN=1 \
    "$TOOLS/appimagetool-x86_64.AppImage" "$APPDIR" "$OUTPUT"
chmod +x "$OUTPUT"
echo "$OUTPUT"
