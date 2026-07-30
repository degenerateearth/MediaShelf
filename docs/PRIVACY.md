# Privacy and online artwork

Core library use is offline and does not require an account, API key, or network
connection. MediaShelf has no analytics, telemetry, advertising, crash upload,
or tracking code.

## Automatic artwork

Automatic artwork is a separately switchable enhancement. In this build it uses
the public Cinemeta metadata endpoint. After parsing a filename, MediaShelf sends
only:

- normalized title;
- movie or series type;
- year, when available.

It does not send a file, full path, containing directory, watch history, manual
metadata, or device identifier. Matching images are downloaded once and cached
under `MediaShelf Data/Artwork`, so they remain available offline.

Matching is deliberately strict. The normalized title must be exact; a known
year must also be exact; and multiple exact-title results without a year are
rejected instead of guessed.

Turn “Automatically match posters and backdrops after scanning” off in Settings
for strictly offline operation. A provider outage is silent and never blocks a
scan or app launch.

## Artwork precedence

1. Manually selected or dropped artwork.
2. Artwork stored beside the media (`poster.jpg`, `folder.jpg`, `backdrop.jpg`,
   and related names).
3. Cached optional provider artwork.
4. Generated in-app placeholder.

Provider refreshes never overwrite manual artwork. A manual source image is
copied into portable storage and is no longer required after import.
