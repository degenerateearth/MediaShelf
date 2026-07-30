# Portable storage

MediaShelf derives its primary data root from the application bundle's parent
directory. If the app is located at:

```text
/Volumes/MEDIA/MediaShelf.app
```

the data root is:

```text
/Volumes/MEDIA/MediaShelf Data
```

The SQLite database, artwork copies, thumbnails, cache, backups, playback
components, and settings therefore travel with the external drive.

## Folder access

The native folder picker stores a security-scoped bookmark and the last-known
path. The scanner resolves the bookmark first and uses the path as a recovery
fallback. A selected root is always presented back to the user; MediaShelf never
requests blanket disk access.

Moving a drive between Macs may invalidate a security-scoped bookmark. macOS can
require the media root to be selected again on the second Mac. The intended
recovery flow is to add/reselect the same root and reconnect indexed records
without deleting portable metadata or progress.

## Mount-point changes

Absolute paths are refreshed during scans. Relative paths are stored for every
file, along with filename, file size, and modification time. No volume name,
`/Volumes` mount suffix, username, or home directory is hard-coded.

## App signing

The local build script applies an ad-hoc signature so the bundle is internally
consistent. Distribution to unrelated Macs should use a Developer ID
Application certificate and notarization. Gatekeeper may otherwise require the
user to confirm opening an application copied from another Mac.
