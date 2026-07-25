import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_protocol/mirror_protocol.dart';
import 'package:windows_sender/app/windows_sender_app.dart';
import 'package:windows_sender/core/native_bridge/mirror_native_api.dart';

void main() {
  testWidgets('loads displays and sends a STAGE 3 video/audio start request', (
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
    expect(json['audio'], {
      'enabled': true,
      'codec': 'aacLc',
      'sampleRate': 48000,
      'channelCount': 2,
      'bitrate': 128000,
      'source': 'systemLoopback',
    });
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
      'targetAdmissionFps': 29.5,
      'admittedFrameFps': 29.4,
      'convertedFps': 29.7,
      'encoderAcceptedFps': 29.0,
      'encoderInputFps': 29.0,
      'encodedFps': 28.8,
      'sentVideoFps': 28.8,
      'sentAccessUnitFps': 28.8,
      'cadenceDroppedFps': 29.0,
      'encoderBusyDroppedFps': 0.0,
      'conversionBusyDroppedFps': 0.0,
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
      'captureReplacedFrames': 1,
      'cadenceSkippedFrames': 2,
      'conversionBackpressureDroppedFrames': 0,
      'encoderBackpressureDroppedFrames': 0,
      'transportBackpressureDroppedFrames': 3,
      'shutdownDroppedFrames': 0,
      'totalDroppedFrames': 6,
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
      'admittedToEncodedRatio': 0.98,
      'selectedEncoderName': 'Intel Quick Sync H.264',
      'selectedEncoderHardware': true,
      'selectedEncoderAsync': false,
      'encoderD3D11Aware': true,
      'encoderInputFormat': 'NV12 1280x720@30',
      'encoderOutputFormat': 'H.264 1280x720@30',
      'averageEncodeDurationMs': 8.0,
      'encoderBackpressureCount': 1,
      'encoderNotAcceptingCount': 1,
      'processInputCalls': 9,
      'processInputAccepted': 8,
      'processInputNotAccepting': 1,
      'processInputRetries': 1,
      'processOutputCalls': 10,
      'processOutputFrames': 8,
      'processInputDurationAverageMs': 0.2,
      'processInputDurationP95Ms': 0.4,
      'processOutputDurationAverageMs': 0.8,
      'processOutputDurationP95Ms': 1.3,
      'bgraToNv12Mode': 'cpuBgraToNv12',
      'gpuReadbackPerFrame': true,
      'textureReuseEnabled': true,
      'lowLatencyOptionsApplied': 'MF_LOW_LATENCY',
      'unsupportedEncoderOptions': 'none',
      'bottleneckSummary': 'healthy',
      'audioEnabled': true,
      'audioCaptureState': 'capturing',
      'audioDeviceName': 'Speakers',
      'audioInputSampleRate': 48000,
      'audioInputChannels': 2,
      'audioEncodedSampleRate': 48000,
      'audioEncodedChannels': 2,
      'capturedAudioPackets': 4,
      'encodedAudioPackets': 4,
      'sentAudioPackets': 3,
      'audioCaptureFps': 46.8,
      'audioEncodeAverageMs': 0.7,
      'audioQueueDepth': 1,
      'audioDroppedPackets': 0,
      'audioLastError': '',
      'videoFpsAudioEnabled': 28.8,
      'audioCpuTimeMs': 0.7,
      'packetWriterVideoWaitMs': 0.5,
      'packetWriterAudioWaitMs': 0.4,
    });

    expect(snapshot.targetFps, 30);
    expect(snapshot.captureCallbackFps, 29.8);
    expect(snapshot.admittedFrameFps, 29.4);
    expect(snapshot.encoderAcceptedFps, 29.0);
    expect(snapshot.captureFrameIntervalP95Ms, 38);
    expect(snapshot.encodeDurationP95Ms, 14);
    expect(snapshot.captureDroppedFrames, 1);
    expect(snapshot.captureReplacedFrames, 1);
    expect(snapshot.cadenceSkippedFrames, 2);
    expect(snapshot.conversionDroppedFrames, 0);
    expect(snapshot.encoderInputDroppedFrames, 2);
    expect(snapshot.encoderBackpressureDroppedFrames, 0);
    expect(snapshot.transportDroppedFrames, 3);
    expect(snapshot.totalDroppedFrames, 6);
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
    expect(snapshot.encoderNotAcceptingCount, 1);
    expect(snapshot.processInputDurationP95Ms, 0.4);
    expect(snapshot.processOutputDurationP95Ms, 1.3);
    expect(snapshot.gpuReadbackPerFrame, isTrue);
    expect(snapshot.audioEnabled, isTrue);
    expect(snapshot.audioCaptureState, 'capturing');
    expect(snapshot.sentAudioPackets, 3);
    expect(snapshot.packetWriterAudioWaitMs, 0.4);
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
