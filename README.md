# Mememaid

Sort a folder of images into its own subfolders, by dragging them off a
filmstrip and dropping them on a folder tile.

Point it at a folder. The loose images in that folder fill the carousel across
the top; its subfolders become the grid below. Drag an image down onto a
folder to queue it, keep going, then hit **Apply** and everything moves at
once.

Nothing moves until Apply. Until then a queued image keeps a badge naming its
destination — tap the badge, or tap the folder tile, to take it back out.

## How it works

- **Drag down, swipe sideways.** The filmstrip scrolls horizontally and the
  drag goes vertically, so each card's `Draggable` carries
  `affinity: Axis.vertical` and competes only for vertical drags. Without
  that, the two gesture recognisers fight and the strip won't scroll.
- **Collisions rename, never overwrite.** If `cat.jpg` is already in the
  destination, the incoming one lands as `cat (1).jpg`. Two source files that
  share a basename in the same batch get distinct names too, and the match is
  case-insensitive because the sdcard filesystem Android presents is.
- **A failed move doesn't strand the batch.** Each file is moved on its own;
  failures are counted and reported, the rest still get filed.
- **Moves, not copies.** `rename()` where possible, falling back to copy+delete
  across filesystems (internal storage → SD card returns `EXDEV`).

## Permissions

Mememaid asks for Android's **All files access**
(`MANAGE_EXTERNAL_STORAGE`). It moves files between folders you pick,
including ones it didn't create, which the Storage Access Framework can't
express without a separate tree grant per folder. Nothing leaves the device.

That permission is Play-Store-restricted — this app is sideloaded via
Obtainium and never published there, so the restriction doesn't apply. The
grant happens on a system Settings screen, so the app re-checks on resume.

## Layout

```
lib/model/sort_plan.dart   pure Dart: classification, collision-free naming,
                           plan -> moves. No Flutter, no dart:io. Where the
                           tests live.
lib/data/                  the only code that touches the filesystem,
                           permissions, or prefs.
lib/ui/                    filmstrip, folder grid, folder browser, home.
```

`flutter test` covers the pure logic exhaustively, the drag-and-drop wiring as
widget tests, and the move layer against a real temp directory.

## Building

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

`compileSdk` is pinned to **37** in `android/app/build.gradle.kts`:
`permission_handler_android` requires it, and the Flutter default resolves to
36. AGP 9.1.0 warns that 36 is its maximum *recommended* value — a warning,
not a limit.

`flutter analyze` and `flutter test` never invoke Gradle, so they stay green
over a broken Android build. After any `flutter upgrade`, run the release
build before trusting it.

### Signing

`android/app/debug.keystore` is committed on purpose. It's a debug-only key
with the standard `android` password, and it exists so APKs built on this
machine and in CI share one signing identity and can install over each other.
It is not a secret and must never be used for anything that matters.

Verify an APK's identity with `apksigner`, not `keytool -printcert -jarfile`
(which only understands legacy v1 JAR signing and misreports a modern APK as
unsigned):

```sh
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
keytool -list -v -keystore android/app/debug.keystore -storepass android -alias androiddebugkey
```

## Releasing

```sh
./scripts/release.sh
```

Bumps the patch version and build number, runs analyze + tests, builds the
release APK, verifies the built APK's `versionName` matches the new tag, then
publishes a GitHub release. Always publish from here — finishing by hand skips
the stale-APK check.

CI (`.github/workflows/build.yml`) also builds on push and uploads an APK
artifact. If Actions minutes run out, delete the `push:`/`pull_request:`
triggers and leave `workflow_dispatch:` so pushes stop failing noisily; the
release script doesn't need CI.

## Installing

Via [Obtainium](https://github.com/ImranR98/Obtainium): add
`https://github.com/stagfoo/mememaid`.

Releases are shaped for Obtainium's defaults — the tag is the bare version
(`1.0.1`, no `v`, no commit suffix), one `.apk` asset per release, and the repo
is public (a private repo answers anonymous API requests with a 404, which
Obtainium reports as *"Could not find a suitable release"*).

Two things break an existing Obtainium entry: renaming the app in a way that
changes the `applicationId` (Android treats that as a different app, not an
update), and changing the tag format.
