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
                  onSystemAudioChanged: _controller.setSystemAudioEnabled,
                  onPcLocalAudioMuteChanged:
                      _controller.setPcLocalAudioMuteRequested,
                  onVideoProfileChanged: _controller.setVideoProfile,
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
    await _controller.start(receiverHost: host, receiverPort: port);
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
    required this.onSystemAudioChanged,
    required this.onPcLocalAudioMuteChanged,
    required this.onVideoProfileChanged,
  });

  final MirrorController controller;
  final TextEditingController hostController;
  final TextEditingController portController;
  final VoidCallback onRefresh;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ValueChanged<bool> onSystemAudioChanged;
  final ValueChanged<bool> onPcLocalAudioMuteChanged;
  final ValueChanged<SenderVideoProfile> onVideoProfileChanged;

  @override
  Widget build(BuildContext context) {
    final pcMuteUnsupported =
        controller.pcLocalAudioMuteRequested &&
        !(controller.snapshot?.pcLocalAudioMuteSupported ?? false);
    final pcMuteSubtitle = pcMuteUnsupported
        ? 'Unavailable: separate PC/TV audio routing is not configured'
        : controller.pcLocalAudioMuteRequested
        ? 'PC muted - TV audio continues'
        : 'PC audio on - TV audio continues';

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
                  'Stage 4 session',
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
          const SizedBox(height: 8),
          DropdownButtonFormField<SenderVideoProfile>(
            initialValue: controller.videoProfile,
            isExpanded: true,
            items: SenderVideoProfile.values
                .map(
                  (profile) => DropdownMenuItem(
                    value: profile,
                    child: Text(
                      profile.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: controller.isRunning
                ? null
                : (value) {
                    if (value != null) {
                      onVideoProfileChanged(value);
                    }
                  },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Video profile',
            ),
          ),
          const SizedBox(height: 8),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.systemAudioEnabled,
              onChanged: controller.isRunning ? null : onSystemAudioChanged,
              title: const Text('System audio'),
              secondary: const Icon(Icons.volume_up),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.pcLocalAudioMuteRequested,
              onChanged: controller.busy || !controller.systemAudioEnabled
                  ? null
                  : onPcLocalAudioMuteChanged,
              title: const Text('Mute PC speakers'),
              subtitle: Text(pcMuteSubtitle),
              secondary: const Icon(Icons.speaker),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MetricRow(label: 'Performance', value: snapshot.bottleneckSummary),
            const Divider(height: 18),
            _MetricSection(
              title: 'Capture',
              rows: [
                _MetricRow(
                  label: 'Profile',
                  value:
                      '${snapshot.selectedProfile} - ${snapshot.outputResolution} - '
                      '${snapshot.currentBitrateKbps} kbps',
                ),
                _MetricRow(
                  label: 'Target / actual',
                  value:
                      '${snapshot.targetFps.toStringAsFixed(1)} / '
                      '${snapshot.admittedFrameFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: 'Callback',
                  value:
                      '${snapshot.captureCallbackFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: 'Interval p95',
                  value:
                      '${snapshot.captureFrameIntervalP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: 'Target interval',
                  value:
                      '${snapshot.targetFrameIntervalMs.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: 'Replaced / cadence',
                  value:
                      '${snapshot.captureReplacedFrames} / ${snapshot.cadenceSkippedFrames}',
                ),
                _MetricRow(
                  label: 'Queue depth',
                  value: '${snapshot.queueDepthCapture}',
                ),
              ],
            ),
            const Divider(height: 18),
            _MetricSection(
              title: 'Convert / Encode',
              rows: [
                _MetricRow(
                  label: 'Admission / accepted',
                  value:
                      '${snapshot.admittedFrameFps.toStringAsFixed(1)} / '
                      '${snapshot.encoderAcceptedFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: 'Converted',
                  value: '${snapshot.convertedFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: 'Encoder input',
                  value: '${snapshot.encoderInputFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: 'Encoded',
                  value: '${snapshot.encodedFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: 'Convert path',
                  value:
                      '${snapshot.captureToConvertAverageMs.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: 'Encode avg/p95',
                  value:
                      '${snapshot.encodeDurationAverageMs.toStringAsFixed(1)}/'
                      '${snapshot.encodeDurationP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: 'Encoder',
                  value: snapshot.selectedEncoderHardware
                      ? '${snapshot.selectedEncoderName} (hardware)'
                      : '${snapshot.selectedEncoderName} (software)',
                ),
                _MetricRow(
                  label: 'Backpressure',
                  value:
                      'not accepting ${snapshot.encoderNotAcceptingCount}, '
                      'drops ${snapshot.encoderBackpressureDroppedFrames}',
                ),
                _MetricRow(
                  label: 'Process in/out p95',
                  value:
                      '${snapshot.processInputDurationP95Ms.toStringAsFixed(1)}/'
                      '${snapshot.processOutputDurationP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: 'Readback / reuse',
                  value:
                      '${snapshot.gpuReadbackPerFrame ? 'readback' : 'zero-copy'}, '
                      '${snapshot.textureReuseEnabled ? 'reuse' : 'allocate'}',
                ),
                _MetricRow(
                  label: 'Queue depth',
                  value: '${snapshot.queueDepthEncoder}',
                ),
              ],
            ),
            const Divider(height: 18),
            _MetricSection(
              title: 'Network',
              rows: [
                _MetricRow(
                  label: 'Sent',
                  value: '${snapshot.sentVideoFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: 'Send interval p95',
                  value:
                      '${snapshot.sendFrameIntervalP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: 'Send duration',
                  value:
                      '${snapshot.accessUnitSendDurationAverageMs.toStringAsFixed(1)}/'
                      '${snapshot.accessUnitSendDurationP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: 'Socket calls',
                  value:
                      '${snapshot.socketSendCallsPerSecond.toStringAsFixed(1)}/s',
                ),
                _MetricRow(
                  label: 'Pending',
                  value: '${snapshot.pendingSendBytes} B',
                ),
                _MetricRow(
                  label: 'Queue depth',
                  value: '${snapshot.queueDepthTransport}',
                ),
                _MetricRow(
                  label: 'Queue wait avg/p95',
                  value:
                      '${snapshot.videoQueueWaitAverageMs.toStringAsFixed(1)}/'
                      '${snapshot.videoQueueWaitP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: 'Stale video drops',
                  value:
                      '${snapshot.staleVideoDroppedFrames} '
                      '(${snapshot.staleVideoDroppedFps.toStringAsFixed(1)} fps)',
                ),
              ],
            ),
            const Divider(height: 18),
            _MetricSection(
              title: 'Audio',
              rows: [
                _MetricRow(
                  label: 'State',
                  value: snapshot.audioEnabled
                      ? snapshot.audioCaptureState
                      : 'disabled',
                ),
                _MetricRow(
                  label: 'Device',
                  value: snapshot.audioDeviceName.isEmpty
                      ? 'unknown'
                      : snapshot.audioDeviceName,
                ),
                _MetricRow(
                  label: 'Input / encoded',
                  value:
                      '${snapshot.audioInputSampleRate} Hz ${snapshot.audioInputChannels} ch / '
                      '${snapshot.audioEncodedSampleRate} Hz ${snapshot.audioEncodedChannels} ch',
                ),
                _MetricRow(
                  label: 'Capture / sent',
                  value:
                      '${snapshot.audioCaptureFps.toStringAsFixed(1)} fps / '
                      '${snapshot.sentAudioPackets}',
                ),
                _MetricRow(
                  label: 'Encode avg',
                  value:
                      '${snapshot.audioEncodeAverageMs.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: 'Queue / dropped',
                  value:
                      '${snapshot.audioQueueDepth} / ${snapshot.audioDroppedPackets}',
                ),
                _MetricRow(
                  label: 'Writer wait V/A',
                  value:
                      '${snapshot.packetWriterVideoWaitMs.toStringAsFixed(1)}/'
                      '${snapshot.packetWriterAudioWaitMs.toStringAsFixed(1)} ms',
                ),
                if (snapshot.audioLastError.isNotEmpty)
                  _MetricRow(
                    label: 'Audio error',
                    value: snapshot.audioLastError,
                  ),
                _MetricRow(
                  label: 'Mute PC speakers',
                  value:
                      'requested ${snapshot.pcLocalAudioMuteRequested}, '
                      'supported ${snapshot.pcLocalAudioMuteSupported}, '
                      'applied ${snapshot.pcLocalAudioMuteApplied}, '
                      'original ${snapshot.pcLocalAudioOriginalMuteState}',
                ),
                _MetricRow(
                  label: 'TV audio path',
                  value:
                      'stream ${snapshot.tvAudioStreaming}, '
                      'cap ${snapshot.audioCaptureActive}, '
                      'enc ${snapshot.audioEncoderActive}, '
                      'net ${snapshot.audioTransportActive}',
                ),
                _MetricRow(
                  label: 'Audio routing',
                  value: snapshot.audioRoutingMode,
                ),
                if (snapshot.audioMuteUnsupportedReason.isNotEmpty)
                  _MetricRow(
                    label: 'Speaker route error',
                    value: snapshot.audioMuteUnsupportedReason,
                  ),
              ],
            ),
            const Divider(height: 18),
            _MetricSection(
              title: 'Playback control',
              rows: [
                _MetricRow(label: 'State', value: snapshot.playbackState),
                _MetricRow(
                  label: 'Pause / resume',
                  value:
                      '${snapshot.pauseRequestsReceived} / ${snapshot.resumeRequestsReceived}',
                ),
                _MetricRow(
                  label: 'ACK / error',
                  value:
                      '${snapshot.playbackCommandAcksSent} / ${snapshot.playbackCommandErrorsSent}',
                ),
                _MetricRow(
                  label: 'Resume config resend',
                  value: '${snapshot.resumeCodecConfigResends}',
                ),
              ],
            ),
            const Divider(height: 18),
            _MetricRow(
              label: 'Captured total',
              value: '${snapshot.capturedFrames}',
            ),
            _MetricRow(
              label: 'Last sequence',
              value: '${snapshot.lastProcessedFrameSequence}',
            ),
            _MetricRow(
              label: 'Intentional skip',
              value:
                  '${snapshot.cadenceSkippedFrames} (${snapshot.cadenceDroppedFps.toStringAsFixed(1)} fps)',
            ),
            _MetricRow(
              label: 'Real drops',
              value:
                  'conv ${snapshot.conversionBackpressureDroppedFrames}, '
                  'enc ${snapshot.encoderBackpressureDroppedFrames}, '
                  'net ${snapshot.transportBackpressureDroppedFrames}, '
                  'stale ${snapshot.staleVideoDroppedFrames}',
            ),
            _MetricRow(
              label: 'Config sent',
              value: '${snapshot.codecConfigSent}',
            ),
            _MetricRow(label: 'Key frames', value: '${snapshot.keyFramesSent}'),
            _MetricRow(
              label: 'Total dropped',
              value: '${snapshot.totalDroppedFrames}',
            ),
            _MetricRow(label: 'Packets', value: '${snapshot.packetsSent}'),
            _MetricRow(label: 'Bytes', value: '${snapshot.bytesSent}'),
            _MetricRow(
              label: 'Send completed',
              value: '${snapshot.sendCompletedBytes}',
            ),
            _MetricRow(
              label: 'Queue depth',
              value:
                  '${snapshot.queueDepthCapture}/'
                  '${snapshot.queueDepthEncoder}/'
                  '${snapshot.queueDepthTransport}',
            ),
            _MetricRow(
              label: 'Capture -> encode',
              value:
                  '${snapshot.lastCaptureToEncodeMs.toStringAsFixed(1)} ms '
                  '(avg ${snapshot.averageCaptureToEncodeMs.toStringAsFixed(1)}, '
                  'max ${snapshot.maxCaptureToEncodeMs.toStringAsFixed(1)})',
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricSection extends StatelessWidget {
  const _MetricSection({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...rows,
      ],
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
