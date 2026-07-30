# Playback decision

## Decision

MediaShelf ships its zero-dependency baseline with AVFoundation and keeps a
`MediaShelf Data/Playback` location reserved for an Intel libmpv bundle. libmpv
is the chosen wide-codec production backend because its documented client API is
intended for embedding in other applications and exposes playback, audio-track,
subtitle-track, and timeline properties through one interface.

AVFoundation is retained for MP4, M4V, MOV, H.264, HEVC, and other combinations
supported natively by the current Mac. It integrates cleanly with hardware
decoding, system fullscreen behavior, and the app's SwiftUI controls.

## Why libmpv is not silently bundled

mpv does not publish an official self-contained Intel macOS libmpv framework.
Building a redistributable bundle requires compiling FFmpeg, libass, libplacebo,
and other libraries, then rewriting every dynamic-library install name. The
resulting codec and license configuration must be audited before distribution.
Bundling an arbitrary third-party binary would violate the project's dependency
and data-safety requirements.

The source architecture reserves the portable `Playback` directory and keeps
player state outside the library UI. A vetted Intel libmpv XCFramework can be
added without changing scanning, metadata, artwork, or progress storage.

## Current behavior

- MP4/M4V/MOV supported by macOS play in the built-in player.
- The player supports resume, pause, ±10 second seek, timeline, elapsed and
  remaining time, fullscreen-capable presentation, keyboard/controller actions,
  periodic progress persistence, and watched-state updates.
- Unsupported codecs produce a useful error with Show in Finder and Back.
- Media is opened directly; there is no transcoding.

## Acceptance gate for a bundled libmpv release

1. Build and test as `x86_64` on the target Intel Mac.
2. Verify every bundled dynamic dependency with `otool -L`.
3. Enable VideoToolbox hardware decoding with a safe fallback.
4. Test MKV/H.264, MKV/HEVC, multichannel AC3/EAC3/DTS, embedded SRT/ASS,
   external subtitles, and multiple audio tracks.
5. Expose audio/subtitle selection through the existing player controls.
6. Add all required license notices and source-availability obligations.
7. Codesign the complete application after embedding the libraries.
