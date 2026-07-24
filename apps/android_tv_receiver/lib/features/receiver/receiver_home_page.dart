import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

import '../../core/native_bridge/receiver_native_api.dart';
import '../../widgets/tv_focus_button.dart';
import 'receiver_controller.dart';

class ReceiverHomePage extends StatefulWidget {
  const ReceiverHomePage({
    required this.nativeApi,
    required this.showNativeSurface,
    super.key,
  });

  final ReceiverNativeApi nativeApi;
  final bool showNativeSurface;

  @override
  State<ReceiverHomePage> createState() => _ReceiverHomePageState();
}

class _ReceiverHomePageState extends State<ReceiverHomePage> {
  late final ReceiverController _controller;
  late final FocusNode _restartFocusNode;
  late final FocusNode _stopFocusNode;
  MirrorSessionState? _lastRestoredState;
  bool _focusRestoreScheduled = false;
  int _focusRestoreRetryCount = 0;

  static const Map<ShortcutActivator, Intent> _tvRemoteShortcuts = {
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.arrowRight): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
    SingleActivator(LogicalKeyboardKey.arrowLeft): PreviousFocusIntent(),
  };

  @override
  void initState() {
    super.initState();
    _restartFocusNode = FocusNode(debugLabel: 'Restart receiver');
    _stopFocusNode = FocusNode(debugLabel: 'Stop receiver');
    _controller = ReceiverController(widget.nativeApi)
      ..addListener(_scheduleFocusRestore)
      ..initialize();
    _scheduleFocusRestore();
  }

  @override
  void dispose() {
    _controller.removeListener(_scheduleFocusRestore);
    _controller.dispose();
    _restartFocusNode.dispose();
    _stopFocusNode.dispose();
    super.dispose();
  }

  void _restartReceiver() {
    _controller.initialize();
    _scheduleFocusRestore();
  }

  void _stopReceiver() {
    _controller.stop();
    _scheduleFocusRestore();
  }

  void _scheduleFocusRestore() {
    if (_focusRestoreScheduled) {
      return;
    }
    _focusRestoreScheduled = true;
    _focusRestoreRetryCount = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRestoreScheduled = false;
      if (!mounted) {
        return;
      }
      _restoreFocusForState();
    });
  }

  void _restoreFocusForState() {
    final state = _controller.state;
    final preferredNode = _preferredFocusNodeForState(state);
    final controls = [_restartFocusNode, _stopFocusNode];
    final controlsHaveFocus = controls.any((node) => node.hasFocus);
    final previousRestoredState = _lastRestoredState;
    final stateChanged = previousRestoredState != state;
    _lastRestoredState = state;

    if (controlsHaveFocus && (!stateChanged || previousRestoredState == null)) {
      return;
    }

    final fallbackNode = _firstFocusableNode(controls);
    final target = preferredNode.canRequestFocus ? preferredNode : fallbackNode;
    if (target == null || target.context?.mounted != true) {
      if (_focusRestoreRetryCount < 2) {
        _focusRestoreRetryCount += 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _restoreFocusForState();
          }
        });
        WidgetsBinding.instance.scheduleFrame();
      }
      return;
    }

    _focusRestoreRetryCount = 0;
    target.requestFocus();
  }

  FocusNode _preferredFocusNodeForState(MirrorSessionState state) {
    return switch (state) {
      MirrorSessionState.streaming => _stopFocusNode,
      MirrorSessionState.idle ||
      MirrorSessionState.starting ||
      MirrorSessionState.listening ||
      MirrorSessionState.connecting ||
      MirrorSessionState.negotiating ||
      MirrorSessionState.waitingForSurface ||
      MirrorSessionState.waitingForKeyFrame ||
      MirrorSessionState.stopping ||
      MirrorSessionState.restoring ||
      MirrorSessionState.failed =>
        _restartFocusNode,
    };
  }

  FocusNode? _firstFocusableNode(Iterable<FocusNode> nodes) {
    for (final node in nodes) {
      if (node.canRequestFocus) {
        return node;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: true,
      child: Focus(
        skipTraversal: true,
        onKeyEvent: _handleTvRemoteKey,
        child: Shortcuts(
          shortcuts: _tvRemoteShortcuts,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _VideoSurface(
                          showNativeSurface: widget.showNativeSurface,
                          controller: _controller,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 3,
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => _ReceiverStatusPanel(
                            controller: _controller,
                            restartFocusNode: _restartFocusNode,
                            stopFocusNode: _stopFocusNode,
                            onRestart: _restartReceiver,
                            onStop: _stopReceiver,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleTvRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      if (_restartFocusNode.hasFocus && _stopFocusNode.canRequestFocus) {
        _stopFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      if (_stopFocusNode.hasFocus && _restartFocusNode.canRequestFocus) {
        _restartFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({
    required this.showNativeSurface,
    required this.controller,
  });

  static const String _surfaceZOrderMode = String.fromEnvironment(
    'PC_TV_MIRROR_SURFACE_Z_ORDER',
    defaultValue: 'onTop',
  );
  static const String _videoSurfaceBackend = String.fromEnvironment(
    'PC_TV_MIRROR_VIDEO_SURFACE_BACKEND',
    defaultValue: 'surfaceView',
  );
  static const bool _debugSurfaceColor = bool.fromEnvironment(
    'PC_TV_MIRROR_DEBUG_SURFACE_COLOR',
  );
  static const Map<String, Object?> _creationParams = {
    'backend': _videoSurfaceBackend,
    'zOrderMode': _surfaceZOrderMode,
    'debugSurfaceColor': _debugSurfaceColor,
  };

  final bool showNativeSurface;
  final ReceiverController controller;

  @override
  Widget build(BuildContext context) {
    final usePlatformView =
        showNativeSurface && defaultTargetPlatform == TargetPlatform.android;
    return Focus(
      key: const Key('receiver.videoSurfaceFocusBoundary'),
      canRequestFocus: false,
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (usePlatformView)
                    const AndroidView(
                      key: ValueKey<String>('receiver.androidVideoSurface'),
                      viewType: 'pc_tv_mirror/video_surface',
                      creationParams: _creationParams,
                      creationParamsCodec: StandardMessageCodec(),
                    )
                  else
                    const ColoredBox(color: Colors.black),
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      final releasedFrames =
                          controller.snapshot?.releasedToSurfaceFrames ?? 0;
                      if (releasedFrames > 0) {
                        return const SizedBox.shrink();
                      }
                      return Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text('Waiting for PC video frames'),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiverStatusPanel extends StatelessWidget {
  const _ReceiverStatusPanel({
    required this.controller,
    required this.restartFocusNode,
    required this.stopFocusNode,
    required this.onRestart,
    required this.onStop,
  });

  final ReceiverController controller;
  final FocusNode restartFocusNode;
  final FocusNode stopFocusNode;
  final VoidCallback onRestart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final capabilities = controller.capabilities;
    final snapshot = controller.snapshot;
    final outputCrop = _formatCrop(snapshot);
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              const Icon(Icons.tv),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'PC TV Mirror',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _StatusBadge(
            label: controller.state.wireName,
            message: controller.statusMessage,
          ),
          const SizedBox(height: 18),
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: TvFocusButton(
              key: const Key('receiver.restartButton'),
              focusNode: restartFocusNode,
              autofocus: controller.state != MirrorSessionState.streaming,
              enabled: !controller.busy,
              onPressed: onRestart,
              onNextFocus: stopFocusNode.requestFocus,
              icon: Icons.refresh,
              label: 'Restart receiver',
            ),
          ),
          const SizedBox(height: 10),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: TvFocusButton(
              key: const Key('receiver.stopButton'),
              focusNode: stopFocusNode,
              autofocus: controller.state == MirrorSessionState.streaming,
              enabled: !controller.busy,
              onPressed: onStop,
              onPreviousFocus: restartFocusNode.requestFocus,
              icon: Icons.stop,
              label: 'Stop receiver',
            ),
          ),
          const SizedBox(height: 18),
          _MetricRow(
            label: 'Control port',
            value:
                '${snapshot?.receiverPort ?? ReceiverController.defaultPort}',
          ),
          _MetricRow(
            label: 'TV address',
            value: _formatReceiverAddresses(snapshot),
          ),
          _MetricRow(
            label: 'Protocol',
            value: '${capabilities?.protocolVersion ?? 1}',
          ),
          _MetricRow(
            label: 'Video',
            value: capabilities == null
                ? 'H.264 720p30'
                : '${capabilities.videoCodecs.map((codec) => codec.wireName).join(', ')} '
                    '${capabilities.maxWidth}x${capabilities.maxHeight}@${capabilities.maxFps}',
          ),
          _MetricRow(
            label: 'Decoder',
            value: snapshot?.decoderReady == true
                ? 'MediaCodec ready'
                : 'Checking',
          ),
          _MetricRow(
            label: 'Surface',
            value: snapshot?.surfaceRendererReady == true
                ? 'SurfaceView ready'
                : 'Pending',
          ),
          const SizedBox(height: 18),
          Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _MetricRow(label: 'Bytes', value: '${snapshot?.bytesReceived ?? 0}'),
          _MetricRow(
            label: 'Config',
            value: '${snapshot?.configPacketsReceived ?? 0}',
          ),
          _MetricRow(
            label: 'Access units',
            value: '${snapshot?.accessUnitsReceived ?? 0}',
          ),
          _MetricRow(
            label: 'Key frames',
            value: '${snapshot?.keyFramesReceived ?? 0}',
          ),
          _MetricRow(
            label: 'Decoder input',
            value: '${snapshot?.decoderInputFrames ?? 0}',
          ),
          _MetricRow(
            label: 'Decoder output',
            value: '${snapshot?.decoderOutputFrames ?? 0}',
          ),
          _MetricRow(
            label: 'Released to surface',
            value: '${snapshot?.releasedToSurfaceFrames ?? 0}',
          ),
          _MetricRow(
            label: 'Dropped',
            value: '${snapshot?.droppedFrames ?? 0}',
          ),
          _MetricRow(
            label: 'Codec create/release',
            value:
                '${snapshot?.codecCreateCount ?? 0}/${snapshot?.codecReleaseCount ?? 0}',
          ),
          _MetricRow(
            label: 'Surface lifecycle',
            value:
                '${snapshot?.surfaceCreatedCount ?? 0}/${snapshot?.surfaceChangedCount ?? 0}/${snapshot?.surfaceDestroyedCount ?? 0}',
          ),
          _MetricRow(
            label: 'Surface valid',
            value: '${snapshot?.surfaceIsValid ?? false}',
          ),
          _MetricRow(
            label: 'Surface size',
            value:
                '${snapshot?.surfaceWidth ?? 0}x${snapshot?.surfaceHeight ?? 0}',
          ),
          _MetricRow(
            label: 'Surface z-order',
            value: snapshot?.zOrderMode ?? 'unknown',
          ),
          _MetricRow(
            label: 'Surface test draw',
            value: '${snapshot?.firstSurfaceTestDrawSucceeded ?? false}',
          ),
          _MetricRow(
            label: 'Scale mode',
            value: snapshot?.scaleMode ?? 'fitCenter',
          ),
          _MetricRow(
            label: 'Container',
            value:
                '${snapshot?.containerWidth ?? 0}x${snapshot?.containerHeight ?? 0}',
          ),
          _MetricRow(
            label: 'Rendered view',
            value:
                '${snapshot?.renderedViewWidth ?? 0}x${snapshot?.renderedViewHeight ?? 0}',
          ),
          _MetricRow(
            label: 'Aspect error',
            value: (snapshot?.aspectRatioError ?? 0).toStringAsFixed(4),
          ),
          _MetricRow(
            label: 'Configured size',
            value:
                '${snapshot?.configuredWidth ?? 0}x${snapshot?.configuredHeight ?? 0}',
          ),
          _MetricRow(
            label: 'Output size',
            value:
                '${snapshot?.outputWidth ?? 0}x${snapshot?.outputHeight ?? 0}',
          ),
          _MetricRow(
            label: 'Output format changes',
            value: '${snapshot?.outputFormatChangedCount ?? 0}',
          ),
          if (outputCrop != null)
            _MetricRow(label: 'Output crop', value: outputCrop),
          _MetricRow(
            label: 'Input latency',
            value:
                '${(snapshot?.networkToDecoderInputMs ?? 0).toStringAsFixed(1)} ms',
          ),
          _MetricRow(
            label: 'Decode latency',
            value:
                '${(snapshot?.decoderInputToOutputMs ?? 0).toStringAsFixed(1)} ms',
          ),
          _MetricRow(
            label: 'Estimated latency',
            value:
                '${(snapshot?.estimatedEndToEndLatencyMs ?? 0).toStringAsFixed(1)} ms',
          ),
          _MetricRow(
            label: 'Latency avg/p95',
            value:
                '${(snapshot?.latencyAverageMs ?? 0).toStringAsFixed(1)}/${(snapshot?.latencyP95Ms ?? 0).toStringAsFixed(1)} ms',
          ),
          _MetricRow(
            label: 'Receiver backlog',
            value:
                '${snapshot?.maxReceiverQueueDepth ?? 0} max, ${snapshot?.staleAccessUnitsDropped ?? 0} stale drops',
          ),
          _MetricRow(
            label: 'Last frame age',
            value: '${(snapshot?.lastFrameAgeMs ?? 0).toStringAsFixed(1)} ms',
          ),
          if (snapshot?.lastDecoderError != null)
            _MetricRow(label: 'Last error', value: snapshot!.lastDecoderError!),
          const SizedBox(height: 18),
          Text('Receiver log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...controller.log.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(entry),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatReceiverAddresses(ReceiverSessionSnapshot? snapshot) {
  if (snapshot == null) {
    return '0.0.0.0:${ReceiverController.defaultPort}';
  }
  if (snapshot.localIpv4Addresses.isEmpty) {
    return '${snapshot.receiverBindAddress}:${snapshot.receiverPort}';
  }
  return snapshot.localIpv4Addresses
      .map((address) => '$address:${snapshot.receiverPort}')
      .join(', ');
}

String? _formatCrop(ReceiverSessionSnapshot? snapshot) {
  if (snapshot == null ||
      (snapshot.outputCropLeft == null &&
          snapshot.outputCropRight == null &&
          snapshot.outputCropTop == null &&
          snapshot.outputCropBottom == null)) {
    return null;
  }
  return 'l:${snapshot.outputCropLeft ?? '-'} '
      'r:${snapshot.outputCropRight ?? '-'} '
      't:${snapshot.outputCropTop ?? '-'} '
      'b:${snapshot.outputCropBottom ?? '-'}';
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.message});

  final String label;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text('State: $label'), Text(message)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
