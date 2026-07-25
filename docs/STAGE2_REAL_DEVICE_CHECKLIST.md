# STAGE 2 Real Device Checklist

## Scope

Validate that the STAGE 2 video path keeps 720p30 low-latency playback stable on
an actual Android TV over the same LAN.

Do not mark FPS, latency, or 5-minute stability as passed unless measured on the
device.

## Build Commands

Run from the repository root:

```powershell
Push-Location packages\mirror_protocol
dart analyze
dart test
Pop-Location

Push-Location apps\windows_sender
flutter analyze
flutter test
flutter build windows --debug
flutter build windows --release
Pop-Location

Push-Location apps\android_tv_receiver
flutter analyze
flutter test
.\android\gradlew.bat -p android :app:compileDebugKotlin
.\android\gradlew.bat -p android :app:assembleDebug
.\android\gradlew.bat -p android :app:bundleRelease
flutter build appbundle --release
Pop-Location

git diff --check
```

## Android TV Run

1. Install and launch the receiver release build on the Android TV.
2. Confirm the receiver is listening on `0.0.0.0:50720`.
3. Note the TV LAN IPv4 address shown in Status mode.
4. Start the Windows sender against that IPv4 address and port `50720`.
5. Confirm the first rendered frame switches the receiver into fullscreen video mode.
6. Confirm BACK returns to Status mode.
7. Confirm DPAD_CENTER or ENTER toggles fullscreen from fullscreen mode.
8. Confirm PLAY_PAUSE does not stop the stream in STAGE 2.
9. Toggle scale mode:
   - `fit` preserves aspect ratio and letterboxes when needed.
   - `fill` preserves aspect ratio and center-crops when needed.
10. Stop and restart the stream five times.

## Metrics To Record

Record before and after any performance fix:

- Sender: target, capture, convert, encode, send FPS.
- Sender: capture interval p95, encode duration average/p95, queue depths, drops.
- Sender: selected encoder name, hardware flag, low-latency options, unsupported options.
- Receiver: receive, decoder input, decoder output, present FPS.
- Receiver: presented interval average/p95, late drops, queue depth, sequence gaps.
- Receiver: estimated latency average/p95.

## Pass Targets

- Presented FPS: 27 to 30.
- Presented frame interval p95: 50 ms or lower.
- Average receiver latency: 300 ms or lower.
- p95 receiver latency: 500 ms or lower.
- No sustained queue depth growth over 5 minutes.
- `codecCreateCount` is 1 during one uninterrupted stream.
- `codecReleaseCount` remains 0 during one uninterrupted stream.

## Required Notes

If hardware misses the targets, prefer dropping stale frames over accumulating
latency. Record the bottleneck summary shown in the UI rather than claiming a
successful FPS or latency result without measurement.
