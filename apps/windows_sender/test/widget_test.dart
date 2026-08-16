import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_protocol/mirror_protocol.dart';
import 'package:windows_sender/app/windows_sender_app.dart';
import 'package:windows_sender/core/native_bridge/mirror_native_api.dart';
import 'package:windows_sender/features/mirroring/mirror_controller.dart';

void main() {
  testWidgets('loads displays and sends the MVP video/audio start request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nativeApi = _FakeMirrorNativeApi();

    await tester.pumpWidget(WindowsSenderApp(nativeApi: nativeApi));
    await tester.pumpAndSettle();

    expect(find.text('DISPLAY1'), findsOneWidget);
    expect(find.text('1280 x 720  DISPLAY1'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, '192.168.1.40');
    final startButton = find.widgetWithText(FilledButton, 'Start');
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
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
      'cinema1080p24',
    );
    expect((json['video'] as Map<String, Object?>)['bitrateKbps'], 8000);
    expect(nativeApi.lastStartRequest!.pcLocalAudioMuteRequested, isFalse);
    expect(nativeApi.lastStartRequest!.tvAudioSourceDeviceId, 'virtual-tv');
    expect(nativeApi.lastStartRequest!.pcMonitorDeviceId, 'speakers');
    expect(find.text('State: negotiating'), findsOneWidget);
    expect(find.text('System audio'), findsNothing);
    expect(find.text('Mute PC speakers'), findsNothing);
    expect(find.text('Audio routing'), findsNothing);
  });

  testWidgets(
    'switches display while streaming by restarting the existing session',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final nativeApi = _FakeMirrorNativeApi();
      await tester.pumpWidget(WindowsSenderApp(nativeApi: nativeApi));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).first, '192.168.1.40');
      final startButton = find.widgetWithText(FilledButton, 'Start');
      await tester.ensureVisible(startButton);
      await tester.tap(startButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('DISPLAY2'));
      await tester.pumpAndSettle();

      expect(nativeApi.stopCalls, 1);
      expect(nativeApi.startCalls, 2);
      expect(nativeApi.lastStartRequest!.streamRequest.sourceId, 'DISPLAY2');
    },
  );

  testWidgets('marks 1080p60 and 4K profiles as Experimental', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WindowsSenderApp(nativeApi: _FakeMirrorNativeApi()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<SenderVideoProfile>));
    await tester.pumpAndSettle();

    expect(find.text('Experimental'), findsNWidgets(2));
  });

  test('uses a balanced STAGE 4 1080p profile bitrate', () {
    final profile = SenderVideoProfile.highQuality1080p30.videoProfile;

    expect(profile.width, 1920);
    expect(profile.height, 1080);
    expect(profile.fps, 30);
    expect(profile.bitrateKbps, 7500);
    expect(profile.performanceProfile, PerformanceProfile.highQuality1080p30);
  });
  test('uses the Experimental FHD 1080p60 profile values', () {
    final profile = SenderVideoProfile.highQuality1080p60.videoProfile;

    expect(profile.width, 1920);
    expect(profile.height, 1080);
    expect(profile.fps, 60);
    expect(profile.bitrateKbps, 14000);
    expect(profile.performanceProfile, PerformanceProfile.highQuality1080p60);
    expect(SenderVideoProfile.highQuality1080p60.isExperimental, isTrue);
  });
  test('uses the FHD 1080p24 Cinema profile values', () {
    final profile = SenderVideoProfile.cinema1080p24.videoProfile;

    expect(profile.width, 1920);
    expect(profile.height, 1080);
    expect(profile.fps, 24);
    expect(profile.bitrateKbps, 8000);
    expect(profile.performanceProfile, PerformanceProfile.cinema1080p24);
  });

  test('uses the STAGE 5 experimental 4K profile values', () {
    final profile = SenderVideoProfile.experimental4k30.videoProfile;

    expect(profile.width, 3840);
    expect(profile.height, 2160);
    expect(profile.fps, 30);
    expect(profile.bitrateKbps, 20000);
    expect(profile.performanceProfile, PerformanceProfile.experimental4k30);
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
      'sendFrameIntervalP95Ms': 42.0,
      'captureToConvertAverageMs': 6.5,
      'convertToEncodeAverageMs': 1.5,
      'encodeDurationAverageMs': 8.0,
      'encodeDurationP95Ms': 14.0,
      'encodeToSendAverageMs': 2.0,
      'videoQueueWaitAverageMs': 0.6,
      'videoQueueWaitP95Ms': 1.4,
      'capturedFrames': 10,
      'captureReplacedFrames': 1,
      'cadenceSkippedFrames': 2,
      'conversionBackpressureDroppedFrames': 0,
      'encoderBackpressureDroppedFrames': 0,
      'transportBackpressureDroppedFrames': 3,
      'staleVideoDroppedFrames': 2,
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
      'selectedProfile': 'highQuality1080p30',
      'outputResolution': '1920x1080',
      'currentBitrateKbps': 7500,
      'targetFrameIntervalMs': 33.333,
      'staleVideoDroppedFps': 1.5,
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
      'playbackState': 'streaming',
      'pauseRequestsReceived': 1,
      'resumeRequestsReceived': 1,
      'playbackCommandAcksSent': 2,
      'playbackCommandErrorsSent': 0,
      'resumeCodecConfigResends': 1,
      'localSpeakerMuteMode': 'pcLocalMuteRequested',
      'localSpeakerMuteState': 'unsupported',
      'localSpeakerMuteLastError':
          'Unavailable: separate PC/TV audio routing is not configured.',
      'pcLocalAudioMuteRequested': true,
      'pcLocalAudioMuteSupported': false,
      'pcLocalAudioMuteApplied': false,
      'pcLocalAudioOriginalMuteState': false,
      'tvAudioStreaming': true,
      'audioCaptureActive': true,
      'audioEncoderActive': true,
      'audioTransportActive': true,
      'audioRoutingMode': 'defaultRenderEndpointLoopback',
      'audioMuteUnsupportedReason':
          'Unavailable: separate PC/TV audio routing is not configured.',
      'audioRoutingUnsupportedReason':
          'Unavailable: separate PC/TV audio routing is not configured.',
      'tvAudioSourceDeviceId': 'virtual-tv',
      'tvAudioSourceDeviceName': 'TV Mirror Virtual Audio',
      'pcMonitorDeviceId': 'speakers',
      'pcMonitorDeviceName': 'Speakers',
      'localMonitorActive': true,
      'localMonitorMuted': true,
      'localMonitorQueueDepth': 1,
      'localMonitorDroppedBuffers': 2,
      'audioCaptureFormat': '48000 Hz 2 ch float32',
      'audioMonitorFormat': '48000 Hz 2 ch float32',
      'requestedProfile': 'experimental4k30',
      'appliedProfile': 'highQuality1080p30',
      'profileFallbackReason':
          '4K unavailable: receiver decoder supports up to 1920x1080',
      'outputWidth': 1920,
      'outputHeight': 1080,
      'targetBitrateKbps': 7500,
      'encoderName': 'Intel Quick Sync H.264',
      'hardwareEncoderActive': true,
      'encoderSupportsRequestedResolution': false,
      'receiverMaxWidth': 1920,
      'receiverMaxHeight': 1080,
      'receiverSupports4k30': false,
      'captureFpsRecent': 29.8,
      'conversionFpsRecent': 29.7,
      'encoderInputFpsRecent': 29.0,
      'encoderOutputFpsRecent': 28.8,
      'transportVideoFpsRecent': 28.8,
      'receiverPresentedFpsRecent': 0.0,
      'conversionDurationP95Ms': 6.5,
      'encoderQueueWaitP95Ms': 1.4,
      'transportSendP95Ms': 1.2,
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
    expect(snapshot.selectedProfile, 'highQuality1080p30');
    expect(snapshot.outputResolution, '1920x1080');
    expect(snapshot.currentBitrateKbps, 7500);
    expect(snapshot.sendFrameIntervalP95Ms, 42);
    expect(snapshot.videoQueueWaitP95Ms, 1.4);
    expect(snapshot.staleVideoDroppedFrames, 2);
    expect(snapshot.staleVideoDroppedFps, 1.5);
    expect(snapshot.audioEnabled, isTrue);
    expect(snapshot.audioCaptureState, 'capturing');
    expect(snapshot.sentAudioPackets, 3);
    expect(snapshot.packetWriterAudioWaitMs, 0.4);
    expect(snapshot.playbackState, 'streaming');
    expect(snapshot.resumeCodecConfigResends, 1);
    expect(snapshot.localSpeakerMuteState, 'unsupported');
    expect(snapshot.pcLocalAudioMuteRequested, isTrue);
    expect(snapshot.pcLocalAudioMuteSupported, isFalse);
    expect(snapshot.pcLocalAudioMuteApplied, isFalse);
    expect(snapshot.tvAudioStreaming, isTrue);
    expect(snapshot.audioCaptureActive, isTrue);
    expect(snapshot.audioEncoderActive, isTrue);
    expect(snapshot.audioTransportActive, isTrue);
    expect(snapshot.audioRoutingMode, 'defaultRenderEndpointLoopback');
    expect(snapshot.audioMuteUnsupportedReason, contains('Unavailable'));
    expect(snapshot.tvAudioSourceDeviceName, 'TV Mirror Virtual Audio');
    expect(snapshot.pcMonitorDeviceName, 'Speakers');
    expect(snapshot.localMonitorActive, isTrue);
    expect(snapshot.localMonitorMuted, isTrue);
    expect(snapshot.localMonitorQueueDepth, 1);
    expect(snapshot.localMonitorDroppedBuffers, 2);
    expect(snapshot.audioCaptureFormat, '48000 Hz 2 ch float32');
    expect(snapshot.audioMonitorFormat, '48000 Hz 2 ch float32');
    expect(snapshot.requestedProfile, 'experimental4k30');
    expect(snapshot.appliedProfile, 'highQuality1080p30');
    expect(snapshot.profileFallbackReason, contains('receiver decoder'));
    expect(snapshot.outputWidth, 1920);
    expect(snapshot.outputHeight, 1080);
    expect(snapshot.targetBitrateKbps, 7500);
    expect(snapshot.encoderName, 'Intel Quick Sync H.264');
    expect(snapshot.hardwareEncoderActive, isTrue);
    expect(snapshot.encoderSupportsRequestedResolution, isFalse);
    expect(snapshot.receiverMaxWidth, 1920);
    expect(snapshot.receiverMaxHeight, 1080);
    expect(snapshot.receiverSupports4k30, isFalse);
    expect(snapshot.transportVideoFpsRecent, 28.8);
    expect(snapshot.bottleneckSummary, 'healthy');
  });
}

final class _FakeMirrorNativeApi implements MirrorNativeApi {
  StartMirrorSessionRequest? lastStartRequest;
  var startCalls = 0;
  var stopCalls = 0;

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
      DisplayInfo(
        id: 'DISPLAY2',
        name: 'DISPLAY2',
        width: 1920,
        height: 1080,
        x: 1280,
        y: 0,
        scaleFactor: 1,
        isPrimary: false,
      ),
    ];
  }

  @override
  Future<List<AudioDeviceInfo>> listAudioDevices() async {
    return const [
      AudioDeviceInfo(
        id: 'virtual-tv',
        name: 'TV Mirror Virtual Audio',
        isDefault: false,
        isLikelyVirtual: true,
      ),
      AudioDeviceInfo(
        id: 'speakers',
        name: 'Speakers',
        isDefault: true,
        isLikelyVirtual: false,
      ),
    ];
  }

  @override
  Future<NativeSessionSnapshot> startSession(
    StartMirrorSessionRequest request,
  ) async {
    lastStartRequest = request;
    startCalls++;
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
    stopCalls++;
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

  @override
  Future<NativeSessionSnapshot> setPcLocalAudioMuteRequested(
    bool requested,
  ) async {
    return NativeSessionSnapshot(
      state: MirrorSessionState.negotiating,
      userMessage: 'Control signaling is ready.',
      captureReady: false,
      encoderReady: false,
      signalingReady: true,
      nativeVideoPathReady: false,
      pcLocalAudioMuteRequested: requested,
      pcLocalAudioMuteSupported: false,
      pcLocalAudioMuteApplied: false,
    );
  }
}
