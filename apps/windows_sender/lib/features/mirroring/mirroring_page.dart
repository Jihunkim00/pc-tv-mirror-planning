import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

import '../../core/native_bridge/mirror_native_api.dart';
import 'mirror_controller.dart';

class MirroringPage extends StatefulWidget {
  const MirroringPage({required this.nativeApi, super.key});

  final MirrorNativeApi nativeApi;

  @override
  State<MirroringPage> createState() => _MirroringPageState();
}

class _MirroringPageState extends State<MirroringPage> {
  late final MirrorController _controller;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _controller = MirrorController(widget.nativeApi)..loadDisplays();
    _hostController = TextEditingController();
    _portController = TextEditingController(text: '50720');
    _loadLastReceiverHost();
  }

  @override
  void dispose() {
    _controller.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final sessionPanel = _SessionPanel(
                  controller: _controller,
                  hostController: _hostController,
                  portController: _portController,
                  onRefresh: _controller.loadDisplays,
                  onStart: _start,
                  onStop: _controller.stop,
                );

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _DisplayPanel(controller: _controller),
                            ),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: sessionPanel),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: constraints.maxHeight * 0.38,
                              child: _DisplayPanel(controller: _controller),
                            ),
                            const SizedBox(height: 16),
                            Expanded(child: sessionPanel),
                          ],
                        ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _start() async {
    final host = _hostController.text.trim();
    if (!_isValidIpv4(host)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid TV IPv4 address.')),
      );
      return;
    }
    final port = int.tryParse(_portController.text.trim()) ?? 50720;
    await _controller.start(
      receiverHost: host,
      receiverPort: port,
    );
    if (_controller.state != MirrorSessionState.failed) {
      await _saveLastReceiverHost(host);
    }
  }

  Future<void> _loadLastReceiverHost() async {
    final file = _settingsFile();
    try {
      if (!await file.exists()) {
        return;
      }
      final host = (await file.readAsString()).trim();
      if (mounted && _isValidIpv4(host)) {
        _hostController.text = host;
      }
    } catch (_) {
      // Local settings are best-effort only; the user can type the TV IP.
    }
  }

  Future<void> _saveLastReceiverHost(String host) async {
    try {
      final file = _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(host);
    } catch (_) {
      // Keep the active session path independent from settings persistence.
    }
  }
}

bool _isValidIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) {
    return false;
  }
  for (final part in parts) {
    if (part.isEmpty || (part.length > 1 && part.startsWith('0'))) {
      return false;
    }
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) {
      return false;
    }
  }
  return true;
}

File _settingsFile() {
  final base = Platform.environment['APPDATA'];
  final root = base == null || base.isEmpty
      ? Directory.systemTemp.path
      : '$base${Platform.pathSeparator}PC TV Mirror';
  return File(
    '$root${Platform.pathSeparator}windows_sender_last_receiver_ip.txt',
  );
}

class _DisplayPanel extends StatelessWidget {
  const _DisplayPanel({required this.controller});

  final MirrorController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor),
                const SizedBox(width: 10),
                Text(
                  'Monitor source',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: controller.displays.isEmpty
                  ? const Center(child: Text('No displays found.'))
                  : ListView.separated(
                      itemCount: controller.displays.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final display = controller.displays[index];
                        return _DisplayTile(
                          display: display,
                          selected: display.id == controller.selectedDisplayId,
                          enabled: !controller.isRunning,
                          onSelected: () =>
                              controller.selectDisplay(display.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisplayTile extends StatelessWidget {
  const _DisplayTile({
    required this.display,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final DisplayInfo display;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onSelected : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.monitor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      display.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${display.width} x ${display.height}  ${display.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (display.isPrimary) const Icon(Icons.star, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionPanel extends StatelessWidget {
  const _SessionPanel({
    required this.controller,
    required this.hostController,
    required this.portController,
    required this.onRefresh,
    required this.onStart,
    required this.onStop,
  });

  final MirrorController controller;
  final TextEditingController hostController;
  final TextEditingController portController;
  final VoidCallback onRefresh;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(Icons.settings_input_antenna),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Stage 1 session',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh displays',
                onPressed: controller.busy ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: hostController,
            enabled: !controller.isRunning,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Receiver IP',
              hintText: 'Example: 192.168.1.40',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: portController,
            enabled: !controller.isRunning,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Control port',
            ),
          ),
          const SizedBox(height: 16),
          _StateBanner(controller: controller),
          if (controller.snapshot != null) ...[
            const SizedBox(height: 12),
            _SenderCounters(snapshot: controller.snapshot!),
          ],
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: controller.canStart ? onStart : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: controller.canStop ? onStop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Session log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: ListView.separated(
              itemCount: controller.log.length,
              separatorBuilder: (_, _) => const Divider(height: 12),
              itemBuilder: (context, index) => Text(controller.log[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderCounters extends StatelessWidget {
  const _SenderCounters({required this.snapshot});

  final NativeSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _MetricRow(label: 'Captured', value: '${snapshot.capturedFrames}'),
            _MetricRow(
              label: 'Capture dropped',
              value: '${snapshot.captureDroppedFrames}',
            ),
            _MetricRow(label: 'Encoded', value: '${snapshot.encodedFrames}'),
            _MetricRow(
              label: 'Encoder input dropped',
              value: '${snapshot.encoderInputDroppedFrames}',
            ),
            _MetricRow(
              label: 'Config sent',
              value: '${snapshot.codecConfigSent}',
            ),
            _MetricRow(label: 'Key frames', value: '${snapshot.keyFramesSent}'),
            _MetricRow(
              label: 'Transport dropped',
              value: '${snapshot.transportDroppedFrames}',
            ),
            _MetricRow(label: 'Packets', value: '${snapshot.packetsSent}'),
            _MetricRow(label: 'Bytes', value: '${snapshot.bytesSent}'),
            _MetricRow(
              label: 'Send completed',
              value: '${snapshot.sendCompletedBytes}',
            ),
            _MetricRow(
              label: 'Queue depth',
              value: '${snapshot.queueDepthCapture}/'
                  '${snapshot.queueDepthEncoder}/'
                  '${snapshot.queueDepthTransport}',
            ),
            _MetricRow(
              label: 'Capture -> encode',
              value: '${snapshot.lastCaptureToEncodeMs.toStringAsFixed(1)} ms '
                  '(avg ${snapshot.averageCaptureToEncodeMs.toStringAsFixed(1)}, '
                  'max ${snapshot.maxCaptureToEncodeMs.toStringAsFixed(1)})',
            ),
          ],
        ),
      ),
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({required this.controller});

  final MirrorController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final failed = controller.state == MirrorSessionState.failed;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: failed ? colorScheme.errorContainer : colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: failed ? colorScheme.error : colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(failed ? Icons.error_outline : Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('State: ${controller.state.wireName}'),
                  if (controller.userMessage != null)
                    Text(controller.userMessage!),
                  if (controller.developerMessage != null)
                    Text(
                      controller.developerMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
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
      padding: const EdgeInsets.only(bottom: 8),
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
