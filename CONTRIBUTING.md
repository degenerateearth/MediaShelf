# Contributing to MediaShelf

Thank you for helping make MediaShelf a safer, more polished way to browse and
play a local media library. Useful contributions include focused bug fixes,
tests, documentation, accessibility improvements, packaging work, playback and
subtitle compatibility, performance improvements, and carefully scoped platform
research.

MediaShelf handles personal libraries and portable watch history. Reliability
and data safety matter more than adding a feature quickly. Please discuss major
architectural changes in a GitHub issue before implementing them.

## Current platform and tools

The supported release target is currently:

- Intel Mac (`x86_64`)
- macOS 13 or newer

Apple Silicon, Windows, and Linux are not currently supported release platforms. See
[`docs/APPLE_SILICON_PLAN.md`](docs/APPLE_SILICON_PLAN.md) for the staged Apple
Silicon plan. The Windows and Linux directories contain preview implementations
with their own validation workflows and documentation.

Development uses Swift Package Manager; there is no checked-in Xcode project.
You need:

- an Intel Mac for supported release validation;
- macOS 13 or newer;
- Xcode 16 or a Swift 5.10-compatible toolchain;
- the full Xcode toolchain, including `xcrun`, the macOS SDK, Metal compiler,
  and `metallib`, to package the app;
- Git.

Swift Package Manager resolves the pinned FFmpegKit 6.1.4 dependency from
`Package.resolved`. The KSPlayer source used by MediaShelf is vendored under
`Vendor/KSPlayer`.

## Set up the repository

Fork the repository on GitHub, then clone your fork:

```sh
git clone https://github.com/YOUR-USER/MediaShelf.git
cd MediaShelf
git remote add upstream https://github.com/degenerateearth/MediaShelf.git
```

The first Swift build or test run downloads the pinned FFmpegKit package and its
binary targets. No separate codec pack is required.

Run the supported test suite:

```sh
swift test --arch x86_64
```

Create the packaged application with the repository script:

```sh
./scripts/build-app.sh
```

The script performs a release build for `x86_64`, compiles
`Vendor/KSPlayer/KSPlayer/Metal/Shaders.metal`, copies the app icon and third-party
license files, applies an ad-hoc signature, verifies that signature, and writes:

```text
dist/MediaShelf.app
```

Warnings emitted from the vendored playback code should not be ignored in a
pull request description, but they are currently present in otherwise successful
builds. New warnings introduced by a contribution should be fixed.

## Run the tests

The tests live in `Tests/MediaShelfCoreTests` and currently cover:

- movie and television filename parsing;
- rejection of season packs as movies;
- recursive scanning and local artwork discovery;
- database ingest and preservation of manual metadata and progress;
- one-series Continue Watching behavior;
- strict, year-aware, ambiguity-safe metadata matching and known title aliases.

Run all tests before opening a pull request:

```sh
swift test --arch x86_64
```

Add or update tests when changing parsing, scanning, database behavior,
metadata selection, or Continue Watching logic. UI, controller, and playback
changes also require the relevant manual checks from
[`docs/TESTING.md`](docs/TESTING.md).

## Create a small test library

The repository contains a `Test Media` directory skeleton, but generated video
binaries are intentionally ignored by Git. From the repository root, create
four short, copyright-free H.264 clips with:

```sh
swift scripts/generate-test-media.swift
```

This produces movie and episodic filename fixtures under `Test Media/Movies`
and `Test Media/TV Shows`. Add those two folders through MediaShelf when testing
scanning, grouping, playback, resume, and next-episode behavior.

You may instead use short files that you created yourself or are legally
allowed to use. Keep the test set small and include representative filename and
container patterns. Generated clips and personal media must remain untracked.

## Protect private and copyrighted data

Never commit, upload, or paste into an issue or pull request:

- copyrighted movie or television files;
- personal `library.sqlite` databases or SQLite WAL/SHM files;
- API keys, credentials, cookies, tokens, or security-scoped bookmarks;
- cached or provider-downloaded artwork without permission to redistribute it;
- private absolute paths, usernames, volume names, or other identifying data;
- crash reports or logs before reviewing and redacting them.

Use generated fixtures, sanitized filenames, and properly licensed artwork in
tests and screenshots. Do not attach an entire `MediaShelf Data` directory to a
bug report.

## Contribution workflow

1. Fork the repository and sync your fork with `upstream/main`.
2. Create a focused branch, such as `fix/episode-order` or
   `docs/controller-testing`.
3. Make a narrowly scoped change. Avoid unrelated formatting or generated-code
   churn.
4. Add or update tests when behavior changes.
5. Run `swift test --arch x86_64` and the relevant manual checks.
6. Update README or `docs/` content when user-visible behavior, requirements,
   privacy, portability, or packaging changes.
7. Review the complete diff for private data, media files, caches, and accidental
   build outputs.
8. Open a pull request describing the problem, approach, safety impact, and
   validation performed.

### Commits

- Keep commits focused and reviewable.
- Use an imperative subject that explains the result, for example
  `Preserve manual episode titles during rescans`.
- Do not combine dependency updates, broad refactors, and user-facing behavior
  changes without a clear reason.
- Do not commit `.build`, `dist`, `MediaShelf Data`, generated test videos,
  local databases, caches, or temporary screenshots.

### Pull requests

A pull request should include:

- the user-visible problem or contributor goal;
- the root cause when fixing a bug;
- a concise explanation of the implementation;
- tests and manual scenarios run;
- database, portability, artwork, privacy, controller, or playback impact;
- screenshots for meaningful UI changes, using generated or licensed content;
- remaining limitations or follow-up work.

Keep pull requests small enough to review confidently. Large architectural,
database, playback-engine, dependency, or cross-platform changes should begin
with a GitHub issue and an agreed implementation plan.

## Report a bug

Search existing issues first. A useful report contains:

- MediaShelf release or source commit;
- Mac model, CPU architecture, and macOS version;
- whether the app ran from an internal or external volume;
- exact reproduction steps, expected behavior, and actual behavior;
- a sanitized example of the filename and directory pattern;
- container and codec details when the problem is playback-related, if known;
- whether the issue reproduces with generated test media;
- controller model and connection method for navigation problems;
- relevant, redacted application or crash-log excerpts.

For data or scanning problems, say whether the library was rescanned, the drive
mount point changed, or a security-scoped folder was reselected. For artwork
problems, include the parsed title, year, media kind, and whether the result was
automatic or manually selected. Never attach the personal database or media
file unless you have created a minimal, redistributable fixture specifically for
the report.

## Architecture and coding principles

MediaShelf deliberately separates the native SwiftUI application from portable
domain logic:

- `Sources/MediaShelfCore` owns parsing, scanning, SQLite access, metadata,
  artwork storage, models, and portable paths.
- `Sources/MediaShelfApp` owns orchestration, SwiftUI, AppKit integration,
  controller input, and playback presentation.
- `LibraryDatabase` is actor-isolated; preserve that serialization boundary.
- scanning and online artwork work remain asynchronous so persisted data can
  load without blocking launch;
- TV library surfaces are series-first; individual episodes belong in season
  pickers and playback-specific contexts;
- manual user choices take precedence over scanner and provider output;
- metadata automation must prefer no match over an uncertain match;
- core library use must remain functional without an account, server, or
  network connection.

Prefer changes at the narrowest existing boundary. Parsing belongs in
`FilenameParser`, file discovery in `MediaScanner`, persistence in
`LibraryDatabase`, provider selection in `MetadataProvider`, and controller
mapping in `ControllerManager`.

## Data-safety requirements

These requirements are non-negotiable:

- Never delete, move, rename, rewrite, transcode, or otherwise modify a user's
  original media files.
- “Remove from Library” behavior must affect index records only.
- Preserve portable database compatibility and the `MediaShelf Data` layout.
- Preserve playback progress, favorites, manual metadata, and manual artwork
  through rescans and upgrades.
- Make database schema changes explicit, versioned, migration-safe, and covered
  by upgrade tests. Keep the pre-migration backup behavior intact.
- Retain relative paths and mount-point recovery behavior when changing scanner
  identity or portable storage.
- Never silently select an uncertain artwork or metadata result. Exact title,
  media kind, year, and ambiguity rules must remain conservative.
- Restrict file deletion to MediaShelf-owned caches or copied artwork, and
  resolve and verify those targets before deletion.

Any pull request touching scanning, stable IDs, migrations, or artwork
precedence must explain how existing portable libraries were protected.

## UI and controller expectations

MediaShelf is designed for both desktop and couch use. User-interface changes
should:

- preserve a polished native macOS experience and clear focus states;
- support keyboard and pointer input without weakening controller navigation;
- keep the sidebar closed by default and reachable through the established back
  flow;
- ensure focused off-screen content scrolls into view;
- expose primary buttons, details, episode selection, and playback controls to
  focus navigation;
- retain A/select, B/back, X/play-pause, Menu, D-pad/stick, and LT/RT behavior;
- keep playback controls visible while paused or scrubbing and allow them to
  fade during active playback;
- consider VoiceOver labels, contrast, reduced motion, Dynamic Type where
  applicable, and non-color status cues.

Controller changes require testing with a real controller through Apple's
GameController framework, not only simulated keyboard focus.

## Dependencies and licenses

Avoid new dependencies when Foundation, AppKit, SwiftUI, or an existing project
component can do the job clearly. A dependency proposal should explain:

- the capability it provides and why it belongs in the app;
- maintenance health and supported macOS architectures;
- binary size, startup, privacy, and offline impact;
- license terms and redistribution obligations;
- how it will be pinned, updated, tested, packaged, and signed.

Do not replace or update FFmpegKit or vendored KSPlayer as an incidental part of
another change. Playback dependencies contain native binary targets and license
obligations. Preserve applicable notices, and update packaging so every required
license ships in `MediaShelf.app`.

## AI-assisted contributions

AI-assisted development is allowed. Contributors are still responsible for:

- understanding every submitted change;
- reviewing the full diff for correctness, privacy, and data safety;
- running and reporting relevant tests;
- manually verifying generated UI, controller, playback, and migration changes;
- explaining the implementation in their own pull request.

Do not submit large generated refactors, tests, documentation, or dependency
changes that have not been manually reviewed and verified. “An AI tool produced
it” is not a substitute for reasoning, validation, or maintainership.

## Especially welcome contributions

- focused bug fixes;
- regression and edge-case tests;
- documentation improvements;
- accessibility improvements;
- Apple Silicon enablement following the staged plan;
- signing, notarization, and reproducible packaging improvements;
- codec, audio-track, and subtitle compatibility;
- scanning, artwork, database, and large-library performance work;
- narrowly scoped research toward a possible future Windows port.
- focused fixes and validation for the Linux GTK preview.

A Windows port is exploratory work, not a currently supported target. Begin with
an issue that separates reusable `MediaShelfCore` concepts from macOS-specific
AppKit, SwiftUI, GameController, security-bookmark, and playback behavior.
