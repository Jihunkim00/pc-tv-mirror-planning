import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:windows_sender/l10n/generated/app_localizations.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

import '../../core/native_bridge/mirror_native_api.dart';
import 'diagnostics_clipboard_formatter.dart';
import 'mirror_controller.dart';

class MirroringPage extends StatefulWidget {
  const MirroringPage({
    required this.nativeApi,
    this.languagePreferenceCode = 'system',
    this.onLanguagePreferenceChanged,
    super.key,
  });

  final MirrorNativeApi nativeApi;
  final String languagePreferenceCode;
  final ValueChanged<String>? onLanguagePreferenceChanged;

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

  Future<void> _copyDiagnostics() async {
    final text = DiagnosticsClipboardFormatter.format(
      snapshot: _controller.snapshot,
      sourceDisplay: _controller.selectedDisplay,
      sessionId: _controller.activeSessionId,
    );
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).diagnosticsCopied),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).diagnosticsCopyFailed),
          ),
        );
      }
    }
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(l10n.language),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: widget.languagePreferenceCode,
                        isDense: true,
                        onChanged: widget.onLanguagePreferenceChanged == null
                            ? null
                            : (value) {
                                if (value != null) {
                                  widget.onLanguagePreferenceChanged!(value);
                                }
                              },
                        items: [
                          DropdownMenuItem(
                            value: 'system',
                            child: Text(l10n.systemLanguage),
                          ),
                          DropdownMenuItem(
                            value: 'ko',
                            child: Text(l10n.languageKorean),
                          ),
                          DropdownMenuItem(
                            value: 'en',
                            child: Text(l10n.languageEnglish),
                          ),
                          DropdownMenuItem(
                            value: 'ja',
                            child: Text(l10n.languageJapanese),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 720;
                        final sessionPanel = _SessionPanel(
                          controller: _controller,
                          hostController: _hostController,
                          portController: _portController,
                          onRefresh: _controller.loadDisplays,
                          onStart: _start,
                          onStop: _controller.stop,
                          onVideoProfileChanged: _controller.setVideoProfile,
                          onCopyDiagnostics: _copyDiagnostics,
                        );

                        return wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _DisplayPanel(
                                      controller: _controller,
                                      onSelected: _selectDisplay,
                                    ),
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
                                    child: _DisplayPanel(
                                      controller: _controller,
                                      onSelected: _selectDisplay,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(child: sessionPanel),
                                ],
                              );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _selectDisplay(String displayId) async {
    if (_controller.busy || _controller.selectedDisplayId == displayId) {
      return;
    }
    if (!_controller.isRunning) {
      _controller.selectDisplay(displayId);
      return;
    }

    final host = _hostController.text.trim();
    if (!_isValidIpv4(host)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).invalidTvIpv4)),
        );
      }
      return;
    }
    final port = int.tryParse(_portController.text.trim()) ?? 50720;

    await _controller.stop();
    if (!mounted || _controller.state != MirrorSessionState.idle) {
      return;
    }

    _controller.selectDisplay(displayId);
    await _controller.start(receiverHost: host, receiverPort: port);
  }

  Future<void> _start() async {
    final host = _hostController.text.trim();
    if (!_isValidIpv4(host)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).invalidTvIpv4)),
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

String _videoProfileLabel(AppLocalizations l10n, SenderVideoProfile profile) =>
    switch (profile) {
      SenderVideoProfile.lowLatency720p30 => l10n.profile720p30Hq,
      SenderVideoProfile.highQuality1080p30 => l10n.profile1080p30Hq,
      SenderVideoProfile.highQuality1080p60 => l10n.profile1080p60,
      SenderVideoProfile.cinema1080p24 => l10n.profile1080p24Cinema,
      SenderVideoProfile.compatibility720p30 => l10n.profile720p30Compat,
      SenderVideoProfile.experimental4k30 => l10n.profile4k30,
    };

String _senderStateLabel(AppLocalizations l10n, MirrorSessionState state) =>
    switch (state) {
      MirrorSessionState.idle => l10n.stateReady,
      MirrorSessionState.starting => l10n.stateStarting,
      MirrorSessionState.listening => l10n.stateListening,
      MirrorSessionState.connecting => l10n.stateConnecting,
      MirrorSessionState.negotiating => l10n.stateNegotiating,
      MirrorSessionState.waitingForSurface => l10n.stateWaitingForSurface,
      MirrorSessionState.waitingForKeyFrame => l10n.stateWaitingForKeyFrame,
      MirrorSessionState.streaming => l10n.stateStreaming,
      MirrorSessionState.paused => l10n.statePaused,
      MirrorSessionState.resuming => l10n.stateResuming,
      MirrorSessionState.disconnected => l10n.stateFailed,
      MirrorSessionState.error => l10n.stateFailed,
      MirrorSessionState.stopping => l10n.stateStopping,
      MirrorSessionState.restoring => l10n.stateRestoring,
      MirrorSessionState.failed => l10n.stateFailed,
    };

String _senderStatusMessage(AppLocalizations l10n, MirrorSessionState state) =>
    switch (state) {
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

String _pcSpeakerMuteMessage(
  AppLocalizations l10n,
  MirrorController controller,
) {
  final snapshot = controller.snapshot;
  if (!controller.pcLocalAudioMuteRequested) {
    return controller.isRunning && snapshot?.pcLocalAudioActualMuted == true
        ? l10n.pcSoundMuteRestoring
        : l10n.pcSoundMuteOff;
  }
  if (!controller.isRunning) return l10n.pcSoundMuteOnlyDuringMirroring;
  if (snapshot == null) return l10n.pcSoundMuteWaiting;
  if (snapshot.pcLocalAudioMuteExternalOverride) {
    return l10n.pcSoundMuteUserChanged;
  }
  switch (snapshot.pcLocalAudioMuteErrorCode) {
    case 'endpoint_unavailable':
      return l10n.pcSoundMuteEndpointUnavailable;
    case 'endpoint_volume_unavailable':
    case 'callback_registration_failed':
      return l10n.pcSoundMuteControlUnavailable;
    case 'set_mute_failed':
      return l10n.pcSoundMuteApplyFailed;
    case 'restore_failed':
      return l10n.pcSoundMuteRestoreFailed;
    case 'audio_capture_unavailable':
    case 'audio_capture_failed':
      return l10n.pcSoundMuteCaptureFailed;
  }
  if (snapshot.pcLocalAudioMuteErrorCode.isNotEmpty) {
    return l10n.pcSoundMuteControlUnavailable;
  }
  if (!snapshot.audioCaptureActive || !snapshot.pcLocalAudioMuteSupported) {
    return l10n.pcSoundMuteWaiting;
  }
  if (snapshot.pcLocalAudioOriginalMuteState) {
    return l10n.pcSoundMuteAlreadyMuted;
  }
  if (snapshot.pcLocalAudioMuteApplied && snapshot.pcLocalAudioActualMuted) {
    return l10n.pcSoundMuteActive;
  }
  return l10n.pcSoundMuteWaiting;
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
      : '$base${Platform.pathSeparator}PC to TV Mirror';
  return File(
    '$root${Platform.pathSeparator}windows_sender_last_receiver_ip.txt',
  );
}

class _DisplayPanel extends StatefulWidget {
  const _DisplayPanel({required this.controller, required this.onSelected});

  final MirrorController controller;
  final ValueChanged<String> onSelected;

  @override
  State<_DisplayPanel> createState() => _DisplayPanelState();
}

class _DisplayPanelState extends State<_DisplayPanel> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                  l10n.monitorSource,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: widget.controller.displays.isEmpty
                  ? Center(child: Text(l10n.noDisplays))
                  : ListView.separated(
                      controller: _scrollController,
                      itemCount: widget.controller.displays.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final display = widget.controller.displays[index];
                        return _DisplayTile(
                          display: display,
                          selected:
                              display.id == widget.controller.selectedDisplayId,
                          enabled: !widget.controller.busy,
                          onSelected: () => widget.onSelected(display.id),
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
    required this.onVideoProfileChanged,
    required this.onCopyDiagnostics,
  });

  final MirrorController controller;
  final TextEditingController hostController;
  final TextEditingController portController;
  final VoidCallback onRefresh;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ValueChanged<SenderVideoProfile> onVideoProfileChanged;
  final VoidCallback onCopyDiagnostics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final experimental4kReason = controller.canSelectExperimental4k30
        ? null
        : controller.selectedDisplay == null
        ? l10n.fourKSelectDisplay
        : l10n.fourKDisplayTooSmall;

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
                  l10n.betaVersion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: l10n.refreshDisplays,
                onPressed: controller.busy ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: l10n.copyDiagnostics,
                onPressed: onCopyDiagnostics,
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: hostController,
            enabled: !controller.isRunning,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: l10n.receiverIp,
              hintText: l10n.receiverIpExample,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: portController,
            enabled: !controller.isRunning,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: l10n.controlPort,
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
                    enabled:
                        profile != SenderVideoProfile.experimental4k30 ||
                        controller.canSelectExperimental4k30,
                    child: _VideoProfileMenuItem(profile: profile),
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
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: l10n.videoProfile,
            ),
          ),
          if (experimental4kReason != null) ...[
            const SizedBox(height: 6),
            Text(
              experimental4kReason,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.pcLocalAudioMuteRequested,
              onChanged: controller.setPcLocalAudioMuteRequested,
              title: Text(l10n.pcSoundMute),
              subtitle: Text(l10n.pcSoundMuteDescription),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              _pcSpeakerMuteMessage(l10n, controller),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
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
                label: Text(l10n.start),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: controller.canStop ? onStop : null,
                icon: const Icon(Icons.stop),
                label: Text(l10n.stop),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(l10n.sessionLog, style: Theme.of(context).textTheme.titleMedium),
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

class _VideoProfileMenuItem extends StatelessWidget {
  const _VideoProfileMenuItem({required this.profile});

  final SenderVideoProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            _videoProfileLabel(l10n, profile),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (profile.isExperimental) ...[
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                l10n.experimental,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SenderCounters extends StatelessWidget {
  const _SenderCounters({required this.snapshot});

  final NativeSessionSnapshot snapshot;

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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MetricRow(
              label: l10n.performance,
              value: snapshot.bottleneckSummary,
            ),
            const Divider(height: 18),
            _MetricSection(
              title: l10n.capture,
              rows: [
                _MetricRow(
                  label: l10n.profile,
                  value:
                      '${snapshot.requestedProfile} -> ${snapshot.appliedProfile} - '
                      '${snapshot.outputWidth}x${snapshot.outputHeight} - '
                      '${snapshot.targetBitrateKbps} kbps',
                ),
                if (snapshot.profileFallbackReason.isNotEmpty)
                  _MetricRow(
                    label: l10n.fallback,
                    value: snapshot.profileFallbackReason,
                  ),
                _MetricRow(
                  label: l10n.targetActual,
                  value:
                      '${snapshot.targetFps.toStringAsFixed(1)} / '
                      '${snapshot.admittedFrameFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: l10n.callback,
                  value:
                      '${snapshot.captureCallbackFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: l10n.intervalP95,
                  value:
                      '${snapshot.captureFrameIntervalP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.targetInterval,
                  value:
                      '${snapshot.targetFrameIntervalMs.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.replacedCadence,
                  value:
                      '${snapshot.captureReplacedFrames} / ${snapshot.cadenceSkippedFrames}',
                ),
                _MetricRow(
                  label: l10n.queueDepth,
                  value: '${snapshot.queueDepthCapture}',
                ),
              ],
            ),
            const Divider(height: 18),
            _MetricSection(
              title: l10n.convertEncode,
              rows: [
                _MetricRow(
                  label: l10n.admissionAccepted,
                  value:
                      '${snapshot.admittedFrameFps.toStringAsFixed(1)} / '
                      '${snapshot.encoderAcceptedFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: l10n.converted,
                  value: '${snapshot.convertedFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: l10n.encoderInput,
                  value: '${snapshot.encoderInputFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: l10n.encoded,
                  value: '${snapshot.encodedFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: l10n.convertPath,
                  value:
                      '${snapshot.captureToConvertAverageMs.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.encodeAvgP95,
                  value:
                      '${snapshot.encodeDurationAverageMs.toStringAsFixed(1)}/'
                      '${snapshot.encodeDurationP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.encoder,
                  value: snapshot.hardwareEncoderActive
                      ? '${snapshot.encoderName} (hardware)'
                      : '${snapshot.encoderName} (software)',
                ),
                _MetricRow(
                  label: l10n.fourKCapability,
                  value:
                      'enc ${snapshot.encoderSupportsRequestedResolution}, '
                      'tv ${snapshot.receiverSupports4k30} '
                      '${snapshot.receiverMaxWidth}x${snapshot.receiverMaxHeight}',
                ),
                _MetricRow(
                  label: l10n.backpressure,
                  value:
                      'not accepting ${snapshot.encoderNotAcceptingCount}, '
                      'drops ${snapshot.encoderBackpressureDroppedFrames}',
                ),
                _MetricRow(
                  label: l10n.processInOutP95,
                  value:
                      '${snapshot.processInputDurationP95Ms.toStringAsFixed(1)}/'
                      '${snapshot.processOutputDurationP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.readbackReuse,
                  value:
                      '${snapshot.gpuReadbackPerFrame ? l10n.valueReadback : l10n.valueZeroCopy}, '
                      '${snapshot.textureReuseEnabled ? l10n.valueReuse : l10n.valueAllocate}',
                ),
                _MetricRow(
                  label: l10n.queueDepth,
                  value: '${snapshot.queueDepthEncoder}',
                ),
              ],
            ),
            const Divider(height: 18),
            _MetricSection(
              title: l10n.network,
              rows: [
                _MetricRow(
                  label: l10n.sent,
                  value: '${snapshot.sentVideoFps.toStringAsFixed(1)} fps',
                ),
                _MetricRow(
                  label: l10n.sendIntervalP95,
                  value:
                      '${snapshot.sendFrameIntervalP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.sendDuration,
                  value:
                      '${snapshot.accessUnitSendDurationAverageMs.toStringAsFixed(1)}/'
                      '${snapshot.accessUnitSendDurationP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.socketCalls,
                  value:
                      '${snapshot.socketSendCallsPerSecond.toStringAsFixed(1)}/s',
                ),
                _MetricRow(
                  label: l10n.pending,
                  value: '${snapshot.pendingSendBytes} B',
                ),
                _MetricRow(
                  label: l10n.queueDepth,
                  value: '${snapshot.queueDepthTransport}',
                ),
                _MetricRow(
                  label: l10n.queueWaitAvgP95,
                  value:
                      '${snapshot.videoQueueWaitAverageMs.toStringAsFixed(1)}/'
                      '${snapshot.videoQueueWaitP95Ms.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.staleVideoDrops,
                  value:
                      '${snapshot.staleVideoDroppedFrames} '
                      '(${snapshot.staleVideoDroppedFps.toStringAsFixed(1)} fps)',
                ),
              ],
            ),
            const Divider(height: 18),
            _MetricSection(
              title: l10n.audio,
              rows: [
                _MetricRow(
                  label: l10n.audioState,
                  value: snapshot.audioEnabled
                      ? snapshot.audioCaptureState
                      : l10n.valueDisabled,
                ),
                _MetricRow(
                  label: l10n.audioDevice,
                  value: snapshot.audioDeviceName.isEmpty
                      ? l10n.valueUnknown
                      : snapshot.audioDeviceName,
                ),
                _MetricRow(
                  label: l10n.inputEncoded,
                  value:
                      '${snapshot.audioInputSampleRate} Hz ${snapshot.audioInputChannels} ch / '
                      '${snapshot.audioEncodedSampleRate} Hz ${snapshot.audioEncodedChannels} ch',
                ),
                _MetricRow(
                  label: l10n.captureSent,
                  value:
                      '${snapshot.audioCaptureFps.toStringAsFixed(1)} fps / '
                      '${snapshot.sentAudioPackets}',
                ),
                _MetricRow(
                  label: l10n.encodeAverage,
                  value:
                      '${snapshot.audioEncodeAverageMs.toStringAsFixed(1)} ms',
                ),
                _MetricRow(
                  label: l10n.queueDropped,
                  value:
                      '${snapshot.audioQueueDepth} / ${snapshot.audioDroppedPackets}',
                ),
                _MetricRow(
                  label: l10n.writerWaitVA,
                  value:
                      '${snapshot.packetWriterVideoWaitMs.toStringAsFixed(1)}/'
                      '${snapshot.packetWriterAudioWaitMs.toStringAsFixed(1)} ms',
                ),
                if (snapshot.audioLastError.isNotEmpty)
                  _MetricRow(
                    label: l10n.audioError,
                    value: snapshot.audioLastError,
                  ),
                _MetricRow(
                  label: l10n.tvAudioPath,
                  value:
                      'stream ${snapshot.tvAudioStreaming}, '
                      'cap ${snapshot.audioCaptureActive}, '
                      'enc ${snapshot.audioEncoderActive}, '
                      'net ${snapshot.audioTransportActive}',
                ),
              ],
            ),
            const Divider(height: 18),
            const Divider(height: 18),
            _MetricSection(
              title: l10n.pcSoundMute,
              rows: [
                _MetricRow(
                  label: l10n.pcMuteRequested,
                  value: snapshot.pcLocalAudioMuteRequested.toString(),
                ),
                _MetricRow(
                  label: l10n.pcMuteApplied,
                  value: snapshot.pcLocalAudioMuteApplied.toString(),
                ),
                _MetricRow(
                  label: l10n.pcMuteActual,
                  value: snapshot.pcLocalAudioActualMuted.toString(),
                ),
                _MetricRow(
                  label: l10n.pcMuteOriginal,
                  value: snapshot.pcLocalAudioOriginalMuteState.toString(),
                ),
                _MetricRow(
                  label: l10n.pcMuteExternalChange,
                  value: snapshot.pcLocalAudioMuteExternalOverride.toString(),
                ),
                _MetricRow(
                  label: l10n.pcMuteTargetDevice,
                  value: snapshot.pcLocalAudioMuteTargetDeviceId.isEmpty
                      ? '-'
                      : snapshot.pcLocalAudioMuteTargetDeviceId,
                ),
                _MetricRow(
                  label: l10n.pcMuteErrorCode,
                  value: snapshot.pcLocalAudioMuteErrorCode.isEmpty
                      ? '-'
                      : snapshot.pcLocalAudioMuteErrorCode,
                ),
                if (snapshot.localSpeakerMuteLastError.isNotEmpty)
                  _MetricRow(
                    label: l10n.audioError,
                    value: snapshot.localSpeakerMuteLastError,
                  ),
              ],
            ),
            const Divider(height: 18),
            _MetricSection(
              title: l10n.playbackControl,
              rows: [
                _MetricRow(
                  label: l10n.audioState,
                  value: snapshot.playbackState,
                ),
                _MetricRow(
                  label: l10n.pauseResume,
                  value:
                      '${snapshot.pauseRequestsReceived} / ${snapshot.resumeRequestsReceived}',
                ),
                _MetricRow(
                  label: l10n.ackError,
                  value:
                      '${snapshot.playbackCommandAcksSent} / ${snapshot.playbackCommandErrorsSent}',
                ),
                _MetricRow(
                  label: l10n.resumeConfigResend,
                  value: '${snapshot.resumeCodecConfigResends}',
                ),
              ],
            ),
            const Divider(height: 18),
            _MetricRow(
              label: l10n.capturedTotal,
              value: '${snapshot.capturedFrames}',
            ),
            _MetricRow(
              label: l10n.lastSequence,
              value: '${snapshot.lastProcessedFrameSequence}',
            ),
            _MetricRow(
              label: l10n.intentionalSkip,
              value:
                  '${snapshot.cadenceSkippedFrames} (${snapshot.cadenceDroppedFps.toStringAsFixed(1)} fps)',
            ),
            _MetricRow(
              label: l10n.realDrops,
              value:
                  'conv ${snapshot.conversionBackpressureDroppedFrames}, '
                  'enc ${snapshot.encoderBackpressureDroppedFrames}, '
                  'net ${snapshot.transportBackpressureDroppedFrames}, '
                  'stale ${snapshot.staleVideoDroppedFrames}',
            ),
            _MetricRow(
              label: l10n.configSent,
              value: '${snapshot.codecConfigSent}',
            ),
            _MetricRow(
              label: l10n.keyFrames,
              value: '${snapshot.keyFramesSent}',
            ),
            _MetricRow(
              label: l10n.totalDropped,
              value: '${snapshot.totalDroppedFrames}',
            ),
            _MetricRow(label: l10n.packets, value: '${snapshot.packetsSent}'),
            _MetricRow(label: l10n.bytes, value: '${snapshot.bytesSent}'),
            _MetricRow(
              label: l10n.sendCompleted,
              value: '${snapshot.sendCompletedBytes}',
            ),
            _MetricRow(
              label: l10n.queueDepth,
              value:
                  '${snapshot.queueDepthCapture}/'
                  '${snapshot.queueDepthEncoder}/'
                  '${snapshot.queueDepthTransport}',
            ),
            _MetricRow(
              label: l10n.captureToEncode,
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
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final failed =
        controller.state == MirrorSessionState.failed ||
        controller.state == MirrorSessionState.error;
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
                  Text(_senderStateLabel(l10n, controller.state)),
                  Text(_senderStatusMessage(l10n, controller.state)),
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
