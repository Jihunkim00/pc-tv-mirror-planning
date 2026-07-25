import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_protocol/mirror_protocol.dart';
import 'package:windows_sender/app/windows_sender_app.dart';
import 'package:windows_sender/core/native_bridge/mirror_native_api.dart';

void main() {
  testWidgets('loads displays and sends a STAGE 2 video-only start request', (
    tester,
  ) async {
    final nativeApi = _FakeMirrorNativeApi();

    await tester.pumpWidget(WindowsSenderApp(nativeApi: nativeApi));
    await tester.pumpAndSettle();

    expect(find.text('DISPLAY1'), findsOneWidget);
    expect(find.text('1280 x 720  DISPLAY1'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, '192.168.1.40');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(nativeApi.lastStartRequest, isNotNull);
    final json = nativeApi.lastStartRequest!.streamRequest.toJson();
    expect(json['type'], 'stream.start');
    expect(json['sourceType'], 'display');
    expect(json.containsKey('audio'), isFalse);
    expect(json.containsKey('privacyScreen'), isFalse);
    expect(
      (json['video'] as Map<String, Object?>)['performanceProfile'],
      'lowLatency720p30',
    );
    expect(find.text('State: negotiating'), findsOneWidget);
  });

  test('parses sender latency, queue, and drop diagnostics', () {
    final snapshot = NativeSessionSnapshot.fromJson({
      'state': 'streaming',
      'userMessage': 'Native 1280x720 H.264 video path is running.',
      'captureReady': true,
      'encoderReady': true,
      'signalingReady': true,
      'nativeVideoPathReady': true,
      'targetFps': 30.0,
      'captureCallbackFps': 29.8,
      'capturedFps': 29.7,
      'convertedFps': 29.7,
      'encoderInputFps': 29.0,
      'encodedFps': 28.8,
      'sentAccessUnitFps': 28.8,
      'captureFrameIntervalAverageMs': 33.5,
      'captureFrameIntervalP95Ms': 38.0,
      'encodeFrameIntervalAverageMs': 34.0,
      'sendFrameIntervalAverageMs': 34.5,
      'captureToConvertAverageMs': 6.5,
      'convertToEncodeAverageMs': 1.5,
      'encodeDurationAverageMs': 8.0,
      'encodeDurationP95Ms': 14.0,
      'encodeToSendAverageMs': 2.0,
      'capturedFrames': 10,
      'captureDroppedFrames': 1,
      'conversionDroppedFrames': 0,
      'encoderInputDroppedFrames': 2,
      'encodedFrames': 8,
      'transportDroppedFrames': 3,
      'duplicatedFrames': 0,
      'lastProcessedFrameSequence': 8,
      'codecConfigSent': 1,
      'keyFramesSent': 1,
      'packetsSent': 9,
      'bytesSent': 1000,
      'sendCompletedBytes': 900,
      'socketSendCallsPerSecond': 28.5,
      'averagePacketSendDurationMs': 0.4,
      'accessUnitSendDurationAverageMs': 0.5,
      'accessUnitSendDurationP95Ms': 1.2,
      'pendingSendBytes': 256,
      'queueDepthCapture': 0,
      'queueDepthEncoder': 1,
      'queueDepthTransport': 2,
      'lastCaptureToEncodeMs': 12.5,
      'averageCaptureToEncodeMs': 14,
      'maxCaptureToEncodeMs': 30.25,
      'selectedEncoderName': 'Intel Quick Sync H.264',
      'selectedEncoderHardware': true,
      'selectedEncoderAsync': false,
      'encoderD3D11Aware': true,
      'encoderInputFormat': 'NV12 1280x720@30',
      'encoderOutputFormat': 'H.264 1280x720@30',
      'averageEncodeDurationMs': 8.0,
      'encoderBackpressureCount': 1,
      'lowLatencyOptionsApplied': 'MF_LOW_LATENCY',
      'unsupportedEncoderOptions': 'none',
      'bottleneckSummary': 'healthy',
    });

    expect(snapshot.targetFps, 30);
    expect(snapshot.captureCallbackFps, 29.8);
    expect(snapshot.captureFrameIntervalP95Ms, 38);
    expect(snapshot.encodeDurationP95Ms, 14);
    expect(snapshot.captureDroppedFrames, 1);
    expect(snapshot.conversionDroppedFrames, 0);
    expect(snapshot.encoderInputDroppedFrames, 2);
    expect(snapshot.transportDroppedFrames, 3);
    expect(snapshot.lastProcessedFrameSequence, 8);
    expect(snapshot.sendCompletedBytes, 900);
    expect(snapshot.socketSendCallsPerSecond, 28.5);
    expect(snapshot.pendingSendBytes, 256);
    expect(snapshot.queueDepthCapture, 0);
    expect(snapshot.queueDepthEncoder, 1);
    expect(snapshot.queueDepthTransport, 2);
    expect(snapshot.lastCaptureToEncodeMs, 12.5);
    expect(snapshot.averageCaptureToEncodeMs, 14);
    expect(snapshot.maxCaptureToEncodeMs, 30.25);
    expect(snapshot.selectedEncoderHardware, isTrue);
    expect(snapshot.encoderD3D11Aware, isTrue);
    expect(snapshot.encoderBackpressureCount, 1);
    expect(snapshot.bottleneckSummary, 'healthy');
  });
}

final class _FakeMirrorNativeApi implements MirrorNativeApi {
  StartMirrorSessionRequest? lastStartRequest;

  @override
  Future<List<DisplayInfo>> listDisplays() async {
    return const [
      DisplayInfo(
        id: 'DISPLAY1',
        name: 'DISPLAY1',
        width: 1280,
        height: 720,
        x: 0,
        y: 0,
        scaleFactor: 1,
        isPrimary: true,
      ),
    ];
  }

  @override
  Future<NativeSessionSnapshot> startSession(
    StartMirrorSessionRequest request,
  ) async {
    lastStartRequest = request;
    return const NativeSessionSnapshot(
      state: MirrorSessionState.negotiating,
      userMessage: 'Control signaling is ready.',
      captureReady: false,
      encoderReady: false,
      signalingReady: true,
      nativeVideoPathReady: false,
    );
  }

  @override
  Future<NativeSessionSnapshot> stopSession(String sessionId) async {
    return const NativeSessionSnapshot(
      state: MirrorSessionState.idle,
      userMessage: 'Stopped.',
      captureReady: false,
      encoderReady: false,
      signalingReady: false,
      nativeVideoPathReady: false,
    );
  }

  @override
  Future<NativeSessionSnapshot> getSessionStatus() async {
    return const NativeSessionSnapshot(
      state: MirrorSessionState.negotiating,
      userMessage: 'Control signaling is ready.',
      captureReady: false,
      encoderReady: false,
      signalingReady: true,
      nativeVideoPathReady: false,
    );
  }
}
