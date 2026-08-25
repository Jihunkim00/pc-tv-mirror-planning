// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';

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
  late final GlobalKey _videoSurfaceKey;
  late final FocusNode _restartFocusNode;
  late final FocusNode _fullscreenFocusNode;
  late final FocusNode _stopFocusNode;
  MirrorSessionState? _lastRestoredState;
  bool _focusRestoreScheduled = false;
  int _focusRestoreRetryCount = 0;
  bool _fullscreenMode = false;
  bool _autoFullscreen = true;
  bool _showPlaybackDebug = false;
  bool _autoFullscreenEnteredForSession = false;
  bool _userExitedFullscreen = false;
  String _scaleMode = 'fit';
  int _lastRemoteActionMs = 0;
  int? _lastConnectionId;

  static const MethodChannel _receiverControlsChannel = MethodChannel(
    'pc_tv_mirror/receiver_controls',
  );

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
    _videoSurfaceKey = GlobalKey(debugLabel: 'receiverVideoSurface');
    _restartFocusNode = FocusNode(debugLabel: 'Restart receiver');
    _fullscreenFocusNode = FocusNode(debugLabel: 'Fullscreen');
    _stopFocusNode = FocusNode(debugLabel: 'Stop receiver');
    _controller = ReceiverController(widget.nativeApi);
    _controller.addListener(_handleControllerChanged);
    _receiverControlsChannel.setMethodCallHandler(_handleNativeRemoteAction);
    _controller.initialize();
    _scheduleFocusRestore();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _sendFullscreenStateToNative(false);
    _receiverControlsChannel.setMethodCallHandler(null);
    _setFullscreenSystemUi(false);
    _controller.dispose();
    _restartFocusNode.dispose();
    _fullscreenFocusNode.dispose();
    _stopFocusNode.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    _scheduleFocusRestore();
    final snapshot = _controller.snapshot;
    final connectionId = snapshot?.connectionId ?? 0;
    if (_lastConnectionId != connectionId) {
      _lastConnectionId = connectionId;
      _autoFullscreenEnteredForSession = false;
      _userExitedFullscreen = false;
    }
    if (_autoFullscreen &&
        !_autoFullscreenEnteredForSession &&
        !_userExitedFullscreen &&
        widget.showNativeSurface &&
        !_fullscreenMode &&
        _controller.state == MirrorSessionState.streaming &&
        (snapshot?.releasedToSurfaceFrames ?? 0) > 0) {
      _enterFullscreen(automatic: true);
    }
  }

  void _restartReceiver() {
    _controller.initialize();
    _scheduleFocusRestore();
  }

  void _stopReceiver() {
    _controller.stop();
    if (_fullscreenMode) {
      _exitFullscreen();
    }
    _scheduleFocusRestore();
  }

  void _enterFullscreen({bool automatic = false, bool explicit = false}) {
    if (_fullscreenMode || !mounted) {
      return;
    }
    setState(() {
      _fullscreenMode = true;
      if (automatic) {
        _autoFullscreenEnteredForSession = true;
      }
      if (explicit) {
        _userExitedFullscreen = false;
      }
    });
    _sendFullscreenStateToNative(true);
    _setFullscreenSystemUi(true);
  }

  void _exitFullscreen({bool userInitiatedBack = false}) {
    if (!_fullscreenMode || !mounted) {
      return;
    }
    setState(() {
      _fullscreenMode = false;
      if (userInitiatedBack) {
        _userExitedFullscreen = true;
      }
    });
    _sendFullscreenStateToNative(false);
    _setFullscreenSystemUi(false);
    _scheduleFocusRestore();
  }

  Future<dynamic> _handleNativeRemoteAction(MethodCall call) async {
    if (call.method != 'remoteAction') {
      return null;
    }
    final args = call.arguments;
    final action = args is Map ? args['action'] as String? : null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastRemoteActionMs < 250) {
      return null;
    }
    _lastRemoteActionMs = nowMs;
    if (action == 'exitFullscreen' && _fullscreenMode) {
      _exitFullscreen(userInitiatedBack: true);
    } else if (action == 'playPause' && _fullscreenMode) {
      unawaited(_togglePlaybackPause());
    } else if (action == 'toggleFullscreen') {
      if (!_fullscreenMode && _canEnterFullscreen) {
        _enterFullscreen(explicit: true);
      }
    }
    return null;
  }

  bool get _canEnterFullscreen {
    return _controller.state == MirrorSessionState.streaming ||
        _controller.state == MirrorSessionState.paused ||
        _controller.state == MirrorSessionState.resuming;
  }

  Future<void> _togglePlaybackPause() async {
    if (_controller.pauseCommandPending || _controller.resumeCommandPending) {
      return;
    }
    if (_controller.state == MirrorSessionState.streaming) {
      await _controller.pausePlayback();
    } else if (_controller.state == MirrorSessionState.paused) {
      await _controller.resumePlayback();
    }
  }

  void _sendFullscreenStateToNative(bool enabled) {
    unawaited(
      _receiverControlsChannel.invokeMethod<void>('setFullscreenState', {
        'enabled': enabled,
      }),
    );
  }

  Future<void> _setFullscreenSystemUi(bool enabled) async {
    if (enabled) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const []);
    }
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
    final controls = [_restartFocusNode, _fullscreenFocusNode, _stopFocusNode];
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
      MirrorSessionState.streaming ||
      MirrorSessionState.paused ||
      MirrorSessionState.resuming => _fullscreenFocusNode,
      MirrorSessionState.idle ||
      MirrorSessionState.starting ||
      MirrorSessionState.listening ||
      MirrorSessionState.connecting ||
      MirrorSessionState.negotiating ||
      MirrorSessionState.waitingForSurface ||
      MirrorSessionState.waitingForKeyFrame ||
      MirrorSessionState.disconnected ||
      MirrorSessionState.error ||
      MirrorSessionState.stopping ||
      MirrorSessionState.restoring ||
      MirrorSessionState.failed => _restartFocusNode,
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
      canPop: !_fullscreenMode,
      child: Focus(
        skipTraversal: true,
        onKeyEvent: _handleTvRemoteKey,
        child: Shortcuts(
          shortcuts: _tvRemoteShortcuts,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Scaffold(
              backgroundColor: Colors.black,
              body: _fullscreenMode
                  ? _VideoSurface(
                      key: _videoSurfaceKey,
                      showNativeSurface: widget.showNativeSurface,
                      controller: _controller,
                      scaleMode: _scaleMode,
                      showPlaybackDebug: _showPlaybackDebug,
                      fullscreen: true,
                    )
                  : SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _VideoSurface(
                                key: _videoSurfaceKey,
                                showNativeSurface: widget.showNativeSurface,
                                controller: _controller,
                                scaleMode: _scaleMode,
                                showPlaybackDebug: _showPlaybackDebug,
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
                                  fullscreenFocusNode: _fullscreenFocusNode,
                                  stopFocusNode: _stopFocusNode,
                                  autoFullscreen: _autoFullscreen,
                                  autoFullscreenEnteredForSession:
                                      _autoFullscreenEnteredForSession,
                                  userExitedFullscreen: _userExitedFullscreen,
                                  scaleMode: _scaleMode,
                                  fullscreenEnabled: _fullscreenMode,
                                  showPlaybackDebug: _showPlaybackDebug,
                                  onRestart: _restartReceiver,
                                  onEnterFullscreen: () =>
                                      _enterFullscreen(explicit: true),
                                  onStop: _stopReceiver,
                                  onAutoFullscreenChanged: (value) {
                                    setState(() {
                                      _autoFullscreen = value;
                                    });
                                  },
                                  onScaleModeChanged: (value) {
                                    setState(() {
                                      _scaleMode = value;
                                    });
                                  },
                                  onPlaybackDebugChanged: (value) {
                                    setState(() {
                                      _showPlaybackDebug = value;
                                    });
                                  },
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
    final key = event.logicalKey;
    final isToggleKey =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    final isBackKey =
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape;
    if (_fullscreenMode) {
      if (event is KeyUpEvent && isBackKey) {
        _exitFullscreen(userInitiatedBack: true);
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent && isToggleKey) {
        unawaited(_togglePlaybackPause());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaPlayPause) {
        return KeyEventResult.handled;
      }
      return isBackKey || isToggleKey
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      if (_restartFocusNode.hasFocus && _fullscreenFocusNode.canRequestFocus) {
        _fullscreenFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_fullscreenFocusNode.hasFocus && _stopFocusNode.canRequestFocus) {
        _stopFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      if (_stopFocusNode.hasFocus && _fullscreenFocusNode.canRequestFocus) {
        _fullscreenFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_fullscreenFocusNode.hasFocus && _restartFocusNode.canRequestFocus) {
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
    required this.scaleMode,
    this.fullscreen = false,
    required this.showPlaybackDebug,
    super.key,
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
  final bool showNativeSurface;
  final ReceiverController controller;
  final String scaleMode;
  final bool fullscreen;
  final bool showPlaybackDebug;

  @override
  Widget build(BuildContext context) {
    final usePlatformView =
        showNativeSurface && defaultTargetPlatform == TargetPlatform.android;
    final creationParams = <String, Object?>{
      'backend': _videoSurfaceBackend,
      'zOrderMode': _surfaceZOrderMode,
      'debugSurfaceColor': _debugSurfaceColor,
      'scaleMode': scaleMode,
    };
    final video = Stack(
      fit: StackFit.expand,
      children: [
        if (usePlatformView)
          AndroidView(
            key: const ValueKey<String>('receiver.androidVideoSurface'),
            viewType: 'pc_tv_mirror/video_surface',
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
          )
        else
          const ColoredBox(color: Colors.black),
        if (!fullscreen)
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
        if (showPlaybackDebug)
          Positioned(
            left: 8,
            top: 8,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) =>
                    _PlaybackDebugOverlay(snapshot: controller.snapshot),
              ),
            ),
          ),
      ],
    );
    return Focus(
      key: const Key('receiver.videoSurfaceFocusBoundary'),
      canRequestFocus: false,
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      child: fullscreen
          ? ColoredBox(color: Colors.black, child: video)
          : DecoratedBox(
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
                    child: video,
                  ),
                ),
              ),
            ),
    );
  }
}

class _PlaybackDebugOverlay extends StatelessWidget {
  const _PlaybackDebugOverlay({required this.snapshot});

  final ReceiverSessionSnapshot? snapshot;

  String _rate(double value) =>
      value <= 0 ? 'unavailable' : value.toStringAsFixed(1);
  String _ms(double value) =>
      value <= 0 ? 'unavailable' : value.toStringAsFixed(1) + ' ms';

  @override
  Widget build(BuildContext context) {
    final value = snapshot;
    final lines = <String>[
      'VIDEO DEBUG',
      'Render mode ' + (value?.rendererMode ?? 'immediate'),
      'Release immediate/scheduled ' +
          (value?.immediateRenderFrames ?? 0).toString() +
          ' / ' +
          (value?.scheduledRenderFrames ?? 0).toString(),
      'Input ' +
          _rate(value?.receivedAccessUnitFps ?? 0) +
          '  Decoder ' +
          _rate(value?.decoderOutputFps ?? 0),
      'Codec rendered ' + _rate(value?.codecRenderedFpsRecent ?? 0),
      'Render p50/p95/max ' +
          _ms(value?.renderedIntervalP50Ms ?? 0) +
          ' / ' +
          _ms(value?.renderedIntervalP95Ms ?? 0) +
          ' / ' +
          _ms(value?.renderedIntervalMaxMs ?? 0),
      'Jitter p95 ' +
          _ms(value?.renderedJitterP95Ms ?? 0) +
          '  Gaps ' +
          (value?.longFrameGapCountRecent ?? 0).toString(),
      'Drops ' +
          (value?.droppedFrames ?? 0).toString() +
          '  PTS ' +
          (value?.videoPtsSource ?? 'unavailable') +
          ' drift ' +
          _ms(value?.ptsDriftMs ?? 0),
      'Display ' +
          (value?.displayWidth ?? 0).toString() +
          'x' +
          (value?.displayHeight ?? 0).toString() +
          '@' +
          _rate(value?.displayRefreshRateHz ?? 0),
      'Surface ' +
          _rate(value?.surfaceRequestedRateFps ?? 0) +
          '  Mode ' +
          (value?.frameRateModeMatch ?? 'NOT_MATCHED'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          lines.join('\n'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.15,
            fontFamily: 'monospace',
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
    required this.fullscreenFocusNode,
    required this.stopFocusNode,
    required this.autoFullscreen,
    required this.autoFullscreenEnteredForSession,
    required this.userExitedFullscreen,
    required this.scaleMode,
    required this.fullscreenEnabled,
    required this.onRestart,
    required this.onEnterFullscreen,
    required this.onStop,
    required this.onAutoFullscreenChanged,
    required this.onScaleModeChanged,
    required this.showPlaybackDebug,
    required this.onPlaybackDebugChanged,
  });

  final ReceiverController controller;
  final FocusNode restartFocusNode;
  final FocusNode fullscreenFocusNode;
  final FocusNode stopFocusNode;
  final bool autoFullscreen;
  final bool autoFullscreenEnteredForSession;
  final bool userExitedFullscreen;
  final String scaleMode;
  final bool fullscreenEnabled;
  final VoidCallback onRestart;
  final VoidCallback onEnterFullscreen;
  final VoidCallback onStop;
  final ValueChanged<bool> onAutoFullscreenChanged;
  final ValueChanged<String> onScaleModeChanged;
  final bool showPlaybackDebug;
  final ValueChanged<bool> onPlaybackDebugChanged;

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
                  'PC to TV Mirror',
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
              autofocus:
                  controller.state != MirrorSessionState.streaming &&
                  controller.state != MirrorSessionState.paused &&
                  controller.state != MirrorSessionState.resuming,
              enabled: !controller.busy,
              onPressed: onRestart,
              onNextFocus: fullscreenFocusNode.requestFocus,
              icon: Icons.refresh,
              label: 'Restart receiver',
            ),
          ),
          const SizedBox(height: 10),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: TvFocusButton(
              key: const Key('receiver.fullscreenButton'),
              focusNode: fullscreenFocusNode,
              autofocus:
                  controller.state == MirrorSessionState.streaming ||
                  controller.state == MirrorSessionState.paused ||
                  controller.state == MirrorSessionState.resuming,
              enabled: !controller.busy && !fullscreenEnabled,
              onPressed: onEnterFullscreen,
              onPreviousFocus: restartFocusNode.requestFocus,
              onNextFocus: stopFocusNode.requestFocus,
              icon: Icons.fullscreen,
              label: 'Fullscreen',
            ),
          ),
          const SizedBox(height: 10),
          FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: TvFocusButton(
              key: const Key('receiver.stopButton'),
              focusNode: stopFocusNode,
              enabled: !controller.busy,
              onPressed: onStop,
              onPreviousFocus: fullscreenFocusNode.requestFocus,
              icon: Icons.stop,
              label: 'Stop receiver',
            ),
          ),
          const SizedBox(height: 18),

          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: autoFullscreen,
              onChanged: onAutoFullscreenChanged,
              title: const Text('Auto fullscreen'),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('FPS debug overlay'),
              subtitle: const Text('Actual codec render/display timing'),
              value: showPlaybackDebug,
              onChanged: onPlaybackDebugChanged,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'fit', label: Text('Fit')),
              ButtonSegment(value: 'fill', label: Text('Fill')),
            ],
            selected: {scaleMode},
            onSelectionChanged: (values) => onScaleModeChanged(values.first),
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
            label: '4K',
            value:
                '${capabilities?.supports4k30 ?? snapshot?.receiverSupports4k30 ?? false} '
                '${snapshot?.receiverMaxVideoWidth ?? capabilities?.maxWidth ?? 0}x'
                '${snapshot?.receiverMaxVideoHeight ?? capabilities?.maxHeight ?? 0}',
          ),
          _MetricRow(
            label: 'Decoder',
            value: snapshot?.decoderReady == true
                ? snapshot?.receiverDecoderName ??
                      capabilities?.decoderName ??
                      'MediaCodec ready'
                : 'Checking',
          ),
          _MetricRow(
            label: 'Surface',
            value: snapshot?.surfaceRendererReady == true
                ? 'SurfaceView ready'
                : 'Pending',
          ),
          const SizedBox(height: 18),
          Text('Performance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _MetricRow(
            label: 'Summary',
            value: snapshot?.bottleneckSummary ?? 'warming_up',
          ),
          _MetricRow(
            label: 'Receive / Decode / Present',
            value:
                '${(snapshot?.receivedAccessUnitFps ?? 0).toStringAsFixed(1)} / '
                '${(snapshot?.decoderOutputFps ?? 0).toStringAsFixed(1)} / '
                '${(snapshot?.releasedToSurfaceFps ?? 0).toStringAsFixed(1)} fps',
          ),
          _MetricRow(
            label: 'Present p95',
            value:
                '${(snapshot?.presentedFrameIntervalP95Ms ?? 0).toStringAsFixed(1)} ms',
          ),
          _MetricRow(
            label: 'Latency avg/p95',
            value:
                '${(snapshot?.latencyAverageMs ?? 0).toStringAsFixed(1)}/'
                '${(snapshot?.latencyP95Ms ?? 0).toStringAsFixed(1)} ms',
          ),
          _MetricRow(
            label: 'Renderer',
            value: snapshot?.rendererMode ?? 'lowLatencyPaced',
          ),
          _MetricRow(
            label: 'Queue',
            value:
                '${snapshot?.receiverQueueDepth ?? 0}/${snapshot?.maxReceiverQueueDepth ?? 0}',
          ),
          _MetricRow(
            label: 'Drops',
            value:
                'stale ${snapshot?.staleAccessUnitsDropped ?? 0}, late ${snapshot?.lateOutputBuffersDropped ?? 0}',
          ),
          _MetricRow(
            label: 'Sequence gaps',
            value: '${snapshot?.frameSequenceGaps ?? 0}',
          ),
          const SizedBox(height: 18),
          Text('Audio', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: snapshot?.audioMuted ?? false,
            onChanged: (value) => controller.setAudioMuted(value),
            title: Text('Audio: ${snapshot?.audioState ?? 'idle'}'),
          ),
          _MetricRow(
            label: 'Codec',
            value:
                '${snapshot?.audioCodec ?? 'audio/mp4a-latm'} ${snapshot?.audioSampleRate ?? 0} Hz ${snapshot?.audioChannels ?? 0} ch',
          ),
          _MetricRow(
            label: 'Decoder',
            value:
                '${snapshot?.audioDecoderState ?? 'released'} / ${snapshot?.audioDecoderName ?? 'unknown'}',
          ),
          _MetricRow(
            label: 'Track',
            value:
                '${snapshot?.audioTrackState ?? 'NONE'} / ${snapshot?.audioTrackPlayState ?? 'STOPPED'}',
          ),
          _MetricRow(
            label: 'Audio session',
            value:
                '${snapshot?.receiverSessionGeneration ?? 0}/${snapshot?.audioSessionGeneration ?? 0}',
          ),
          _MetricRow(
            label: 'Queue / PCM',
            value:
                '${snapshot?.audioQueueDepth ?? 0}/${snapshot?.pcmQueueDepth ?? 0}',
          ),
          _MetricRow(
            label: 'Buffered',
            value:
                '${(snapshot?.audioBufferedDurationMs ?? 0).toStringAsFixed(1)} ms',
          ),
          _MetricRow(
            label: 'A/V sync',
            value:
                '${(snapshot?.avSyncOffsetMs ?? 0).toStringAsFixed(1)} ms '
                '(${snapshot?.syncMaster ?? 'videoLocal'})',
          ),
          _MetricRow(
            label: 'A/V avg/p95',
            value:
                '${(snapshot?.avSyncAverageMs ?? 0).toStringAsFixed(1)}/'
                '${(snapshot?.avSyncP95Ms ?? 0).toStringAsFixed(1)} ms',
          ),
          _MetricRow(
            label: 'Audio packets',
            value:
                '${snapshot?.receivedAudioPackets ?? 0}/${snapshot?.audioDecoderInputPackets ?? 0}/${snapshot?.audioDecoderOutputBuffers ?? 0} '
                '(${(snapshot?.audioPacketsReceivedRecent ?? 0).toStringAsFixed(1)}/s)',
          ),
          _MetricRow(
            label: 'Audio writes',
            value:
                '${snapshot?.audioTrackWrittenFrames ?? 0}f/${snapshot?.audioBytesWritten ?? 0}B '
                '${(snapshot?.audioBytesWrittenRecent ?? 0).toStringAsFixed(0)}B/s',
          ),
          _MetricRow(
            label: 'Audio recovery',
            value:
                'recreate ${snapshot?.audioTrackRecreatedCount ?? 0}, '
                'write ${snapshot?.audioTrackWriteErrorCount ?? 0}, '
                'dead ${snapshot?.audioTrackDeadObjectCount ?? 0}',
          ),
          _MetricRow(
            label: 'Audio reset',
            value:
                '${snapshot?.audioSessionResetCount ?? 0}, pts ${snapshot?.audioPtsResetCount ?? 0}',
          ),
          _MetricRow(
            label: 'Audio expected',
            value:
                '${snapshot?.tvAudioAudibleExpected ?? false}, play ${snapshot?.audioTrackPlayCalled ?? false}',
          ),
          _MetricRow(
            label: 'Audio drops',
            value:
                '${snapshot?.audioDroppedPackets ?? 0}, av ${snapshot?.videoFramesDroppedForAvSync ?? 0}',
          ),
          if ((snapshot?.lastAudioSessionResetReason ?? '').isNotEmpty)
            _MetricRow(
              label: 'Audio reset reason',
              value: snapshot!.lastAudioSessionResetReason,
            ),
          if (snapshot?.audioLastError != null)
            _MetricRow(label: 'Audio error', value: snapshot!.audioLastError!),
          const SizedBox(height: 18),
          Text('Presentation', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _MetricRow(label: 'Fullscreen', value: '$fullscreenEnabled'),
          _MetricRow(label: 'Auto fullscreen', value: '$autoFullscreen'),
          _MetricRow(
            label: 'Auto entered',
            value: '$autoFullscreenEnteredForSession',
          ),
          _MetricRow(label: 'User exited', value: '$userExitedFullscreen'),
          _MetricRow(
            label: 'Playback',
            value:
                '${snapshot?.playbackState ?? controller.state.wireName} '
                'pause ${snapshot?.pauseCommandPending ?? false} '
                'resume ${snapshot?.resumeCommandPending ?? false}',
          ),
          _MetricRow(label: 'Scale mode', value: scaleMode),
          _MetricRow(
            label: 'Display',
            value:
                '${snapshot?.containerWidth ?? 0}x${snapshot?.containerHeight ?? 0}',
          ),
          _MetricRow(
            label: 'Video view',
            value:
                '${snapshot?.renderedViewWidth ?? 0}x${snapshot?.renderedViewHeight ?? 0}',
          ),
          _MetricRow(
            label: 'Aspect error',
            value: (snapshot?.aspectRatioError ?? 0).toStringAsFixed(4),
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
            label: 'Decoder input/output',
            value:
                '${snapshot?.decoderInputFrames ?? 0}/${snapshot?.decoderOutputFrames ?? 0}',
          ),
          _MetricRow(
            label: 'Released to surface',
            value: '${snapshot?.releasedToSurfaceFrames ?? 0}',
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
            label: 'Configured/output',
            value:
                '${snapshot?.configuredWidth ?? 0}x${snapshot?.configuredHeight ?? 0} / '
                '${snapshot?.outputWidth ?? 0}x${snapshot?.outputHeight ?? 0}',
          ),
          if (outputCrop != null)
            _MetricRow(label: 'Output crop', value: outputCrop),
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
