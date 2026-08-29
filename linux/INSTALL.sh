#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$HOME/.local/opt/mediashelf"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

if ! python3 -c 'import gi; gi.require_version("Gtk", "3.0")' >/dev/null 2>&1; then
    echo "Missing GTK Python support. Install it with:"
    echo "  sudo apt install python3-gi gir1.2-gtk-3.0"
    exit 1
fi

mkdir -p "$APP_DIR" "$DESKTOP_DIR" "$ICON_DIR"
install -m 755 "$HERE/mediashelf" "$HERE/mediashelf.py" "$APP_DIR/"
install -m 644 "$HERE/Resources/AppIcon.png" "$ICON_DIR/mediashelf.png"

sed \
    -e "s|^Exec=.*|Exec=$APP_DIR/mediashelf|" \
    -e "s|^Icon=.*|Icon=mediashelf|" \
    "$HERE/MediaShelf.desktop" > "$DESKTOP_DIR/MediaShelf.desktop"
chmod +x "$DESKTOP_DIR/MediaShelf.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

echo "MediaShelf installed. Open it from the applications menu."
if ! command -v celluloid >/dev/null 2>&1; then
    echo "For video playback, install Celluloid: sudo apt install celluloid"
fi
if ! command -v ffmpegthumbnailer >/dev/null 2>&1; then
    echo "For generated thumbnails, install ffmpegthumbnailer: sudo apt install ffmpegthumbnailer"
fi
