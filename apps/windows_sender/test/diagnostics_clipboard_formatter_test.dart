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
    expect(text, contains('MFT flags/doesNotAddRef/holdsBuffers:'));
    expect(text, contains('keyframes/sinceLast/lastPtsUs/lastBytes:'));
    expect(text, contains('AU size/fragment/reassembly errors:'));
    expect(text, contains('receiver decoder configured/output: 1920x1080 / 1920x1080'));
    expect(text, contains('receiver surface/outputFormatChanges: 1920x1080 / 1'));
  });}
