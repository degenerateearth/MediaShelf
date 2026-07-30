# Known limitations

- The packaged baseline uses AVFoundation. MKV and advanced audio/subtitle
  combinations depend on a vetted Intel libmpv bundle that is not included.
- Automatic artwork relies on an optional third-party endpoint and therefore
  requires internet access while matching. Cached results work offline.
- Automatic matching is conservative but not infallible. The year is used when
  present, and every match can be replaced manually.
- Security-scoped bookmarks can require reauthorization after moving an external
  drive to another Mac.
- Embedded artwork extraction and video-frame thumbnail generation are reserved
  for the libmpv/FFmpeg integration.
- Controller navigation follows native focus movement. Highly unusual custom
  controller mappings are not exposed in version 1.
- The local build is ad-hoc signed. Public distribution requires Developer ID
  signing and Apple notarization.
