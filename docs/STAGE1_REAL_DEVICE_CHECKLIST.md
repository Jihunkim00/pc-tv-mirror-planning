# STAGE 1 Real Device Verification Checklist

Use this checklist for Android TV validation that cannot be proven by unit tests or local builds.

## Build Artifacts

- Build Windows release: `flutter build windows --release`
- Build Android release bundle: `flutter build appbundle --release`
- Do not commit build outputs, logs, signing files, `key.properties`, or keystores.

## Android TV Receiver

- Install the latest receiver release build on the Android TV.
- Launch the app and confirm it auto-starts in `listening`.
- Confirm the UI shows one or more LAN IPv4 addresses with port `50720`.
- Confirm diagnostics show:
  - `Surface z-order: onTop`
  - `Surface valid: true`
  - `Scale mode: fitCenter`
  - `Codec create/release: 1/0` during an active stream
  - `Configured size: 1280x720`
  - `Output size: 1280x720`
- Confirm debug magenta is not visible in the release default build.

## Windows Sender

- Confirm the receiver IP field is empty on a fresh install, or loads the last successful TV IP.
- Enter the TV LAN IPv4 address, not `127.0.0.1`, unless testing with emulator and `adb forward`.
- Start streaming and confirm the sender shows:
  - increasing captured/encoded/packet counters
  - bounded queue depth
  - non-growing latency diagnostics
  - no unbounded transport backlog

## Streaming Pass

- Stream for at least 30 seconds.
- Confirm actual PC video is visible on the TV SurfaceView.
- Confirm the image is 16:9 and UI circles do not appear stretched.
- Confirm `aspectRatioError < 0.01`.
- Confirm `codecCreateCount == 1` and `codecReleaseCount == 0` during the stream.
- Confirm `surfaceCreatedCount == 1` and `surfaceDestroyedCount == 0` during the stream.
- Confirm `CCodecBufferChannel: no latch time for frame` is not continuously repeated.

## Stability Pass

- Run Stop/Start 5 times.
- Force-close the Windows sender and confirm the receiver returns to `listening`.
- Reopen the receiver app and reconnect.
- Stream for 5 minutes and confirm latency does not accumulate over time.
- Run a malformed TCP probe such as connect-and-close and confirm the receiver stays alive and returns to `listening`.
