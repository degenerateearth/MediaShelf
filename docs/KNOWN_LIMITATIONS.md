# Known limitations

- Playback supports common MP4, MKV, M4V, and MOV media through the packaged
  KSPlayer/FFmpegKit stack, but unusual codec, audio, or subtitle combinations
  may still be unsupported.
- Automatic artwork relies on an optional third-party endpoint and therefore
  requires internet access while matching. Cached results work offline.
- Automatic matching is conservative but not infallible. The year is used when
  present, and every match can be replaced manually.
- Security-scoped bookmarks can require reauthorization after moving an external
  drive to another Mac.
- Embedded artwork extraction and video-frame thumbnail generation are not yet
  part of the library scan.
- Controller navigation follows native focus movement. Highly unusual custom
  controller mappings are not exposed in version 1.
- The local build is ad-hoc signed. Public distribution requires Developer ID
  signing and Apple notarization.
