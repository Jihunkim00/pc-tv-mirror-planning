# STAGE 3 Real Device Checklist

Use this checklist on the actual Windows sender PC and Android TV. Do not mark
FPS, latency, audio, or sync targets as passed unless they were measured on the
real devices.

## Setup

1. Connect the Windows PC and Android TV to the same LAN.
2. Start the Android TV receiver and confirm it listens on `0.0.0.0:50720`.
3. Start the Windows sender on `pr02` and select `lowLatency720p30`.
4. Keep system audio enabled for the default pass. Repeat with audio disabled.

## Sender Metrics

Record these values after 30 seconds and again after 5 minutes:

- `captureCallbackFps`
- `admittedFrameFps`
- `convertedFps`
- `encoderAcceptedFps`
- `encodedFps`
- `sentVideoFps`
- `cadenceSkippedFrames`
- `captureReplacedFrames`
- `conversionBackpressureDroppedFrames`
- `encoderBackpressureDroppedFrames`
- `transportBackpressureDroppedFrames`
- `encoderNotAcceptingCount`
- `processInputDurationAverageMs`
- `processInputDurationP95Ms`
- `processOutputDurationAverageMs`
- `processOutputDurationP95Ms`
- `selectedEncoderName`
- `selectedEncoderHardware`
- `encoderD3D11Aware`
- `bgraToNv12Mode`
- `gpuReadbackPerFrame`
- `textureReuseEnabled`
- `audioCaptureState`
- `audioDeviceName`
- `audioCaptureFps`
- `audioEncodeAverageMs`
- `audioQueueDepth`
- `audioDroppedPackets`
- `packetWriterVideoWaitMs`
- `packetWriterAudioWaitMs`

Pass criteria:

- `admittedFrameFps >= 23`
- `encoderAcceptedFps >= 23`
- `encodedFps >= 23`
- `sentVideoFps >= 23`
- Recommended: all above `>= 27`
- `encoderAcceptedFps - encodedFps <= 2`
- real backpressure drops do not grow continuously
- audio enabled does not reduce presented video FPS by 3fps or more

`cadenceSkippedFrames` is expected when a 60Hz or higher source is admitted to
30fps. Do not count it as a performance failure. Real bottlenecks are
`conversionBackpressureDroppedFrames`, `encoderBackpressureDroppedFrames`, and
`transportBackpressureDroppedFrames`.

## Receiver Metrics

Record these values after 30 seconds and again after 5 minutes:

- `receivedAccessUnitFps`
- `decoderInputFps`
- `decoderOutputFps`
- `releasedToSurfaceFps`
- `actualPresentedFps`
- `presentedFrameIntervalP95Ms`
- `receiverQueueDepth`
- `staleAccessUnitsDropped`
- `lateOutputBuffersDropped`
- `frameSequenceGaps`
- `codecCreateCount`
- `codecReleaseCount`
- `surfaceCreatedCount`
- `surfaceDestroyedCount`
- `audioState`
- `audioDecoderName`
- `receivedAudioPackets`
- `audioDecoderInputPackets`
- `audioDecoderOutputBuffers`
- `audioTrackWrittenFrames`
- `audioBufferedDurationMs`
- `audioDroppedPackets`
- `audioUnderrunCount`
- `avSyncOffsetMs`
- `avSyncAverageMs`
- `avSyncP95Ms`
- `videoFramesDroppedForAvSync`
- `syncMaster`

Pass criteria:

- `receivedAccessUnitFps >= 23`
- `decoderOutputFps >= 23`
- `releasedToSurfaceFps >= 23`
- Recommended: all above `>= 27`
- `presentedFrameIntervalP95Ms <= 60ms`
- queues do not grow continuously
- no sustained FPS degradation after 5 minutes
- `abs(avSyncAverageMs) <= 100ms`
- Recommended A/V sync: within about `+/-50ms`
- no continuously increasing A/V drift after 5 minutes

## Fullscreen Remote Test

1. Start streaming and enter fullscreen.
2. Press remote OK once.
3. Confirm status/diagnostics UI appears and stream continues.
4. Press OK/Fullscreen again and confirm fullscreen returns.
5. Press BACK in fullscreen and confirm status UI appears.
6. Repeat 10 times.

Pass criteria:

- socket remains connected
- MediaCodec keeps streaming
- `codecCreateCount` does not increase during toggles
- `codecReleaseCount` does not increase during toggles
- status UI shows current diagnostics after exit

## Audio Test

1. Play PC system audio from an app.
2. Confirm TV speakers play the PC system sound.
3. Confirm microphone input is not transmitted.
4. Use TV volume keys and confirm Android volume behavior is unchanged.
5. Toggle mute in receiver status UI.
6. Stop/start mirroring 5 times.

Pass criteria:

- `audioState` is `playing` when unmuted
- mute stops TV audio without stopping video
- audio errors do not end the video stream
- no repeated audio underruns
- no audio delay accumulation after 5 minutes

## Known Limits To Record

- Actual device model and Windows GPU/driver.
- Whether hardware H.264 encoder was selected.
- Whether AAC encoder started successfully.
- Whether video FPS met 23fps minimum and 27fps recommendation.
- Whether A/V sync met the 100ms absolute-average target.
