# MediaShelf for Linux

The Linux preview is a lightweight GTK 3 edition of MediaShelf for Linux Mint
and Ubuntu-family distributions. It indexes local movies and television files,
stores the portable SQLite library beside the selected media folder, and opens
playback in Celluloid. It never moves, renames, rewrites, or uploads media.

## Requirements

- Python 3
- PyGObject with GTK 3 bindings
- Celluloid for playback
- `ffmpegthumbnailer` for optional generated thumbnails

On Linux Mint or Ubuntu:

```sh
sudo apt install python3 python3-gi gir1.2-gtk-3.0 celluloid ffmpegthumbnailer
```

## Run from the repository

```sh
cd linux
sh ./mediashelf
```

Choose a media folder when prompted. MediaShelf creates `MediaShelf Data`
beside that folder and stores its database, thumbnails, backups, settings, and
playback state there.

## Install for the current user

```sh
cd linux
sh ./INSTALL.sh
```

The installer copies the app to `~/.local/opt/mediashelf`, adds a desktop entry
under `~/.local/share/applications`, and installs the icon for the current user.
It does not require root access.

## Supported filenames

Examples include `Alien (1979).mkv`, `Dexter S03E11.mkv`, and
`Vikings 1x04.mp4`. Supported video extensions currently include MP4, MKV,
M4V, MOV, AVI, WebM, MPEG, MPG, and TS.

## Status and limitations

This is an early Linux preview, not yet a packaged release. It uses the system
Celluloid and codec stack, and its interface and feature set do not yet match
the native macOS edition. Test with a copy of your library metadata first and
report issues with sanitized filenames only—never upload personal databases or
copyrighted media.

## Validation

Repository checks compile the Python source, validate both shell scripts, and
validate the desktop entry on Ubuntu. UI, scanning, thumbnail generation, and
playback still require manual testing on a GTK desktop.

MediaShelf is licensed under the repository's [MIT License](../LICENSE).
