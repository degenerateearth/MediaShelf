# Playback

MediaShelf uses KSPlayer with FFmpegKit for the packaged Intel macOS build. The
required playback components are embedded in `MediaShelf.app`, so another user
does not need to install a codec pack or troubleshoot a separate MKV player.

## Supported experience

- Direct playback of MP4, MKV, M4V, and MOV containers
- Resume from saved progress
- Play/pause and ±10-second seeking
- Timeline scrubbing with elapsed and remaining time
- Hold Xbox LT/RT to rewind or fast-forward
- Automatic progress persistence and watched-state updates
- Automatic next-episode playback for television series
- Controls that fade during playback and remain visible while paused or scrubbing

Actual codec compatibility depends on the codecs enabled by the packaged
FFmpegKit build and the capabilities of the Mac. MediaShelf opens files directly
and does not transcode them or require a media server.

## Packaging checks

Before publishing a release:

1. Build and test as `x86_64` on an Intel Mac.
2. Verify bundled dynamic dependencies with `otool -L`.
3. Test representative MKV/H.264, MKV/HEVC, MP4, audio, and subtitle files.
4. Test timeline scrubbing, progress restoration, and automatic next episode.
5. Include all required third-party license notices.
6. Codesign the complete application after embedding dependencies.
