import 'dart:async';

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

    await tester.drag(
      find.byKey(const Key('receiver.settingsScroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.text('Auto fullscreen'), findsOneWidget);
  });

  testWidgets('connection info stays visible outside the settings scroll', (
    tester,
  ) async {
    final nativeApi = _FakeReceiverNativeApi(
      localIpv4Addresses: ['192.168.1.40', '10.20.30.4'],
      receiverPort: 54123,
    );
    await _pumpReceiverApp(tester, nativeApi);

    final panel = find.byKey(const Key('receiver.connectionInfoPanel'));
    final settings = find.byKey(const Key('receiver.settingsScroll'));
    expect(find.text('PC connection info'), findsOneWidget);
    expect(find.text('TV IP address'), findsOneWidget);
    expect(find.text('192.168.1.40'), findsOneWidget);
    expect(find.text('10.20.30.4'), findsOneWidget);
    expect(find.text('54123'), findsOneWidget);
    expect(find.text('192.168.1.40:54123'), findsNothing);
    expect(find.text('0.0.0.0'), findsNothing);
    expect(find.ancestor(of: panel, matching: settings), findsNothing);

    final panelRect = tester.getRect(panel);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: settings, matching: find.byType(Scrollable)),
    );
    await tester.drag(settings, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.text('192.168.1.40'), findsOneWidget);
    expect(tester.getRect(panel), panelRect);
  });

  testWidgets('address checking changes to an address when startup completes', (
    tester,
  ) async {
    final pendingStart = Completer<ReceiverSessionSnapshot>();
    final nativeApi = _FakeReceiverNativeApi(pendingStart: pendingStart);
    await _pumpReceiverApp(tester, nativeApi);

    expect(find.text('Checking IP address…'), findsOneWidget);

    nativeApi.localIpv4Addresses = ['10.20.30.40'];
    pendingStart.complete(
      _snapshot(
        state: MirrorSessionState.listening,
        userMessage: 'Listening for a Windows sender.',
        decoderReady: true,
        surfaceRendererReady: true,
        localIpv4Addresses: ['10.20.30.40'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('10.20.30.40'), findsOneWidget);
    expect(find.text('Checking IP address…'), findsNothing);
  });

  testWidgets('empty and failed address lookups show different messages', (
    tester,
  ) async {
    await _pumpReceiverApp(
      tester,
      _FakeReceiverNativeApi(localIpv4Addresses: []),
    );
    expect(find.text('Check the network connection.'), findsOneWidget);
    expect(find.text('0.0.0.0'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpReceiverApp(
      tester,
      _FakeReceiverNativeApi(addressLookupFailed: true),
    );
    expect(
      find.text("Couldn't check the IP address. Try again shortly."),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpReceiverApp(tester, _FakeReceiverNativeApi(startError: true));
    expect(
      find.text("Couldn't check the IP address. Try again shortly."),
      findsOneWidget,
    );
  });

  testWidgets('resume refreshes the address without restarting the receiver', (
    tester,
  ) async {
    final nativeApi = _FakeReceiverNativeApi(
      localIpv4Addresses: ['192.168.1.40'],
    );
    await _pumpReceiverApp(tester, nativeApi);

    nativeApi.localIpv4Addresses = ['10.20.30.40'];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('10.20.30.40'), findsOneWidget);
    expect(find.text('192.168.1.40'), findsNothing);
    expect(nativeApi.startCalls, 1);
    expect(nativeApi.stopCalls, 0);
    expect(nativeApi.statusCalls, greaterThan(0));
  });

  testWidgets(
    'network changes refresh addresses without restarting the receiver',
    (tester) async {
      final nativeApi = _FakeReceiverNativeApi(
        localIpv4Addresses: ['192.168.1.40'],
      );
      await _pumpReceiverApp(tester, nativeApi);

      nativeApi.localIpv4Addresses = ['10.20.30.40'];
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('10.20.30.40'), findsOneWidget);
      expect(find.text('192.168.1.40'), findsNothing);
      expect(nativeApi.startCalls, 1);
      expect(nativeApi.stopCalls, 0);
      expect(nativeApi.statusCalls, greaterThan(0));
    },
  );
  testWidgets('connection info returns after fullscreen exit', (tester) async {
    const controlsChannel = MethodChannel('pc_tv_mirror/receiver_controls');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlsChannel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlsChannel, null),
    );

    await _pumpReceiverApp(tester, _FakeReceiverNativeApi());
    expect(_focusedDebugLabel(), 'Restart receiver');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focusedDebugLabel(), 'Fullscreen');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('receiver.connectionInfoPanel')), findsNothing);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'pc_tv_mirror/receiver_controls',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('remoteAction', {'action': 'exitFullscreen'}),
          ),
          null,
        );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('receiver.connectionInfoPanel')),
      findsOneWidget,
    );
    expect(find.text('192.168.1.40'), findsOneWidget);
  });

  testWidgets(
    'connection info fits 720p and 1080p in all locales with one or several IPs',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final resolution in const [Size(1280, 720), Size(1920, 1080)]) {
        tester.view.physicalSize = resolution;
        for (final addresses in const <List<String>>[
          ['203.0.113.24'],
          ['203.0.113.24', '10.20.30.40'],
        ]) {
          for (final language in ['ko', 'en', 'ja']) {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            final nativeApi = _FakeReceiverNativeApi(
              localIpv4Addresses: addresses,
            );
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(language),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: supportedAppLocales,
                home: ReceiverHomePage(
                  nativeApi: nativeApi,
                  showNativeSurface: false,
                ),
              ),
            );
            await tester.pumpAndSettle();

            final panel = find.byKey(const Key('receiver.connectionInfoPanel'));
            final l10n = AppLocalizations.of(tester.element(panel));
            expect(tester.takeException(), isNull);
            expect(find.text(l10n.pcConnectionInfo), findsOneWidget);
            expect(
              tester
                  .widget<Text>(find.text(l10n.pcConnectionInfo))
                  .style
                  ?.fontSize,
              14,
            );
            expect(find.text(l10n.tvIpAddress), findsOneWidget);
            expect(
              tester.widget<Text>(find.text(l10n.tvIpAddress)).style?.fontSize,
              11,
            );
            expect(find.text(l10n.port), findsOneWidget);
            expect(
              tester.widget<Text>(find.text(l10n.port)).style?.fontSize,
              11,
            );
            expect(find.text(l10n.ipAddressEntryInstruction), findsOneWidget);
            for (final address in addresses) {
              expect(
                find.text(address),
                findsOneWidget,
                reason:
                    'Missing $address at ${resolution.width}x${resolution.height} in $language for $addresses.',
              );
            }
            final primaryAddressValue = addresses.length == 1
                ? addresses.first
                : '10.20.30.40';
            final primaryAddress = tester.widget<Text>(
              find.text(primaryAddressValue),
            );
            expect(primaryAddress.maxLines, isNull);
            expect(primaryAddress.overflow, isNull);
            expect(primaryAddress.style?.fontSize, 16);
            final instruction = find.text(l10n.ipAddressEntryInstruction);
            expect(tester.widget<Text>(instruction).style?.fontSize, 10);
            expect(tester.getSize(instruction).height, lessThan(14));
            expect(tester.widget<Text>(find.text('50720')).style?.fontSize, 14);
            expect(find.text('50720'), findsOneWidget);

            final panelRect = tester.getRect(panel);
            expect(panelRect.left, greaterThanOrEqualTo(0));
            expect(panelRect.right, lessThanOrEqualTo(resolution.width));
            expect(panelRect.bottom, lessThanOrEqualTo(resolution.height));
            expect(panelRect.height, lessThanOrEqualTo(130));
            if (resolution.height == 720) {
              for (final key in const [
                Key('receiver.restartButton'),
                Key('receiver.fullscreenButton'),
                Key('receiver.stopButton'),
                Key('receiver.autoFullscreenSetting'),
              ]) {
                final rect = tester.getRect(find.byKey(key));
                expect(rect.top, greaterThanOrEqualTo(0));
                expect(
                  rect.bottom,
                  lessThanOrEqualTo(resolution.height),
                  reason: 'Expected the control to remain visible at 720p.',
                );
              }
            }
            if (addresses.length == 1) {
              expect(
                find.byKey(const Key('receiver.additionalAddressesScroll')),
                findsNothing,
              );
            } else {
              expect(
                find.byKey(const Key('receiver.additionalAddressesScroll')),
                findsOneWidget,
              );
            }
          }
        }
      }
    },
  );

  testWidgets('many additional IPs use a capped D-pad scroll area', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    final nativeApi = _FakeReceiverNativeApi(
      localIpv4Addresses: List.generate(
        12,
        (index) => '192.168.1.${index + 1}',
      ),
    );
    await _pumpReceiverApp(tester, nativeApi);

    final panel = find.byKey(const Key('receiver.connectionInfoPanel'));
    final additionalList = find.byKey(
      const Key('receiver.additionalAddressesScroll'),
    );
    final additionalScrollable = tester.state<ScrollableState>(
      find.descendant(of: additionalList, matching: find.byType(Scrollable)),
    );
    final outerSettings = find.byKey(const Key('receiver.settingsScroll'));
    final outerScrollable = tester.state<ScrollableState>(
      find.descendant(of: outerSettings, matching: find.byType(Scrollable)),
    );

    expect(tester.getSize(additionalList).height, lessThanOrEqualTo(48));
    expect(additionalScrollable.position.maxScrollExtent, greaterThan(0));
    expect(find.text('192.168.1.1'), findsOneWidget);
    expect(find.text('50720'), findsOneWidget);
    expect(_focusedDebugLabel(), 'Restart receiver');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_focusedDebugLabel(), 'Additional TV IP addresses');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(additionalScrollable.position.pixels, greaterThan(0));
    expect(outerScrollable.position.pixels, 0);
    expect(find.text('192.168.1.1'), findsOneWidget);
    expect(find.text('50720'), findsOneWidget);
    expect(tester.getRect(panel).bottom, lessThanOrEqualTo(720));
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
      'localIpv4AddressesQueryFailed': true,
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
    expect(snapshot.localIpv4AddressesQueryFailed, isTrue);
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
  _FakeReceiverNativeApi({
    this.startState = MirrorSessionState.listening,
    this.localIpv4Addresses = const ['192.168.1.40'],
    this.receiverPort = 50720,
    this.addressLookupFailed = false,
    this.pendingStart,
    this.startError = false,
  });

  final MirrorSessionState startState;
  List<String> localIpv4Addresses;
  final int receiverPort;
  final bool addressLookupFailed;
  final Completer<ReceiverSessionSnapshot>? pendingStart;
  final bool startError;
  int? startedPort;
  int startCalls = 0;
  int stopCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int statusCalls = 0;

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
    if (startError) {
      throw StateError('Receiver startup failed.');
    }
    final pending = pendingStart;
    if (pending != null) {
      return pending.future;
    }
    return _makeSnapshot(
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
    return _makeSnapshot(
      state: MirrorSessionState.idle,
      userMessage: 'Receiver stopped.',
      decoderReady: false,
      surfaceRendererReady: false,
    );
  }

  @override
  Future<ReceiverSessionSnapshot> getReceiverStatus() async {
    statusCalls += 1;
    return _makeSnapshot(
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
    return _makeSnapshot(
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
      return _makeSnapshot(
        state: MirrorSessionState.paused,
        userMessage: 'Playback paused.',
        decoderReady: true,
        surfaceRendererReady: true,
        releasedToSurfaceFrames: 1,
      );
    }
    resumeCalls += 1;
    return _makeSnapshot(
      state: MirrorSessionState.resuming,
      userMessage: 'Playback resuming.',
      decoderReady: true,
      surfaceRendererReady: true,
      releasedToSurfaceFrames: 1,
    );
  }

  ReceiverSessionSnapshot _makeSnapshot({
    required MirrorSessionState state,
    required String userMessage,
    required bool decoderReady,
    required bool surfaceRendererReady,
    int releasedToSurfaceFrames = 0,
  }) {
    return _snapshot(
      state: state,
      userMessage: userMessage,
      decoderReady: decoderReady,
      surfaceRendererReady: surfaceRendererReady,
      releasedToSurfaceFrames: releasedToSurfaceFrames,
      receiverPort: receiverPort,
      localIpv4Addresses: localIpv4Addresses,
      localIpv4AddressesQueryFailed: addressLookupFailed,
    );
  }
}

ReceiverSessionSnapshot _snapshot({
  required MirrorSessionState state,
  required String userMessage,
  required bool decoderReady,
  required bool surfaceRendererReady,
  int releasedToSurfaceFrames = 0,
  int receiverPort = 50720,
  List<String> localIpv4Addresses = const [],
  bool localIpv4AddressesQueryFailed = false,
}) {
  return ReceiverSessionSnapshot(
    state: state,
    userMessage: userMessage,
    receiverPort: receiverPort,
    decoderReady: decoderReady,
    localIpv4Addresses: localIpv4Addresses,
    localIpv4AddressesQueryFailed: localIpv4AddressesQueryFailed,
    surfaceRendererReady: surfaceRendererReady,
    releasedToSurfaceFrames: releasedToSurfaceFrames,
  );
}
