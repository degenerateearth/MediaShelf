# MediaShelf

MediaShelf is a native Intel macOS application for browsing and playing a local
movie and television library directly from an external drive. It is designed to
feel like a private streaming service without a server, account, subscription,
or mandatory internet connection.

## What works

- Portable SQLite library stored in `MediaShelf Data` beside the app.
- One or more security-scoped library folders.
- Recursive MP4, MKV, M4V, and MOV discovery.
- Movie and `S01E01` / `1x01` television filename parsing.
- TV show, season, and episode grouping.
- One card per TV series; seasons and episodes live inside the series page.
- Continue Watching, Movies, TV Shows, and automatic genre rails in that order.
- Streaming-style home, details, search, sort, and filter interfaces.
- Continue Watching, watched state, recently added, and favorites.
- Manual metadata editing that survives rescans.
- Local, manual, drag-and-drop, cached online, and generated placeholder art.
- Conservative no-key poster/backdrop matching through an optional provider:
  exact normalized title, exact year when known, and no guessing on ambiguity.
- Manual artwork always has priority and is never overwritten.
- Native playback, resume, frequent progress saves, and a configurable 90% watched threshold.
- Xbox controller navigation through Apple's GameController framework, with the
  sidebar hidden by default and available from the B button.
- Automatic next-episode playback when a TV episode finishes.
- Portable database backups before schema migration.
- No media rename, move, rewrite, or deletion paths.

## Requirements

- Intel Mac (`x86_64`)
- macOS 13 or newer
- Xcode 16 or a Swift 5.10-compatible toolchain for source builds

## Build and test

```sh
swift test --arch x86_64
./scripts/build-app.sh
```

The packaged application is written to `dist/MediaShelf.app`. Put the `.app` on
an external drive and launch it there. On first launch MediaShelf creates:

```text
MediaShelf.app
MediaShelf Data/
├── library.sqlite
├── Artwork/
├── Backups/
├── Cache/
├── Playback/
├── Settings/
└── Thumbnails/
```

## Data safety

“Remove from Library” removes index records, not video files. The app contains no
code that deletes, renames, moves, or rewrites media. Manually chosen artwork is
copied into portable storage; its source file is untouched.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Playback](docs/PLAYBACK.md)
- [Portable storage](docs/PORTABILITY.md)
- [Privacy and online artwork](docs/PRIVACY.md)
- [Testing](docs/TESTING.md)
- [Known limitations](docs/KNOWN_LIMITATIONS.md)

## License

MediaShelf source code is available under the MIT License. Artwork and metadata
returned by optional providers remain subject to their respective terms.
