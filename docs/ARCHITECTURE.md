# Architecture

MediaShelf separates portable domain logic from the macOS user interface.

```text
SwiftUI application
├── AppState (orchestration)
├── Library, detail, editor, settings, and player views
├── ControllerManager (GameController)
└── AVPlayer session
        │
MediaShelfCore
├── FilenameParser
├── MediaScanner
├── LibraryDatabase (SQLite)
├── ArtworkService
├── MetadataProvider
└── PortablePaths / security bookmarks
        │
MediaShelf Data (beside the .app)
├── library.sqlite
├── Artwork
├── Backups
├── Cache
├── Playback
├── Settings
└── Thumbnails
```

## Important decisions

### Portable data is derived from the application location

When running as an application bundle, `PortablePaths` resolves storage to a
`MediaShelf Data` sibling of `MediaShelf.app`. Nothing relies on `/Applications`,
the external volume name, the current username, or a fixed mount point.

### Media is read-only

The scanner uses resource metadata and indexes file references. It has no media
write, move, rename, or deletion operation. Removing a library folder deletes
database records through a foreign-key cascade; the source folder is untouched.

### SQLite instead of SwiftData

Direct SQLite provides a stable, portable file with explicit migrations, WAL
journaling, indexes, and backup behavior. Database access is actor-isolated.

### Manual choices win

Scanner upserts use conditional SQL to preserve manual metadata and manual
poster/backdrop fields. Provider enrichment only fills missing, non-manual
values.

### Expensive work does not block startup

Startup opens the persisted database immediately. Scans and artwork matching run
as asynchronous activities. Media files are not decoded during normal launch.

## Database version 1

Version 1 stores library roots, media items, user metadata, artwork paths,
favorites, progress, availability, and settings. TV hierarchy is projected from
normalized series title plus season/episode numbers, avoiding duplicate series
records while the matcher is still filename-first.

Schema changes must be migration-aware. Before initialization or a future
migration, the database creates a timestamped backup and retains the newest
three.

## Future extension points

- `MetadataProvider` supports alternate online or local metadata sources.
- A wide-codec player can replace the native player without changing the library.
- The scanner's supported extension set and filename parser are isolated.
- Controller actions map onto the native focus system, so new screens inherit
  controller navigation.
