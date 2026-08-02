# Apple Silicon support plan

## Goal and scope

MediaShelf currently publishes an Intel-only macOS application. This plan
describes the work needed to produce:

1. a native Apple Silicon (`arm64`) application; and
2. optionally, a universal application containing `x86_64` and `arm64`.

This document is an implementation plan, not a claim of Apple Silicon release
support. No current Intel release should be replaced until the Apple Silicon
artifact passes native clean-machine playback and portability testing.

## Executive assessment

A native `arm64` build appears **moderately difficult**, not blocked on a
missing architecture in the pinned dependency.

The application source is architecture-neutral, and a diagnostic
`swift build -c debug --arch arm64` completed successfully on the existing Intel
development Mac, producing an arm64 Mach-O executable. FFmpegKit 6.1.4 contains
`macos-arm64_x86_64` slices for every macOS binary target used by its package,
including FFmpeg libraries, codec and subtitle support libraries, MoltenVK,
libplacebo, libsmbclient, and related crypto/font dependencies.

The important remaining blocker is **native Apple Silicon runtime and packaging
validation of the complete playback stack**. A cross-linked executable proves
that the slices exist and link; it does not prove video/audio decode,
VideoToolbox, Metal rendering, subtitles, SMB access, controller focus, signing,
or portable-drive behavior on Apple Silicon.

The safest first release is a separate Apple Silicon archive alongside the
existing Intel archive. A universal build should wait until both native
artifacts are reproducible and pass the same test matrix.

## Current baseline

- `Package.swift` declares `.macOS(.v13)` and Swift tools 5.10.
- `Resources/Info.plist` declares `LSMinimumSystemVersion` 13.0.
- The released app and `scripts/build-app.sh` target `x86_64`.
- The packaged executable is currently a thin x86_64 Mach-O.
- The app bundle's `Frameworks` directory is created but currently empty; the
  pinned FFmpegKit binary frameworks are static archives linked into the final
  executable.
- Metal shaders are compiled into `KSPlayerShaders.metallib` during packaging.
- The final bundle is ad-hoc signed and verified locally.
- There is no checked-in GitHub Actions workflow or automated release pipeline.
- The public asset is named `MediaShelf-macOS-Intel.zip`.

## Explicit x86_64 assumptions

### `scripts/build-app.sh`

- Hard-codes the executable path as
  `.build/x86_64-apple-macosx/release/MediaShelf`.
- Calls `swift build -c release --arch x86_64`.
- Always writes `dist/MediaShelf.app`, which cannot represent simultaneous
  per-architecture staging safely.
- Reports the final executable with `file`, but does not fail if the reported
  architecture is unexpected.

### `README.md`

- Describes Intel Mac as the only supported release platform.
- Links to `MediaShelf-macOS-Intel.zip`.
- Uses `swift test --arch x86_64` in build instructions.

These statements are correct until an Apple Silicon release exists and should
not be changed during Phase 1 experimentation.

### `docs/PLAYBACK.md`

- Describes the packaged playback stack as Intel macOS.
- Requires an x86_64 build in the packaging checklist.

### `docs/TESTING.md`

- Uses `swift test --arch x86_64`.
- Requires moving the portable app and data to a second Intel Mac.

### Current release metadata outside the repository

- Release `v0.1.0` contains the Intel-named ZIP and checksum.
- Existing tags and release assets must remain immutable; new architecture
  artifacts belong in a later release.

## Platform requirement

The `.macOS(.v13)` declaration is not an Intel restriction. macOS 13 runs on
both Intel and Apple Silicon, and the application APIs used by MediaShelf are
available at that deployment target. `LSMinimumSystemVersion` 13.0 agrees with
the package declaration.

Keep macOS 13 as the deployment target unless a specific API or dependency
forces a change. Validate the deployment target in every Mach-O slice; an arm64
build performed on a newer Mac must not silently raise the minimum OS version.

## Swift Package Manager compatibility

MediaShelf's Swift targets contain no explicit architecture checks or assembly.
The following compiled successfully for arm64 during planning:

- `MediaShelfCore`;
- `MediaShelfApp`;
- vendored `KSPlayer` Swift sources;
- the Objective-C `DisplayCriteria` target;
- the FFmpegKit C shim;
- linking of the final MediaShelf executable.

The diagnostic output is `.build/arm64-apple-macosx/debug/MediaShelf`, and
`file`/`lipo -archs` report `arm64`. This result is useful evidence but is not a
release acceptance test because it was produced on an Intel host and was not
executed there.

Swift 6.1 currently emits concurrency and sendability warnings in vendored
KSPlayer. They are not architecture-specific and do not prevent the Swift 5.10
package build, but they are a future toolchain risk if warnings become errors in
a newer language mode.

## FFmpegKit 6.1.4 compatibility

`Package.resolved` pins FFmpegKit 6.1.4 at revision
`c32be9bfb628042737ad3ef622e930c5c7b15954`.

At this revision, all 26 binary XCFramework targets with macOS support declare a
`macos-arm64_x86_64` library. Inspection of the actual binaries confirms both
architectures in the macOS archives. The set includes:

- `Libavcodec`, `Libavdevice`, `Libavfilter`, `Libavformat`, `Libavutil`,
  `Libswresample`, and `Libswscale`;
- MoltenVK, shaderc, lcms2, dav1d, placebo, SRT, and ZVBI;
- FreeType, FriBidi, HarfBuzz, Fontconfig, and libass;
- GMP, Nettle, Hogweed, GnuTLS, SMB client, and Blu-ray support;
- the packaged libmpv archive, although MediaShelf currently consumes the
  FFmpegKit target through KSPlayer rather than linking the libmpv product.

This is strong evidence that no replacement FFmpeg build is required merely to
link arm64. Native testing must still cover:

- H.264 and HEVC in MP4 and MKV;
- AC3/EAC3/DTS and ordinary stereo audio;
- embedded and external subtitles, including SRT and ASS where supported;
- VideoToolbox hardware decode and software fallback;
- Metal presentation and the compiled shader library;
- malformed or unsupported streams and graceful error handling;
- SMB-related code paths if MediaShelf begins exposing them.

Do not update FFmpegKit while adding architecture support unless a demonstrated
arm64 defect requires it. A dependency update would combine architecture,
codec, licensing, and regression risk in one change.

## KSPlayer and vendored components

`Vendor/KSPlayer` is primarily Swift and contains no MediaShelf-controlled
`x86_64` conditional. `DisplayCriteria.m` compiles as ordinary Objective-C, and
the Metal shader source is compiled by the app packaging script. All three
participated in the successful arm64 diagnostic link.

Remaining KSPlayer risks are runtime rather than slice availability:

- VideoToolbox decode selection and fallback;
- audio renderer behavior and channel layouts;
- Metal pixel formats and HDR/color-space paths;
- timing, seeking, and end-of-playback callbacks;
- subtitle rendering and font dependencies;
- Swift concurrency warnings under future toolchains.

Changes to vendored source should be minimal, documented, and tested on both
architectures. Preserve `Vendor/KSPlayer/LICENSE` and the license copy placed in
the app bundle.

## Build-script changes

Phase 1 should parameterize or supplement `scripts/build-app.sh` without
changing its default Intel behavior. A safe design should:

1. accept only an allow-listed architecture (`x86_64` or `arm64`);
2. derive the binary directory with SwiftPM rather than hard-coding it, for
   example with `swift build --show-bin-path` using the same configuration and
   architecture;
3. stage each architecture in a distinct directory such as
   `dist/x86_64/MediaShelf.app` and `dist/arm64/MediaShelf.app`;
4. compile the Metal library during each package build;
5. copy Info.plist, icon, and third-party notices identically;
6. assert the executable architecture with `lipo -archs` before signing;
7. sign the fully assembled bundle last;
8. use deterministic release archive names.

The existing `./scripts/build-app.sh` command must continue to produce the
supported Intel bundle until the release process intentionally changes.

## Test commands

The architecture-specific commands to validate during implementation are:

```sh
swift test --arch x86_64
swift test --arch arm64
swift build -c release --arch x86_64
swift build -c release --arch arm64
```

Run arm64 tests natively on Apple Silicon. A successful cross-compile on Intel
cannot execute the arm64 XCTest bundle and is not a substitute.

For a candidate app:

```sh
file dist/arm64/MediaShelf.app/Contents/MacOS/MediaShelf
lipo -archs dist/arm64/MediaShelf.app/Contents/MacOS/MediaShelf
otool -L dist/arm64/MediaShelf.app/Contents/MacOS/MediaShelf
codesign --verify --deep --strict --verbose=2 dist/arm64/MediaShelf.app
```

Expected native results are exactly `arm64` for the Apple Silicon artifact and
exactly `x86_64` for the Intel artifact. Inspect every bundled Mach-O if future
dependency changes add dynamic frameworks or helpers; checking only the main
executable is insufficient.

## App-bundle packaging and signing

Thin architecture releases can share the same bundle identifier and app data
layout, but should be staged and archived separately. Code signing must happen
after the correct executable, Metal library, resources, and license files are in
place.

For local development, the current ad-hoc signing step can remain. Public
distribution should eventually use a Developer ID Application certificate,
hardened runtime where compatible, notarization, and stapling. Signing identities
and notarization credentials must be supplied through secure local or CI secrets
and never committed.

Verification for a notarized candidate should include:

```sh
codesign -d --verbose=4 MediaShelf.app
codesign --verify --deep --strict --verbose=2 MediaShelf.app
spctl --assess --type execute --verbose=4 MediaShelf.app
```

Notarize the final archive/bundle produced for distribution, not an intermediate
slice that will later be modified.

## GitHub Actions feasibility

Automated compilation and unit tests are feasible, but there is currently no
`.github/workflows` directory. Phase 3 should add a matrix that runs on genuine
Intel and Apple Silicon macOS environments where available. Runner labels and
hardware guarantees change over time and must be confirmed against current
GitHub documentation when the workflow is implemented.

Requirements for CI:

- pin or deliberately select the Xcode version;
- report `uname -m`, `swift --version`, and `xcodebuild -version`;
- cache dependencies only when it does not hide architecture contamination;
- isolate SwiftPM scratch directories per architecture;
- run tests natively for the runner architecture;
- build and inspect the release executable;
- upload unsigned/ad-hoc artifacts for validation first;
- gate Developer ID signing and notarization behind protected secrets and tags;
- retain checksums and third-party license notices with each artifact.

If a native Intel hosted runner is unavailable, retain a trusted Intel Mac or
self-hosted runner for release validation. Rosetta testing on Apple Silicon is a
useful compatibility check but does not replace testing on actual Intel hardware.

## Release naming and structure

Initial architecture-specific assets should remain separate:

```text
MediaShelf-macOS-Intel.zip
MediaShelf-macOS-Apple-Silicon.zip
SHA256SUMS.txt
```

If a universal build is later accepted:

```text
MediaShelf-macOS-Universal.zip
SHA256SUMS.txt
```

Release notes must state supported architecture, minimum macOS version, signing
and notarization status, known codec limitations, and whether the artifact has
passed the clean-machine matrix. Do not overwrite or rename the existing Intel
v0.1.0 asset.

## Universal build strategy and risks

Do not run `lipo` on an `.app` directory or ZIP. A universal bundle requires
combining every corresponding Mach-O binary, while copying identical resources
once, then signing the completed result.

Because the current FFmpegKit dependencies link as static archives into the main
executable, a future process may be able to create the executable with SwiftPM's
multi-architecture support or combine separately linked executables:

```sh
lipo -create \
  path/to/x86_64/MediaShelf \
  path/to/arm64/MediaShelf \
  -output path/to/universal/MediaShelf
lipo -archs path/to/universal/MediaShelf
```

That approach is only acceptable after proving that:

- both thin executables come from the same commit, dependency lock, version,
  compiler family, deployment target, and build settings;
- their exported/load-command structure is compatible;
- all future embedded frameworks, dylibs, helpers, and plug-ins are also
  universal;
- neither slice contains absolute build paths or mismatched rpaths;
- the universal executable launches natively on each architecture;
- the completed bundle is signed after merging.

Risks include silently omitting a slice from a future helper, mismatched minimum
OS load commands, duplicate or incompatible resources, architecture-specific
link behavior, invalidating signatures, and doubling binary size. Separate
thin releases are easier to diagnose and roll back.

For a universal candidate, verify:

```sh
file MediaShelf.app/Contents/MacOS/MediaShelf
lipo -archs MediaShelf.app/Contents/MacOS/MediaShelf
otool -l MediaShelf.app/Contents/MacOS/MediaShelf
otool -L MediaShelf.app/Contents/MacOS/MediaShelf
codesign --verify --deep --strict --verbose=2 MediaShelf.app
```

The main executable must report both `x86_64` and `arm64`.

## Portable storage across architectures

`PortablePaths` derives `MediaShelf Data` from the app bundle's parent directory.
SQLite, artwork, settings, relative paths, and progress are architecture-neutral,
so the same external drive should be usable by Intel and Apple Silicon builds.

The following behaviors still require testing:

- security-scoped bookmarks may become stale when the drive moves to another
  Mac and may require reselecting the media root;
- absolute paths must refresh after mount-point changes while relative identity
  preserves existing records;
- schema changes must be readable in both directions during a mixed-architecture
  rollout;
- manual metadata, artwork, favorites, and progress must survive switching
  architectures;
- users must quit MediaShelf before ejecting the drive;
- two Macs or two app copies must not open the same portable SQLite database
  concurrently through shared storage.

Architecture support must not introduce architecture-specific database fields,
cache keys, stable IDs, or storage roots.

## Clean-machine test matrix

Test release archives after downloading them as a user would, not only from the
build directory.

| Machine | OS | Artifact | Required checks |
|---|---|---|---|
| Intel Mac | macOS 13 | Intel | First launch, folder authorization, scan, MP4/MKV playback, controller, resume, next episode, quit/eject |
| Intel Mac | latest supported macOS | Intel | Full regression and Gatekeeper/signing behavior |
| Apple Silicon Mac | macOS 13 | Apple Silicon | Native launch (`arm64`), same functional and playback suite |
| Apple Silicon Mac | latest supported macOS | Apple Silicon | Full regression, hardware decode, signing/notarization |
| Apple Silicon Mac | latest supported macOS | Intel under Rosetta | Existing Intel fallback remains usable; not a substitute for native testing |
| Intel Mac | macOS 13 or later | Universal | Confirms x86_64 slice selection and full regression |
| Apple Silicon Mac | macOS 13 or later | Universal | Confirms arm64 slice selection and full regression |
| Intel → Apple Silicon | supported OS versions | Same external drive and `MediaShelf Data` | Reselect bookmark if needed; preserve library, artwork, edits, favorites, and progress |
| Apple Silicon → Intel | supported OS versions | Same external drive and `MediaShelf Data` | Confirm backward-compatible schema and mount-path recovery |

At minimum, playback fixtures should cover MP4/H.264, MKV/H.264, MKV/HEVC,
stereo audio, representative multichannel audio, embedded SRT/ASS subtitles,
seeking, completion, and automatic next episode.

## Repository file-by-file impact

| File or area | Expected impact |
|---|---|
| `scripts/build-app.sh` | Parameterize architecture and output/staging path while preserving Intel default; add architecture assertions. |
| `Package.swift` | No architecture change expected; keep `.macOS(.v13)`. Change only if an implementation finding requires target settings. |
| `Package.resolved` | Keep FFmpegKit 6.1.4 pinned initially. Change only for a demonstrated blocker and audit every replacement slice/license. |
| `Resources/Info.plist` | Keep minimum macOS 13; increment release versions normally. No architecture key is required. |
| `Sources/MediaShelfCore/*` | No architecture changes expected. Add portability/migration tests if cross-machine behavior exposes a defect. |
| `Sources/MediaShelfApp/*` | No architecture changes expected outside runtime fixes discovered on native hardware. |
| `Sources/MediaShelfApp/Views/PlayerView.swift` | Validate KSPlayer/FFmpeg option selection, progress, seeking, and end callbacks natively; change only for verified runtime issues. |
| `Vendor/KSPlayer/*` | Avoid broad updates. Patch only reproducible architecture/runtime problems and retain license notices. |
| `scripts/generate-test-media.swift` | Expected to remain architecture-neutral; run on both native development machines. |
| `Tests/MediaShelfCoreTests/*` | Run natively on both architectures; add cross-architecture storage and migration fixtures where possible. |
| `docs/TESTING.md` | Add native Apple Silicon and later universal release checklists when support lands. |
| `docs/PLAYBACK.md` | Document validated Apple Silicon codec/subtitle coverage after testing. |
| `docs/PORTABILITY.md` | Document verified Intel/Apple Silicon drive transfer behavior. |
| `docs/KNOWN_LIMITATIONS.md` | Remove Intel-only limitation only after release acceptance. |
| `README.md` | Add Apple Silicon download and requirements only when a supported artifact is published. |
| `CONTRIBUTING.md` | Update supported development/test matrix as phases land. |
| `.github/workflows/*` | New in Phase 3: native architecture test/build matrix and artifact inspection. |
| Release tooling | Add deterministic per-architecture archives, checksums, optional signing/notarization, and later universal assembly. |

## Phased implementation

### Phase 1: native Apple Silicon development build

1. Add an opt-in arm64 build path without changing Intel defaults.
2. Build and run `swift test --arch arm64` on an Apple Silicon Mac.
3. Package a local ad-hoc-signed arm64 app.
4. Verify the executable and all bundled Mach-O slices.
5. Run generated-media scanning, database, UI, controller, and basic playback
   tests natively.
6. Record KSPlayer/FFmpeg warnings and runtime defects separately.

Acceptance criteria:

- a thin arm64 executable and app bundle build from a clean checkout;
- all unit tests pass natively;
- the app launches without Rosetta;
- generated MP4 and representative MKV fixtures scan and play;
- no Intel release command or artifact changes behavior.

### Phase 2: packaged Apple Silicon release

1. Complete the clean-machine Apple Silicon matrix.
2. Test codec, audio, subtitle, controller, resume, and next-episode paths.
3. Move the same portable drive between Intel and Apple Silicon test Macs.
4. Produce `MediaShelf-macOS-Apple-Silicon.zip` and checksum.
5. Complete signing/notarization work or disclose ad-hoc status clearly.
6. Publish beside, not instead of, the Intel artifact.

Acceptance criteria:

- native arm64 execution is confirmed on macOS 13 and the latest supported OS;
- portable data survives round trips without losing manual choices or progress;
- release archive passes signature, Gatekeeper, architecture, and dependency
  inspection;
- release notes accurately describe verified codecs and limitations.

### Phase 3: automated Intel and Apple Silicon builds

1. Add architecture-appropriate GitHub Actions or trusted self-hosted runners.
2. Pin Xcode/toolchain selection and isolate scratch directories.
3. Run unit tests natively in both jobs.
4. Package thin artifacts and validate architecture/load commands.
5. Upload CI artifacts with checksums and licenses.
6. Add protected tag-only signing/notarization after unsigned CI is reliable.

Acceptance criteria:

- repeated builds from the same commit produce correctly named thin artifacts;
- both native test jobs pass;
- architecture inspection fails the workflow on a wrong or missing slice;
- secrets cannot run on untrusted pull-request code.

### Phase 4: universal build, only if safe

1. Compare native thin build settings and Mach-O load commands.
2. Prototype universal assembly in a separate staging directory.
3. Verify every Mach-O and resource, then sign the final bundle.
4. Run the universal artifact on native Intel and Apple Silicon hardware.
5. Compare size, startup, playback, and operational complexity against separate
   downloads.
6. Publish universal only if it is as reliable and supportable as thin builds.

Acceptance criteria:

- every Mach-O that must be universal contains both slices;
- native slice selection is confirmed on both machine families;
- the full clean-machine and portable-drive matrix passes;
- signing/notarization remains valid after universal assembly;
- thin artifacts remain available for diagnosis and fallback during rollout.

## Unresolved questions

- Does KSPlayer choose identical decode paths and hardware acceleration on native
  Apple Silicon for all target codecs?
- Do FFmpegKit's arm64 SMB, GnuTLS, subtitle, font, Metal, and color-management
  paths behave correctly at runtime?
- Are the current Swift concurrency warnings compatible with the Xcode version
  selected for the first Apple Silicon release?
- Which current GitHub-hosted runner labels guarantee native Intel and native
  Apple Silicon hardware when Phase 3 begins?
- Will release distribution remain ad-hoc signed, or will Developer ID signing
  and notarization be completed first?
- Is universal distribution worth its larger archive and more complex assembly,
  or are two thin downloads clearer and safer?
- Should Rosetta remain a documented fallback after a native build exists?
- What exact codec/audio/subtitle fixture set can be legally redistributed or
  generated for repeatable release testing?
- Can mixed-version Intel and Apple Silicon builds ever touch the same portable
  database, and what forward/backward schema policy is required if they can?

## Recommendation

Implement **Phase 1 only** next: parameterize the package script while keeping
the Intel command unchanged, then package and run a thin arm64 build on a real
Apple Silicon Mac. The dependency slices and successful arm64 link make this a
reasonable next step, but native playback and portable-drive evidence should be
required before advertising support.

Keep Intel and Apple Silicon releases separate through Phases 2 and 3. Revisit a
universal app only after both thin builds are automated, signed consistently,
and independently proven on clean hardware.
