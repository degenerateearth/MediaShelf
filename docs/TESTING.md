# Testing

## Automated

Run:

```sh
swift test --arch x86_64
```

The current suite covers:

- movie year extraction;
- common release-tag removal;
- `S01E01`, dashed `S02E04`, and `1x03` television formats;
- SQLite ingest;
- manual metadata preservation after rescan;
- playback-progress preservation after rescan.

## Manual release checklist

- Launch the app from outside `/Applications`.
- Add one Movies folder and one TV Shows folder.
- Confirm recursive discovery of MP4, MKV, M4V, and MOV filenames.
- Confirm movie cards and TV show grouping.
- Search by title, episode title, year, and genre.
- Test sort and watched/favorite filters.
- Set and remove poster/backdrop artwork.
- Drop an image onto both artwork regions.
- Remove or move the original artwork source and relaunch.
- Edit metadata, refresh, and confirm edits persist.
- Play a compatible video, quit part-way, and resume.
- Finish 90% and confirm watched state.
- Disconnect a selected external drive and confirm a graceful unavailable state.
- Reconnect at a changed mount point and refresh.
- Pair an Xbox controller and test D-pad/stick, A, B, X, and Menu.
- Disable automatic artwork, disconnect networking, and verify all core flows.
- Move the app and `MediaShelf Data` together to a second Intel Mac.

## Test media

`Test Media` contains a copyright-free directory skeleton and filename fixtures.
Generated media binaries are deliberately ignored by Git. Use
`scripts/generate-test-media.swift` to produce short local clips when exercising
the player.
