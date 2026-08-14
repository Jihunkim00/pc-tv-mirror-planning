import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_protocol/mirror_protocol.dart';
import 'package:windows_sender/core/native_bridge/mirror_native_api.dart';

import 'package:windows_sender/features/mirroring/diagnostics_clipboard_formatter.dart';

void main() {
  test(
    'formats all required sections and unavailable values without a snapshot',
    () {
      final text = DiagnosticsClipboardFormatter.format(
        snapshot: null,
        sourceDisplay: null,
        sessionId: null,
      );

      for (final section in [
        '=== SESSION ===',
        'SOURCE DISPLAY',
        'CAPTURE',
        'ENCODER',
        'TRANSPORT',
        'RECEIVER',
        'VIDEO TIMING',
        'AUDIO',
        'PIPELINE',
        'DEBUG',
      ]) {
        expect(text, contains(section));
      }
      expect(text, contains('unavailable'));
      expect(text, contains('receiverMetricsSource:'));
    },
  );

  test('includes immutable source display information', () {
    final text = DiagnosticsClipboardFormatter.format(
      snapshot: null,
      sourceDisplay: const DisplayInfo(
        id: 'display-1',
        name: 'Panel',
        width: 1920,
        height: 1080,
        x: 0,
        y: 0,
        scaleFactor: 1,
        isPrimary: true,
        refreshRateHz: 60,
      ),
      sessionId: 'session-1',
    );

    expect(text, contains('session-1'));
    expect(text, contains('1920x1080@60.00 Hz Panel'));
  });

  test('formats corruption diagnostics and receiver format values', () {
    final snapshot = NativeSessionSnapshot.fromJson({
      'state': 'streaming',
      'userMessage': 'streaming',
      'captureReady': true,
      'encoderReady': true,
      'signalingReady': true,
      'nativeVideoPathReady': true,
      'targetFps': 30,
      'frameArrivedCallbackFps': 60,
      'tryGetNextFrameSuccessFps': 60,
      'tryGetNextFrameNullCount': 2,
      'rawWgcIntervalP50Ms': 16.67,
      'rawWgcIntervalP95Ms': 16.70,
      'frameAcquireAverageMs': 0.2,
      'frameAcquireP95Ms': 0.4,
      'copyResourceAverageMs': 0.3,
      'copyResourceP95Ms': 0.5,
      'mapReadbackAverageMs': 1.2,
      'mapReadbackP95Ms': 2.0,
      'scaleAverageMs': 0.1,
      'scaleP95Ms': 0.2,
      'bgraToNv12AverageMs': 10.5,
      'bgraToNv12P95Ms': 12.0,
      'nv12CopyAverageMs': 1.1,
      'nv12CopyP95Ms': 1.5,
      'samplePrepareAverageMs': 0.4,
      'samplePrepareP95Ms': 0.7,
      'processInputAverageMs': 0.8,
      'processInputP95Ms': 1.4,
      'captureToEncoderReadyAverageMs': 14.6,
      'captureToEncoderReadyP95Ms': 17.2,
      'admittedFrameFps': 30,
      'cadenceSkippedFrames': 4,
      'cadenceSkippedRecent': 1,
      'cadenceSkipReason': 'source_above_target',
      'captureBottleneckStage': 'bgra_to_nv12',
      'sourceTextureWidth': 1920,
      'sourceTextureHeight': 1080,
      'sourceTextureFormat': 'BGRA8',
      'sourceRowPitch': 7680,
      'sourceBgraStride': 7680,
      'nv12YStride': 1920,
      'nv12UvStride': 1920,
      'nv12ExpectedBytes': 3110400,
      'nv12AllocatedBytes': 3110400,
      'nv12UsedBytes': 3110400,
      'mftInputStreamFlags': 1,
      'mftDoesNotAddref': false,
      'mftHoldsBuffers': false,
      'unsafeInputBufferReuseDetected': 0,
      'nv12GuardCorruptionCount': 0,
      'keyFrameCount': 7,
      'framesSinceLastKeyFrame': 21,
      'encodedAccessUnitBytes': 1000,
      'transportedAccessUnitBytes': 1000,
      'videoAuSizeMismatchCount': 0,
      'receiverAccessUnitBytes': 1000,
      'receiverCodecConfigsReceived': 1,
      'receiverKeyFramesReceived': 7,
      'receiverDecoderConfiguredWidth': 1920,
      'receiverDecoderConfiguredHeight': 1080,
      'receiverDecoderOutputWidth': 1920,
      'receiverDecoderOutputHeight': 1080,
      'receiverSurfaceWidth': 1920,
      'receiverSurfaceHeight': 1080,
      'receiverDecoderFormatChangeCount': 1,
    });
    final text = DiagnosticsClipboardFormatter.format(
      snapshot: snapshot,
      sourceDisplay: null,
      sessionId: 'corruption-test',
    );

    expect(text, contains('sourceTexture:'));
    expect(text, contains('FrameArrived FPS: 60.00'));
    expect(text, contains('TryGetNextFrame nulls: 2'));
    expect(text, contains('BGRA->NV12 avg/p95: 10.50 / 12.00'));
    expect(
      text,
      contains('Total capture->encoder-ready avg/p95: 14.60 / 17.20'),
    );
    expect(text, contains('Cadence skip reason: source_above_target'));
    expect(text, contains('Measured bottleneck stage: bgra_to_nv12'));
    expect(text, contains('MFT flags/doesNotAddRef/holdsBuffers:'));
    expect(text, contains('keyframes/sinceLast/lastPtsUs/lastBytes:'));
    expect(text, contains('AU size/fragment/reassembly errors:'));
    expect(
      text,
      contains('receiver decoder configured/output: 1920x1080 / 1920x1080'),
    );
    expect(
      text,
      contains('receiver surface/outputFormatChanges: 1920x1080 / 1'),
    );
  });
}
