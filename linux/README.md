# MediaShelf for Linux

The Linux preview is a lightweight GTK 3 edition of MediaShelf for Linux Mint
and Ubuntu-family distributions. It indexes local movies and television files,
stores the portable SQLite library beside the selected media folder, and opens
playback in Celluloid, mpv, or VLC. It never moves, renames, rewrites, or
uploads media.

The GTK edition includes the same core library workflow as the macOS app:
home shelves, Continue Watching, movie and series browsing, watched and
favorite filters, sorting and search, episode lists, metadata editing, manual
poster/backdrop artwork, folder management, and optional Cinemeta matching.

## Requirements

- Python 3
- PyGObject with GTK 3 bindings
- Celluloid, mpv, or VLC for playback
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

## Portable AppImage

Download `MediaShelf-*-x86_64.AppImage` from the repository's **Releases** page,
then make it executable and open it:

```sh
chmod +x MediaShelf-*-x86_64.AppImage
./MediaShelf-*-x86_64.AppImage
```

The AppImage bundles MediaShelf, Python, GTK 3, and their runtime libraries, so
it does not need to be installed. Media and `MediaShelf Data` remain on your
drive. Playback prefers Celluloid, then mpv, then VLC when installed on the
host.

The current AppImage targets 64-bit Intel/AMD Ubuntu 22.04 or newer. It is not
currently built for ARM devices.

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

## Platform differences

The AppImage bundles the application runtime but uses the host video player and
codec stack. The macOS app has an embedded FFmpeg player and native gamepad
navigation; Linux delegates playback to Celluloid/mpv/VLC and therefore cannot
yet capture continuous playback progress with the same precision. All library,
artwork, filtering, metadata, episode, and portable-data workflows are present.

## Validation

Repository checks compile the Python source, validate the shell and desktop
files, build the AppImage on Ubuntu 22.04, inspect its bundled runtime, and
smoke-test GTK startup under a virtual display. Scanning, thumbnail generation,
and playback still require a final manual test on a real GTK desktop.

MediaShelf is licensed under the repository's [MIT License](../LICENSE).
