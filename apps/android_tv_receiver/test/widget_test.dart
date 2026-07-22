import 'package:android_tv_receiver/app/android_tv_receiver_app.dart';
import 'package:android_tv_receiver/core/native_bridge/receiver_native_api.dart';
import 'package:android_tv_receiver/features/receiver/receiver_home_page.dart';
import 'package:android_tv_receiver/widgets/tv_focus_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

void main() {
  testWidgets('starts the native receiver in video-only STAGE 1 mode', (
    tester,
  ) async {
    final nativeApi = _FakeReceiverNativeApi();

    await _pumpReceiverApp(tester, nativeApi);

    expect(nativeApi.startedPort, 50720);
    expect(find.text('Waiting for PC video frames'), findsOneWidget);
    expect(find.text('State: negotiating'), findsOneWidget);
    expect(find.text('h264 1280x720@30'), findsOneWidget);
  });

  testWidgets('initial focus is Restart receiver', (tester) async {
    await _pumpReceiverApp(tester, _FakeReceiverNativeApi());

    expect(_focusedDebugLabel(), 'Restart receiver');
  });

  testWidgets('D-pad down moves focus to the next ordered button', (
    tester,
  ) async {
    await _pumpReceiverApp(tester, _FakeReceiverNativeApi());

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

  testWidgets('streaming state restores focus to Stop receiver', (
    tester,
  ) async {
    await _pumpReceiverApp(
      tester,
      _FakeReceiverNativeApi(startState: MirrorSessionState.streaming),
    );

    expect(_focusedDebugLabel(), 'Stop receiver');
  });

  testWidgets('waiting label is hidden after the first rendered frame', (
    tester,
  ) async {
    await _pumpReceiverApp(
      tester,
      _FakeReceiverNativeApi(startState: MirrorSessionState.streaming),
    );

    expect(find.text('Waiting for PC video frames'), findsNothing);
    expect(find.text('State: streaming'), findsOneWidget);
  });

  testWidgets('focused receiver button survives parent rebuild', (
    tester,
  ) async {
    final nativeApi = _FakeReceiverNativeApi();
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
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

    expect(_focusedDebugLabel(), 'Stop receiver');

    rebuild(() {});
    await tester.pumpAndSettle();

    expect(_focusedDebugLabel(), 'Stop receiver');
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
  _FakeReceiverNativeApi({this.startState = MirrorSessionState.negotiating});

  final MirrorSessionState startState;
  int? startedPort;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<ReceiverCapabilities> getCapabilities() async {
    return const ReceiverCapabilities(
      deviceId: 'android-tv-dev',
      deviceName: 'Android TV Dev',
      videoCodecs: [VideoCodec.h264],
      maxWidth: 1280,
      maxHeight: 720,
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
      renderedFrames: startState == MirrorSessionState.streaming ? 1 : 0,
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
      renderedFrames: startState == MirrorSessionState.streaming ? 1 : 0,
    );
  }
}

ReceiverSessionSnapshot _snapshot({
  required MirrorSessionState state,
  required String userMessage,
  required bool decoderReady,
  required bool surfaceRendererReady,
  int renderedFrames = 0,
}) {
  return ReceiverSessionSnapshot(
    state: state,
    userMessage: userMessage,
    receiverPort: 50720,
    decoderReady: decoderReady,
    surfaceRendererReady: surfaceRendererReady,
    renderedFrames: renderedFrames,
  );
}
