# Windows portable build

The Windows app is an early x64 port that reads and writes the same `MediaShelf
Data/library.sqlite` used by the macOS app. It supports portable scanning,
movies and series grouping, search, filters, favorites, resume/watched state,
direct FFmpeg-backed playback, seeking, and automatic next-episode playback.

## Install and run

Download `MediaShelf.exe` from the `MediaShelf-Windows-x64` artifact produced
by the **Windows portable build** GitHub Actions workflow and place it on the
external drive:

```text
External Drive/
├── MediaShelf.app
├── MediaShelf.exe
├── MediaShelf Data/
└── Movies & TV/
```

Run `MediaShelf.exe`, choose **Add folder**, and select the same media folder
used on the Mac. When the display name matches a library whose Mac path is not
available, MediaShelf reconnects that library ID instead of creating duplicate
records. Windows mappings are stored in
`MediaShelf Data/Settings/windows-library-paths.json`; macOS security bookmarks
remain untouched.

Do not open the same portable database from Windows and macOS simultaneously.
Quit MediaShelf before ejecting the drive.

## Build on Windows

Install the .NET 8 SDK and run:

```powershell
powershell -ExecutionPolicy Bypass -File windows/build-portable.ps1
```

The standalone app is written to `dist/MediaShelf-Windows/MediaShelf.exe`.
It is self-contained: users do not need to install .NET, VLC, or a codec pack.
The executable securely extracts its embedded native playback components into
the current user's temporary application cache when launched.

## Current gaps

- Online automatic artwork matching and the visual match chooser are not yet
  exposed in the Windows UI. Existing portable artwork is displayed.
- Manual metadata/artwork editing and controller navigation need Windows UI.
- Windows ARM64 is not built.
- The binary is unsigned; Windows SmartScreen may warn on first launch.

The compatibility tests intentionally reproduce the Mac filename parser and
stable-ID contract. Schema changes must stay migration-safe for both apps.
