import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_protocol/mirror_protocol.dart';
import 'package:windows_sender/app/windows_sender_app.dart';
import 'package:windows_sender/core/native_bridge/mirror_native_api.dart';

void main() {
  testWidgets('loads displays and sends a STAGE 1 video-only start request', (
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
      'capturedFrames': 10,
      'captureDroppedFrames': 1,
      'encoderInputDroppedFrames': 2,
      'encodedFrames': 8,
      'transportDroppedFrames': 3,
      'codecConfigSent': 1,
      'keyFramesSent': 1,
      'packetsSent': 9,
      'bytesSent': 1000,
      'sendCompletedBytes': 900,
      'queueDepthCapture': 0,
      'queueDepthEncoder': 1,
      'queueDepthTransport': 2,
      'lastCaptureToEncodeMs': 12.5,
      'averageCaptureToEncodeMs': 14,
      'maxCaptureToEncodeMs': 30.25,
    });

    expect(snapshot.captureDroppedFrames, 1);
    expect(snapshot.encoderInputDroppedFrames, 2);
    expect(snapshot.transportDroppedFrames, 3);
    expect(snapshot.sendCompletedBytes, 900);
    expect(snapshot.queueDepthCapture, 0);
    expect(snapshot.queueDepthEncoder, 1);
    expect(snapshot.queueDepthTransport, 2);
    expect(snapshot.lastCaptureToEncodeMs, 12.5);
    expect(snapshot.averageCaptureToEncodeMs, 14);
    expect(snapshot.maxCaptureToEncodeMs, 30.25);
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
