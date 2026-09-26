import 'package:android_tv_receiver/app/android_tv_receiver_app.dart';
import 'package:android_tv_receiver/core/native_bridge/receiver_native_api.dart';
import 'package:android_tv_receiver/features/receiver/receiver_home_page.dart';
import 'package:android_tv_receiver/core/localization/locale_resolution.dart';
import 'package:android_tv_receiver/l10n/generated/app_localizations.dart';
import 'package:android_tv_receiver/widgets/tv_focus_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

void main() {
  testWidgets('starts the native receiver in STAGE 3 mode', (tester) async {
    final nativeApi = _FakeReceiverNativeApi();

    await _pumpReceiverApp(tester, nativeApi);

    expect(nativeApi.startedPort, 50720);
    expect(find.text('Waiting for PC video frames'), findsOneWidget);
    expect(find.text('State: Listening'), findsOneWidget);

    expect(find.text('Auto fullscreen'), findsOneWidget);
  });

  testWidgets('initial focus is Restart receiver', (tester) async {
    await _pumpReceiverApp(tester, _FakeReceiverNativeApi());

    expect(_focusedDebugLabel(), 'Restart receiver');
  });

  testWidgets('D-pad down moves focus through ordered buttons', (tester) async {
    await _pumpReceiverApp(tester, _FakeReceiverNativeApi());

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_focusedDebugLabel(), 'Fullscreen');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_focusedDebugLabel(), 'Stop receiver');
  });

  testWidgets('Select and Enter activate the focused button once', (
    tester,
  ) async {
    final nativeApi = _FakeReceiverNativeApi();
    await _pumpReceiverApp(tester, nativeApi);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(nativeApi.startCalls, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(nativeApi.stopCalls, 1);
  });

  testWidgets('disabled TV focus button is skipped by traversal', (
    tester,
  ) async {
    final firstNode = FocusNode(debugLabel: 'Enabled first');
    final disabledNode = FocusNode(debugLabel: 'Disabled middle');
    final lastNode = FocusNode(debugLabel: 'Enabled last');
    addTearDown(firstNode.dispose);
    addTearDown(disabledNode.dispose);
    addTearDown(lastNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
          },
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              children: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: TvFocusButton(
                    focusNode: firstNode,
                    autofocus: true,
                    onPressed: () {},
                    icon: Icons.looks_one,
                    label: 'Enabled first',
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: TvFocusButton(
                    focusNode: disabledNode,
                    enabled: false,
                    onPressed: () {},
                    icon: Icons.looks_two,
                    label: 'Disabled middle',
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: TvFocusButton(
                    focusNode: lastNode,
                    onPressed: () {},
                    icon: Icons.looks_3,
                    label: 'Enabled last',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_focusedDebugLabel(), 'Enabled first');
    expect(disabledNode.canRequestFocus, isFalse);
    expect(disabledNode.skipTraversal, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_focusedDebugLabel(), 'Enabled last');
  });

  testWidgets('streaming state restores focus to Fullscreen', (tester) async {
    await _pumpReceiverApp(
      tester,
      _FakeReceiverNativeApi(startState: MirrorSessionState.streaming),
    );

    expect(_focusedDebugLabel(), 'Fullscreen');
  });

  testWidgets('waiting label is hidden after the first surface release', (
    tester,
  ) async {
    await _pumpReceiverApp(
      tester,
      _FakeReceiverNativeApi(startState: MirrorSessionState.streaming),
    );

    expect(find.text('Waiting for PC video frames'), findsNothing);
    expect(find.text('State: Streaming'), findsOneWidget);
  });

  testWidgets('video surface is constrained to a 16:9 viewport', (
    tester,
  ) async {
    await _pumpReceiverApp(tester, _FakeReceiverNativeApi());

    final aspectRatio = tester.widget<AspectRatio>(
      find.descendant(
        of: find.byKey(const Key('receiver.videoSurfaceFocusBoundary')),
        matching: find.byType(AspectRatio),
      ),
    );

    expect(aspectRatio.aspectRatio, 16 / 9);
  });

  test('parses receiver surface and codec diagnostics', () {
    final snapshot = ReceiverSessionSnapshot.fromJson({
      'state': 'streaming',
      'userMessage': 'PC video is being released to the TV surface.',
      'receiverPort': 50720,
      'receiverBindAddress': '0.0.0.0',
      'localIpv4Addresses': ['192.168.1.40'],
      'decoderReady': true,
      'surfaceRendererReady': true,
      'receiverMaxVideoWidth': 3840,
      'receiverMaxVideoHeight': 2160,
      'receiverSupports4k30': true,
      'receiverDecoderName': 'c2.vendor.avc.decoder',
      'receiverPerformanceClass': '4k30',
      'receivedAccessUnitFps': 29.5,
      'decoderInputFps': 29.4,
      'decoderOutputFps': 29.3,
      'releasedToSurfaceFps': 29.2,
      'actualPresentedFps': 29.2,
      'lateFrameDropFps': 0.0,
      'receivedFrameIntervalAverageMs': 33.5,
      'receivedFrameIntervalP95Ms': 38.0,
      'decoderOutputIntervalAverageMs': 34.0,
      'presentedFrameIntervalAverageMs': 34.1,
      'presentedFrameIntervalP95Ms': 39.0,
      'receiverQueueDepth': 1,
      'releasedToSurfaceFrames': 4,
      'codecCreateCount': 1,
      'codecReleaseCount': 0,
      'surfaceCreatedCount': 1,
      'surfaceChangedCount': 2,
      'surfaceDestroyedCount': 0,
      'surfaceIsValid': true,
      'surfaceWidth': 1280,
      'surfaceHeight': 720,
      'zOrderMode': 'mediaOverlay',
      'firstSurfaceTestDrawSucceeded': true,
      'sourceWidth': 1280,
      'sourceHeight': 720,
      'containerWidth': 1000,
      'containerHeight': 700,
      'renderedViewWidth': 1000,
      'renderedViewHeight': 562,
      'scaleMode': 'fit',
      'aspectRatioError': 0.001,
      'configuredWidth': 1280,
      'configuredHeight': 720,
      'outputWidth': 1280,
      'outputHeight': 720,
      'outputFormatChangedCount': 1,
      'outputCropLeft': 0,
      'outputCropRight': 1279,
      'outputCropTop': 0,
      'outputCropBottom': 719,
      'networkToDecoderInputMs': 1.5,
      'decoderInputToOutputMs': 12.5,
      'estimatedEndToEndLatencyMs': 120.0,
      'latencyAverageMs': 100.0,
      'latencyP95Ms': 180.0,
      'maxReceiverQueueDepth': 3,
      'staleAccessUnitsDropped': 2,
      'lateOutputBuffersDropped': 1,
      'frameSequenceGaps': 0,
      'lastFrameAgeMs': 40.0,
      'currentFrameAgeMs': 40.0,
      'estimatedReceiverLatencyMs': 120.0,
      'rendererMode': 'lowLatencyPaced',
      'scheduledRenderFrames': 4,
      'immediateRenderFallbackFrames': 0,
      'averageRenderScheduleDelayMs': 20.0,
      'p95RenderScheduleDelayMs': 28.0,
      'playoutDelayMs': 30.0,
      'pacingResyncCount': 1,
      'avSyncOffsetMs': 24.0,
      'avSyncAverageMs': 30.0,
      'avSyncP95Ms': 42.0,
      'videoFramesDroppedForAvSync': 1,
      'avSyncResyncCount': 2,
      'syncMaster': 'audio',
      'audioDecoderName': 'c2.android.aac.decoder',
      'audioSessionGeneration': 8,
      'audioDecoderState': 'running',
      'audioDecoderInitialized': true,
      'audioDecoderReleased': false,
      'receivedAudioPackets': 10,
      'audioDecoderInputPackets': 9,
      'audioDecoderOutputBuffers': 8,
      'audioTrackWrittenFrames': 8192,
      'audioBytesWritten': 32768,
      'audioQueueDepth': 1,
      'pcmQueueDepth': 0,
      'audioBufferedDurationMs': 96.0,
      'audioPlaybackPositionUs': 123456,
      'audioUnderrunCount': 0,
      'audioDroppedPackets': 1,
      'audioState': 'playing',
      'audioMuted': false,
      'audioCodec': 'audio/mp4a-latm',
      'audioSampleRate': 48000,
      'audioChannels': 2,
      'audioChannelMask': 12,
      'audioEncodingFormat': 2,
      'audioTrackState': 'INITIALIZED',
      'audioTrackPlayState': 'PLAYING',
      'audioTrackInitialized': true,
      'audioTrackPlayCalled': true,
      'audioTrackRecreatedCount': 1,
      'audioTrackWriteErrorCount': 2,
      'audioTrackDeadObjectCount': 1,
      'audioQueueClearedOnReconnect': true,
      'audioEosReceived': false,
      'audioPtsResetCount': 3,
      'audioSessionResetCount': 4,
      'lastAudioSessionResetReason': 'TCP reconnect generation=8',
      'audioPacketsReceivedRecent': 47.0,
      'audioPacketsDecodedRecent': 46.0,
      'audioBytesWrittenRecent': 188416.0,
      'tvAudioAudibleExpected': true,
      'connectionId': 3,
      'receiverSessionGeneration': 8,
      'sessionId': 'session-3',
      'playbackState': 'streaming',
      'pauseCommandPending': false,
      'resumeCommandPending': false,
      'playbackCommandAcksReceived': 2,
      'playbackCommandErrorsReceived': 0,
    });

    expect(snapshot.receiverBindAddress, '0.0.0.0');
    expect(snapshot.localIpv4Addresses, ['192.168.1.40']);
    expect(snapshot.receiverMaxVideoWidth, 3840);
    expect(snapshot.receiverMaxVideoHeight, 2160);
    expect(snapshot.receiverSupports4k30, isTrue);
    expect(snapshot.receiverDecoderName, 'c2.vendor.avc.decoder');
    expect(snapshot.receiverPerformanceClass, '4k30');
    expect(snapshot.receivedAccessUnitFps, 29.5);
    expect(snapshot.releasedToSurfaceFrames, 4);
    // Legacy compatibility only; this does not prove Surface latch/render.
    // ignore: deprecated_member_use_from_same_package
    expect(snapshot.renderedFrames, 4);
    expect(snapshot.codecCreateCount, 1);
    expect(snapshot.codecReleaseCount, 0);
    expect(snapshot.surfaceCreatedCount, 1);
    expect(snapshot.surfaceDestroyedCount, 0);
    expect(snapshot.surfaceIsValid, isTrue);
    expect(snapshot.surfaceWidth, 1280);
    expect(snapshot.surfaceHeight, 720);
    expect(snapshot.zOrderMode, 'mediaOverlay');
    expect(snapshot.firstSurfaceTestDrawSucceeded, isTrue);
    expect(snapshot.sourceWidth, 1280);
    expect(snapshot.sourceHeight, 720);
    expect(snapshot.containerWidth, 1000);
    expect(snapshot.renderedViewHeight, 562);
    expect(snapshot.scaleMode, 'fit');
    expect(snapshot.aspectRatioError, 0.001);
    expect(snapshot.configuredWidth, 1280);
    expect(snapshot.configuredHeight, 720);
    expect(snapshot.outputWidth, 1280);
    expect(snapshot.outputHeight, 720);
    expect(snapshot.outputCropRight, 1279);
    expect(snapshot.outputFormatChangedCount, 1);
    expect(snapshot.networkToDecoderInputMs, 1.5);
    expect(snapshot.decoderInputToOutputMs, 12.5);
    expect(snapshot.estimatedEndToEndLatencyMs, 120.0);
    expect(snapshot.latencyP95Ms, 180.0);
    expect(snapshot.releasedToSurfaceFps, 29.2);
    expect(snapshot.actualPresentedFps, 29.2);
    expect(snapshot.presentedFrameIntervalP95Ms, 39.0);
    expect(snapshot.receiverQueueDepth, 1);
    expect(snapshot.maxReceiverQueueDepth, 3);
    expect(snapshot.staleAccessUnitsDropped, 2);
    expect(snapshot.lateOutputBuffersDropped, 1);
    expect(snapshot.lastFrameAgeMs, 40.0);
    expect(snapshot.rendererMode, 'lowLatencyPaced');
    expect(snapshot.scheduledRenderFrames, 4);
    expect(snapshot.pacingResyncCount, 1);
    expect(snapshot.avSyncOffsetMs, 24.0);
    expect(snapshot.avSyncP95Ms, 42.0);
    expect(snapshot.videoFramesDroppedForAvSync, 1);
    expect(snapshot.syncMaster, 'audio');
    expect(snapshot.audioState, 'playing');
    expect(snapshot.audioDecoderName, 'c2.android.aac.decoder');
    expect(snapshot.audioSessionGeneration, 8);
    expect(snapshot.audioDecoderState, 'running');
    expect(snapshot.audioDecoderInitialized, isTrue);
    expect(snapshot.audioDecoderReleased, isFalse);
    expect(snapshot.audioBufferedDurationMs, 96.0);
    expect(snapshot.audioTrackWrittenFrames, 8192);
    expect(snapshot.audioBytesWritten, 32768);
    expect(snapshot.audioTrackState, 'INITIALIZED');
    expect(snapshot.audioTrackPlayState, 'PLAYING');
    expect(snapshot.audioTrackInitialized, isTrue);
    expect(snapshot.audioTrackPlayCalled, isTrue);
    expect(snapshot.audioTrackRecreatedCount, 1);
    expect(snapshot.audioTrackWriteErrorCount, 2);
    expect(snapshot.audioTrackDeadObjectCount, 1);
    expect(snapshot.audioQueueClearedOnReconnect, isTrue);
    expect(snapshot.audioEosReceived, isFalse);
    expect(snapshot.audioPtsResetCount, 3);
    expect(snapshot.audioSessionResetCount, 4);
    expect(snapshot.lastAudioSessionResetReason, 'TCP reconnect generation=8');
    expect(snapshot.audioPacketsReceivedRecent, 47.0);
    expect(snapshot.audioPacketsDecodedRecent, 46.0);
    expect(snapshot.audioBytesWrittenRecent, 188416.0);
    expect(snapshot.tvAudioAudibleExpected, isTrue);
    expect(snapshot.connectionId, 3);
    expect(snapshot.receiverSessionGeneration, 8);
    expect(snapshot.sessionId, 'session-3');
    expect(snapshot.playbackState, 'streaming');
    expect(snapshot.playbackCommandAcksReceived, 2);
    expect(snapshot.bottleneckSummary, 'healthy_27_plus');
  });

  testWidgets('focused receiver button survives parent rebuild', (
    tester,
  ) async {
    final nativeApi = _FakeReceiverNativeApi();
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: supportedAppLocales,
        locale: const Locale('en'),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ReceiverHomePage(
              nativeApi: nativeApi,
              showNativeSurface: false,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_focusedDebugLabel(), 'Fullscreen');

    rebuild(() {});
    await tester.pumpAndSettle();

    expect(_focusedDebugLabel(), 'Fullscreen');
  });

  testWidgets('video surface is not focusable', (tester) async {
    await _pumpReceiverApp(tester, _FakeReceiverNativeApi());

    final videoFocus = tester.widget<Focus>(
      find.byKey(const Key('receiver.videoSurfaceFocusBoundary')),
    );

    expect(videoFocus.canRequestFocus, isFalse);
    expect(videoFocus.descendantsAreFocusable, isFalse);
    expect(videoFocus.descendantsAreTraversable, isFalse);
    expect(_focusedDebugLabel(), isNot('Waiting for PC video frames'));
  });
}

Future<void> _pumpReceiverApp(
  WidgetTester tester,
  _FakeReceiverNativeApi nativeApi,
) async {
  await tester.pumpWidget(
    AndroidTvReceiverApp(nativeApi: nativeApi, showNativeSurface: false),
  );
  await tester.pumpAndSettle();
}

String? _focusedDebugLabel() {
  return FocusManager.instance.primaryFocus?.debugLabel;
}

final class _FakeReceiverNativeApi implements ReceiverNativeApi {
  _FakeReceiverNativeApi({this.startState = MirrorSessionState.listening});

  final MirrorSessionState startState;
  int? startedPort;
  int startCalls = 0;
  int stopCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;

  @override
  Future<ReceiverCapabilities> getCapabilities() async {
    return const ReceiverCapabilities(
      deviceId: 'android-tv-dev',
      deviceName: 'Android TV Dev',
      videoCodecs: [VideoCodec.h264],
      maxWidth: 1920,
      maxHeight: 1080,
      maxFps: 30,
      lowLatencyDecoder: true,
    );
  }

  @override
  Future<ReceiverSessionSnapshot> startReceiver({required int port}) async {
    startedPort = port;
    startCalls += 1;
    return _snapshot(
      state: startState,
      userMessage: 'Listening for a Windows sender.',
      decoderReady: true,
      surfaceRendererReady: true,
      releasedToSurfaceFrames: startState == MirrorSessionState.streaming
          ? 1
          : 0,
    );
  }

  @override
  Future<ReceiverSessionSnapshot> stopReceiver() async {
    stopCalls += 1;
    return _snapshot(
      state: MirrorSessionState.idle,
      userMessage: 'Receiver stopped.',
      decoderReady: false,
      surfaceRendererReady: false,
    );
  }

  @override
  Future<ReceiverSessionSnapshot> getReceiverStatus() async {
    return _snapshot(
      state: startState,
      userMessage: 'Listening for a Windows sender.',
      decoderReady: true,
      surfaceRendererReady: true,
      releasedToSurfaceFrames: startState == MirrorSessionState.streaming
          ? 1
          : 0,
    );
  }

  @override
  Future<ReceiverSessionSnapshot> setAudioMuted(bool muted) async {
    return _snapshot(
      state: startState,
      userMessage: 'Listening for a Windows sender.',
      decoderReady: true,
      surfaceRendererReady: true,
      releasedToSurfaceFrames: startState == MirrorSessionState.streaming
          ? 1
          : 0,
    );
  }

  @override
  Future<ReceiverSessionSnapshot> sendPlaybackCommand(String command) async {
    if (command == 'pause') {
      pauseCalls += 1;
      return _snapshot(
        state: MirrorSessionState.paused,
        userMessage: 'Playback paused.',
        decoderReady: true,
        surfaceRendererReady: true,
        releasedToSurfaceFrames: 1,
      );
    }
    resumeCalls += 1;
    return _snapshot(
      state: MirrorSessionState.resuming,
      userMessage: 'Playback resuming.',
      decoderReady: true,
      surfaceRendererReady: true,
      releasedToSurfaceFrames: 1,
    );
  }
}

ReceiverSessionSnapshot _snapshot({
  required MirrorSessionState state,
  required String userMessage,
  required bool decoderReady,
  required bool surfaceRendererReady,
  int releasedToSurfaceFrames = 0,
}) {
  return ReceiverSessionSnapshot(
    state: state,
    userMessage: userMessage,
    receiverPort: 50720,
    decoderReady: decoderReady,
    surfaceRendererReady: surfaceRendererReady,
    releasedToSurfaceFrames: releasedToSurfaceFrames,
  );
}
