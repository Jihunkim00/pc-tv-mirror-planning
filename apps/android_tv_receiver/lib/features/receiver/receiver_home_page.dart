// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mirror_protocol/mirror_protocol.dart';
import 'package:android_tv_receiver/l10n/generated/app_localizations.dart';

import '../../core/native_bridge/receiver_native_api.dart';
import '../../widgets/tv_focus_button.dart';
import 'receiver_controller.dart';
import 'receiver_address_display.dart';

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

class _ReceiverHomePageState extends State<ReceiverHomePage>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refreshStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        AppLocalizations.of(context).waitingForVideoFrames,
                      ),
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
    final l10n = AppLocalizations.of(context);
    final value = snapshot;
    final lines = <String>[
      l10n.videoDebug,
      l10n.renderMode + ' ' + (value?.rendererMode ?? 'immediate'),
      l10n.releaseImmediateScheduled +
          ' ' +
          (value?.immediateRenderFrames ?? 0).toString() +
          ' / ' +
          (value?.scheduledRenderFrames ?? 0).toString(),
      l10n.input +
          ' ' +
          _rate(value?.receivedAccessUnitFps ?? 0) +
          '  ' +
          l10n.decoder +
          ' ' +
          _rate(value?.decoderOutputFps ?? 0),
      l10n.codecRendered + ' ' + _rate(value?.codecRenderedFpsRecent ?? 0),
      l10n.renderP50P95Max +
          ' ' +
          _ms(value?.renderedIntervalP50Ms ?? 0) +
          ' / ' +
          _ms(value?.renderedIntervalP95Ms ?? 0) +
          ' / ' +
          _ms(value?.renderedIntervalMaxMs ?? 0),
      l10n.jitterP95 +
          ' ' +
          _ms(value?.renderedJitterP95Ms ?? 0) +
          '  ' +
          l10n.gaps +
          ' ' +
          (value?.longFrameGapCountRecent ?? 0).toString(),
      l10n.drops +
          ' ' +
          (value?.droppedFrames ?? 0).toString() +
          '  PTS ' +
          (value?.videoPtsSource ?? 'unavailable') +
          ' ' +
          l10n.drift +
          ' ' +
          _ms(value?.ptsDriftMs ?? 0),
      l10n.display +
          ' ' +
          (value?.displayWidth ?? 0).toString() +
          'x' +
          (value?.displayHeight ?? 0).toString() +
          '@' +
          _rate(value?.displayRefreshRateHz ?? 0),
      l10n.surface +
          ' ' +
          _rate(value?.surfaceRequestedRateFps ?? 0) +
          '  ' +
          l10n.mode +
          ' ' +
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
    final l10n = AppLocalizations.of(context);
    final capabilities = controller.capabilities;
    final snapshot = controller.snapshot;
    final outputCrop = _formatCrop(snapshot);
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: _ReceiverConnectionInfoPanel(controller: controller),
          ),
          Expanded(
            child: ListView(
              key: const Key('receiver.settingsScroll'),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
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
                  label: _receiverStateLabel(l10n, controller.state),
                  message: _receiverStatusMessage(l10n, controller.state),
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
                    label: l10n.restartReceiver,
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
                    label: l10n.fullscreen,
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
                    label: l10n.stopReceiver,
                  ),
                ),
                const SizedBox(height: 18),

                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    key: const Key('receiver.autoFullscreenSetting'),
                    value: autoFullscreen,
                    onChanged: onAutoFullscreenChanged,
                    title: Text(l10n.autoFullscreen),
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.fpsDebugOverlay),
                    subtitle: Text(l10n.actualCodecTiming),
                    value: showPlaybackDebug,
                    onChanged: onPlaybackDebugChanged,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'fit', label: Text(l10n.fit)),
                    ButtonSegment(value: 'fill', label: Text(l10n.fill)),
                  ],
                  selected: {scaleMode},
                  onSelectionChanged: (values) =>
                      onScaleModeChanged(values.first),
                ),
                const SizedBox(height: 18),
                _MetricRow(
                  label: l10n.protocol,
                  value: '${capabilities?.protocolVersion ?? 1}',
                ),
                _MetricRow(
                  label: l10n.video,
                  value: capabilities == null
                      ? 'H.264 720p30'
                      : '${capabilities.videoCodecs.map((codec) => codec.wireName).join(', ')} '
                            '${capabilities.maxWidth}x${capabilities.maxHeight}@${capabilities.maxFps}',
                ),
                _MetricRow(
                  label: l10n.fourK,
                  value:
                      '${capabilities?.supports4k30 ?? snapshot?.receiverSupports4k30 ?? false} '
                      '${snapshot?.receiverMaxVideoWidth ?? capabilities?.maxWidth ?? 0}x'
                      '${snapshot?.receiverMaxVideoHeight ?? capabilities?.maxHeight ?? 0}',
                ),
                _MetricRow(
                  label: l10n.decoder,
                  value: snapshot?.decoderReady == true
                      ? snapshot?.receiverDecoderName ??
                            capabilities?.decoderName ??
                            l10n.mediaCodecReady
                      : l10n.checking,
                ),
                _MetricRow(
                  label: l10n.surface,
                  value: snapshot?.surfaceRendererReady == true
                      ? l10n.surfaceViewReady
                      : l10n.pending,
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.performance,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _MetricRow(
                  label: l10n.summary,
                  value: snapshot?.bottleneckSummary ?? 'warming_up',
                ),
                _MetricRow(
                  label: l10n.receiveDecodePresent,
                  value:
                      '${(snapshot?.receivedAccessUnitFps ?? 0).toStringAsFixed(1)} / '
                      '${(snapshot?.decoderOutputFps ?? 0).toStringAsFixed(1)} / '
                      '${(snapshot?.releasedToSurfaceFps ?? 0).toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: l10n.presentP95,
                  value:
                      '${(snapshot?.presentedFrameIntervalP95Ms ?? 0).toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.latencyAvgP95,
                  value:
                      '${(snapshot?.latencyAverageMs ?? 0).toStringAsFixed(1)}/'
                      '${(snapshot?.latencyP95Ms ?? 0).toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.renderer,
                  value: snapshot?.rendererMode ?? 'lowLatencyPaced',
                ),
                _MetricRow(
                  label: l10n.queue,
                  value:
                      '${snapshot?.receiverQueueDepth ?? 0}/${snapshot?.maxReceiverQueueDepth ?? 0}',
                ),
                _MetricRow(
                  label: l10n.drops,
                  value:
                      'stale ${snapshot?.staleAccessUnitsDropped ?? 0}, late ${snapshot?.lateOutputBuffersDropped ?? 0}',
                ),
                _MetricRow(
                  label: l10n.sequenceGaps,
                  value: '${snapshot?.frameSequenceGaps ?? 0}',
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.audio,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: snapshot?.audioMuted ?? false,
                    onChanged: (value) => controller.setAudioMuted(value),
                    title: Text(
                      '${l10n.audio}: ${snapshot?.audioState ?? l10n.idle}',
                    ),
                  ),
                ),
                _MetricRow(
                  label: l10n.audioCodec,
                  value:
                      '${snapshot?.audioCodec ?? 'audio/mp4a-latm'} ${snapshot?.audioSampleRate ?? 0} Hz ${snapshot?.audioChannels ?? 0} ch',
                ),
                _MetricRow(
                  label: l10n.decoder,
                  value:
                      '${snapshot?.audioDecoderState ?? 'released'} / ${snapshot?.audioDecoderName ?? 'unknown'}',
                ),
                _MetricRow(
                  label: l10n.track,
                  value:
                      '${snapshot?.audioTrackState ?? 'NONE'} / ${snapshot?.audioTrackPlayState ?? 'STOPPED'}',
                ),
                _MetricRow(
                  label: l10n.audioSession,
                  value:
                      '${snapshot?.receiverSessionGeneration ?? 0}/${snapshot?.audioSessionGeneration ?? 0}',
                ),
                _MetricRow(
                  label: l10n.queuePcm,
                  value:
                      '${snapshot?.audioQueueDepth ?? 0}/${snapshot?.pcmQueueDepth ?? 0}',
                ),
                _MetricRow(
                  label: l10n.buffered,
                  value:
                      '${(snapshot?.audioBufferedDurationMs ?? 0).toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.avSync,
                  value:
                      '${(snapshot?.avSyncOffsetMs ?? 0).toStringAsFixed(1)} ms '
                      '(${snapshot?.syncMaster ?? 'videoLocal'})',
                ),
                _MetricRow(
                  label: l10n.avAvgP95,
                  value:
                      '${(snapshot?.avSyncAverageMs ?? 0).toStringAsFixed(1)}/'
                      '${(snapshot?.avSyncP95Ms ?? 0).toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.audioPackets,
                  value:
                      '${snapshot?.receivedAudioPackets ?? 0}/${snapshot?.audioDecoderInputPackets ?? 0}/${snapshot?.audioDecoderOutputBuffers ?? 0} '
                      '(${(snapshot?.audioPacketsReceivedRecent ?? 0).toStringAsFixed(1)}/s)',
                ),
                _MetricRow(
                  label: l10n.audioWrites,
                  value:
                      '${snapshot?.audioTrackWrittenFrames ?? 0}f/${snapshot?.audioBytesWritten ?? 0}B '
                      '${(snapshot?.audioBytesWrittenRecent ?? 0).toStringAsFixed(0)}B/s',
                ),
                _MetricRow(
                  label: l10n.audioRecovery,
                  value:
                      'recreate ${snapshot?.audioTrackRecreatedCount ?? 0}, '
                      'write ${snapshot?.audioTrackWriteErrorCount ?? 0}, '
                      'dead ${snapshot?.audioTrackDeadObjectCount ?? 0}',
                ),
                _MetricRow(
                  label: l10n.audioReset,
                  value:
                      '${snapshot?.audioSessionResetCount ?? 0}, pts ${snapshot?.audioPtsResetCount ?? 0}',
                ),
                _MetricRow(
                  label: l10n.audioExpected,
                  value:
                      '${snapshot?.tvAudioAudibleExpected ?? false}, play ${snapshot?.audioTrackPlayCalled ?? false}',
                ),
                _MetricRow(
                  label: l10n.audioDrops,
                  value:
                      '${snapshot?.audioDroppedPackets ?? 0}, av ${snapshot?.videoFramesDroppedForAvSync ?? 0}',
                ),
                if ((snapshot?.lastAudioSessionResetReason ?? '').isNotEmpty)
                  _MetricRow(
                    label: l10n.audioResetReason,
                    value: snapshot!.lastAudioSessionResetReason,
                  ),
                if (snapshot?.audioLastError != null)
                  _MetricRow(
                    label: l10n.audioError,
                    value: snapshot!.audioLastError!,
                  ),
                const SizedBox(height: 18),
                Text(
                  l10n.presentation,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _MetricRow(label: l10n.fullscreen, value: '$fullscreenEnabled'),
                _MetricRow(
                  label: l10n.autoFullscreen,
                  value: '$autoFullscreen',
                ),
                _MetricRow(
                  label: l10n.autoEntered,
                  value: '$autoFullscreenEnteredForSession',
                ),
                _MetricRow(
                  label: l10n.userExited,
                  value: '$userExitedFullscreen',
                ),
                _MetricRow(
                  label: l10n.playback,
                  value:
                      '${snapshot?.playbackState ?? controller.state.wireName} '
                      'pause ${snapshot?.pauseCommandPending ?? false} '
                      'resume ${snapshot?.resumeCommandPending ?? false}',
                ),
                _MetricRow(
                  label: l10n.scaleMode,
                  value: scaleMode == 'fit' ? l10n.fit : l10n.fill,
                ),
                _MetricRow(
                  label: l10n.display,
                  value:
                      '${snapshot?.containerWidth ?? 0}x${snapshot?.containerHeight ?? 0}',
                ),
                _MetricRow(
                  label: l10n.videoView,
                  value:
                      '${snapshot?.renderedViewWidth ?? 0}x${snapshot?.renderedViewHeight ?? 0}',
                ),
                _MetricRow(
                  label: l10n.aspectError,
                  value: (snapshot?.aspectRatioError ?? 0).toStringAsFixed(4),
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.diagnostics,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _MetricRow(
                  label: l10n.bytes,
                  value: '${snapshot?.bytesReceived ?? 0}',
                ),
                _MetricRow(
                  label: l10n.config,
                  value: '${snapshot?.configPacketsReceived ?? 0}',
                ),
                _MetricRow(
                  label: l10n.accessUnits,
                  value: '${snapshot?.accessUnitsReceived ?? 0}',
                ),
                _MetricRow(
                  label: l10n.keyFrames,
                  value: '${snapshot?.keyFramesReceived ?? 0}',
                ),
                _MetricRow(
                  label: l10n.decoderIo,
                  value:
                      '${snapshot?.decoderInputFrames ?? 0}/${snapshot?.decoderOutputFrames ?? 0}',
                ),
                _MetricRow(
                  label: l10n.releasedToSurface,
                  value: '${snapshot?.releasedToSurfaceFrames ?? 0}',
                ),
                _MetricRow(
                  label: l10n.codecCreateRelease,
                  value:
                      '${snapshot?.codecCreateCount ?? 0}/${snapshot?.codecReleaseCount ?? 0}',
                ),
                _MetricRow(
                  label: l10n.surfaceLifecycle,
                  value:
                      '${snapshot?.surfaceCreatedCount ?? 0}/${snapshot?.surfaceChangedCount ?? 0}/${snapshot?.surfaceDestroyedCount ?? 0}',
                ),
                _MetricRow(
                  label: l10n.surfaceValid,
                  value: '${snapshot?.surfaceIsValid ?? false}',
                ),
                _MetricRow(
                  label: l10n.surfaceSize,
                  value:
                      '${snapshot?.surfaceWidth ?? 0}x${snapshot?.surfaceHeight ?? 0}',
                ),
                _MetricRow(
                  label: l10n.surfaceZOrder,
                  value: snapshot?.zOrderMode ?? 'unknown',
                ),
                _MetricRow(
                  label: l10n.configuredOutput,
                  value:
                      '${snapshot?.configuredWidth ?? 0}x${snapshot?.configuredHeight ?? 0} / '
                      '${snapshot?.outputWidth ?? 0}x${snapshot?.outputHeight ?? 0}',
                ),
                if (outputCrop != null)
                  _MetricRow(label: l10n.outputCrop, value: outputCrop),
                if (snapshot?.lastDecoderError != null)
                  _MetricRow(
                    label: l10n.lastError,
                    value: snapshot!.lastDecoderError!,
                  ),
                const SizedBox(height: 18),
                Text(
                  l10n.receiverLog,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...controller.log.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(entry),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiverConnectionInfoPanel extends StatefulWidget {
  const _ReceiverConnectionInfoPanel({required this.controller});

  final ReceiverController controller;

  @override
  State<_ReceiverConnectionInfoPanel> createState() =>
      _ReceiverConnectionInfoPanelState();
}

class _ReceiverConnectionInfoPanelState
    extends State<_ReceiverConnectionInfoPanel> {
  static const double _maxAdditionalAddressesHeight = 48;
  static const double _addressScrollStep = 24;

  final ScrollController _additionalAddressesController = ScrollController();
  bool _additionalAddressesHasFocus = false;

  @override
  void dispose() {
    _additionalAddressesController.dispose();
    super.dispose();
  }

  KeyEventResult _handleAdditionalAddressesKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_additionalAddressesController.hasClients) {
      return KeyEventResult.ignored;
    }

    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => _addressScrollStep,
      LogicalKeyboardKey.arrowUp => -_addressScrollStep,
      _ => 0.0,
    };
    if (delta == 0) {
      return KeyEventResult.ignored;
    }

    final position = _additionalAddressesController.position;
    final offset = (position.pixels + delta)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if (offset == position.pixels) {
      return KeyEventResult.ignored;
    }
    _additionalAddressesController.jumpTo(offset);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final l10n = AppLocalizations.of(context);
    final snapshot = controller.snapshot;
    final addresses = usableReceiverIpv4Addresses(
      snapshot?.localIpv4Addresses ?? const <String>[],
    );
    final additionalAddresses = addresses.skip(1).toList(growable: false);
    final lookupState = controller.addressLookupState;
    final String? statusMessage;
    if (lookupState == ReceiverAddressLookupState.checking) {
      statusMessage = l10n.ipAddressChecking;
    } else if (lookupState == ReceiverAddressLookupState.failed) {
      statusMessage = l10n.ipAddressLookupFailed;
    } else if (addresses.isEmpty) {
      statusMessage = l10n.networkConnectionCheck;
    } else {
      statusMessage = null;
    }

    final port = snapshot?.receiverPort ?? ReceiverController.defaultPort;
    final colorScheme = Theme.of(context).colorScheme;
    final addressStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontSize: 16,
      height: 1.1,
      fontWeight: FontWeight.w600,
    );
    final addressLabelStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(fontSize: 11, height: 1.1);
    return Container(
      key: const Key('receiver.connectionInfoPanel'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.connected_tv, color: colorScheme.primary, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.pcConnectionInfo,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 14, height: 1.1),
                  softWrap: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.tvIpAddress, style: addressLabelStyle),
          const SizedBox(height: 1),
          if (statusMessage != null)
            Text(
              statusMessage,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.1),
              softWrap: true,
            )
          else
            Text(addresses.first, style: addressStyle, softWrap: true),
          Row(
            children: [
              Text(l10n.port, style: addressLabelStyle),
              const SizedBox(width: 6),
              Text(
                port.toString(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 14,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            l10n.ipAddressEntryInstruction,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 10, height: 1.1),
            softWrap: true,
          ),
          if (additionalAddresses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _maxAdditionalAddressesHeight,
                ),
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: Focus(
                    debugLabel: 'Additional TV IP addresses',
                    onFocusChange: (hasFocus) {
                      if (_additionalAddressesHasFocus != hasFocus) {
                        setState(() {
                          _additionalAddressesHasFocus = hasFocus;
                        });
                      }
                    },
                    onKeyEvent: _handleAdditionalAddressesKey,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _additionalAddressesHasFocus
                              ? colorScheme.primary
                              : Colors.transparent,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: ListView(
                        key: const Key('receiver.additionalAddressesScroll'),
                        controller: _additionalAddressesController,
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final address in additionalAddresses)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 1,
                                vertical: 0,
                              ),
                              child: Text(
                                address,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(fontSize: 16, height: 1.1),
                                softWrap: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
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

String _receiverStateLabel(
  AppLocalizations l10n,
  MirrorSessionState state,
) => switch (state) {
  MirrorSessionState.idle => l10n.receiverStateReady,
  MirrorSessionState.starting => l10n.receiverStateStarting,
  MirrorSessionState.listening => l10n.receiverStateListening,
  MirrorSessionState.connecting => l10n.receiverStateConnecting,
  MirrorSessionState.negotiating => l10n.receiverStateNegotiating,
  MirrorSessionState.waitingForSurface => l10n.receiverStateWaitingForSurface,
  MirrorSessionState.waitingForKeyFrame => l10n.receiverStateWaitingForKeyFrame,
  MirrorSessionState.streaming => l10n.receiverStateStreaming,
  MirrorSessionState.paused => l10n.receiverStatePaused,
  MirrorSessionState.resuming => l10n.receiverStateResuming,
  MirrorSessionState.disconnected => l10n.receiverStateFailed,
  MirrorSessionState.error => l10n.receiverStateFailed,
  MirrorSessionState.stopping => l10n.receiverStateStopping,
  MirrorSessionState.restoring => l10n.receiverStateRestoring,
  MirrorSessionState.failed => l10n.receiverStateFailed,
};

String _receiverStatusMessage(
  AppLocalizations l10n,
  MirrorSessionState state,
) => switch (state) {
  MirrorSessionState.idle => l10n.statusReady,
  MirrorSessionState.starting => l10n.statusStarting,
  MirrorSessionState.listening => l10n.statusListening,
  MirrorSessionState.connecting => l10n.statusConnecting,
  MirrorSessionState.negotiating => l10n.statusNegotiating,
  MirrorSessionState.waitingForSurface => l10n.statusWaitingForSurface,
  MirrorSessionState.waitingForKeyFrame => l10n.statusWaitingForKeyFrame,
  MirrorSessionState.streaming => l10n.statusStreaming,
  MirrorSessionState.paused => l10n.statusPaused,
  MirrorSessionState.resuming => l10n.statusResuming,
  MirrorSessionState.disconnected => l10n.statusFailed,
  MirrorSessionState.error => l10n.statusFailed,
  MirrorSessionState.stopping => l10n.statusStopping,
  MirrorSessionState.restoring => l10n.statusRestoring,
  MirrorSessionState.failed => l10n.statusFailed,
};

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.message});

  final String label;
  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                children: [Text('${l10n.state}: $label'), Text(message)],
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
