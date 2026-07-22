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
    final stateChanged = _lastRestoredState != state;
    _lastRestoredState = state;

    if (!stateChanged && controlsHaveFocus) {
      return;
    }

    final fallbackNode = _firstFocusableNode(controls);
    final target = preferredNode.canRequestFocus ? preferredNode : fallbackNode;
    target?.requestFocus();
  }

  FocusNode _preferredFocusNodeForState(MirrorSessionState state) {
    return switch (state) {
      MirrorSessionState.streaming => _stopFocusNode,
      MirrorSessionState.idle ||
      MirrorSessionState.connecting ||
      MirrorSessionState.negotiating ||
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
      canPop: true,
      child: Shortcuts(
        shortcuts: _tvRemoteShortcuts,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Scaffold(
            body: SafeArea(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.all(28),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _VideoSurface(
                          showNativeSurface: widget.showNativeSurface,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 3,
                        child: _ReceiverStatusPanel(
                          controller: _controller,
                          restartFocusNode: _restartFocusNode,
                          stopFocusNode: _stopFocusNode,
                          onRestart: _restartReceiver,
                          onStop: _stopReceiver,
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
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.showNativeSurface});

  final bool showNativeSurface;

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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (usePlatformView)
                const AndroidView(viewType: 'pc_tv_mirror/video_surface')
              else
                const ColoredBox(color: Colors.black),
              Align(
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
              ),
            ],
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
          _MetricRow(
            label: 'Control port',
            value:
                '${snapshot?.receiverPort ?? ReceiverController.defaultPort}',
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
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: TvFocusButton(
              key: const Key('receiver.restartButton'),
              focusNode: restartFocusNode,
              autofocus: true,
              enabled: !controller.busy,
              onPressed: onRestart,
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
              enabled: !controller.busy,
              onPressed: onStop,
              icon: Icons.stop,
              label: 'Stop receiver',
            ),
          ),
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
