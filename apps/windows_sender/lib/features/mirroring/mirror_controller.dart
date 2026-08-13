import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

import '../../core/native_bridge/mirror_native_api.dart';

enum SenderVideoProfile {
  lowLatency720p30,
  highQuality1080p30,
  cinema1080p24,
  compatibility720p30,
  experimental4k30;

  String get label {
    return switch (this) {
      SenderVideoProfile.lowLatency720p30 => '720p30 HQ',
      SenderVideoProfile.highQuality1080p30 => '1080p30 HQ',
      SenderVideoProfile.cinema1080p24 => '1080p24 Cinema',
      SenderVideoProfile.compatibility720p30 => '720p30 Compat',
      SenderVideoProfile.experimental4k30 => '4K 30fps (Experimental)',
    };
  }

  String get description {
    return switch (this) {
      SenderVideoProfile.lowLatency720p30 => 'Low-latency 720p30 H.264',
      SenderVideoProfile.highQuality1080p30 => 'Balanced 1080p30 H.264',
      SenderVideoProfile.cinema1080p24 =>
        'FHD 24fps Cinema H.264 with display pacing',
      SenderVideoProfile.compatibility720p30 => 'Lower bitrate 720p30 H.264',
      SenderVideoProfile.experimental4k30 =>
        'Requires compatible hardware encoder, Android TV decoder, and wired LAN',
    };
  }

  VideoProfile get videoProfile {
    return switch (this) {
      SenderVideoProfile.lowLatency720p30 =>
        const VideoProfile.lowLatency720p30(),
      SenderVideoProfile.highQuality1080p30 =>
        const VideoProfile.highQuality1080p30(),
      SenderVideoProfile.cinema1080p24 => const VideoProfile.cinema1080p24(),
      SenderVideoProfile.compatibility720p30 =>
        const VideoProfile.compatibility720p30(),
      SenderVideoProfile.experimental4k30 =>
        const VideoProfile.experimental4k30(),
    };
  }
}

class MirrorController extends ChangeNotifier {
  MirrorController(this._nativeApi);

  final MirrorNativeApi _nativeApi;

  var _displays = <DisplayInfo>[];
  var _audioDevices = <AudioDeviceInfo>[];
  var _state = MirrorSessionState.idle;
  var _log = <String>['Native sender bridge is idle.'];
  NativeSessionSnapshot? _snapshot;
  String? _selectedDisplayId;
  String? _selectedTvAudioSourceDeviceId;
  String? _selectedPcMonitorDeviceId;
  String? _activeSessionId;
  bool _busy = false;
  bool _systemAudioEnabled = true;
  bool _pcLocalAudioMuteRequested = false;
  SenderVideoProfile _videoProfile = SenderVideoProfile.lowLatency720p30;
  String? _userMessage;
  String? _developerMessage;
  Timer? _statusTimer;
  bool _pollingStatus = false;

  List<DisplayInfo> get displays => List.unmodifiable(_displays);
  List<AudioDeviceInfo> get audioDevices => List.unmodifiable(_audioDevices);
  MirrorSessionState get state => _state;
  NativeSessionSnapshot? get snapshot => _snapshot;
  List<String> get log => List.unmodifiable(_log);
  String? get selectedDisplayId => _selectedDisplayId;
  String? get selectedTvAudioSourceDeviceId => _selectedTvAudioSourceDeviceId;
  String? get selectedPcMonitorDeviceId => _selectedPcMonitorDeviceId;
  bool get busy => _busy;
  bool get systemAudioEnabled => _systemAudioEnabled;
  bool get pcLocalAudioMuteRequested => _pcLocalAudioMuteRequested;
  SenderVideoProfile get videoProfile => _videoProfile;
  String? get userMessage => _userMessage;
  String? get developerMessage => _developerMessage;
  bool get canStart => !_busy && _selectedDisplayId != null && !isRunning;
  bool get canStop => !_busy && isRunning;
  DisplayInfo? get selectedDisplay => _displays
      .where((display) => display.id == _selectedDisplayId)
      .firstOrNull;
  AudioDeviceInfo? get selectedTvAudioSourceDevice => _audioDevices
      .where((device) => device.id == _selectedTvAudioSourceDeviceId)
      .firstOrNull;
  AudioDeviceInfo? get selectedPcMonitorDevice => _audioDevices
      .where((device) => device.id == _selectedPcMonitorDeviceId)
      .firstOrNull;
  bool get hasLikelyVirtualAudioSource =>
      _audioDevices.any((device) => device.isLikelyVirtual);
  bool get pcLocalAudioMuteSupportedBySelection =>
      audioRoutingUnsupportedReason == null;
  String? get audioRoutingUnsupportedReason {
    if (!_systemAudioEnabled) {
      return 'System audio is disabled';
    }
    final source = selectedTvAudioSourceDevice;
    final monitor = selectedPcMonitorDevice;
    if (source == null) {
      return 'No TV audio source selected';
    }
    if (monitor == null) {
      return 'No PC speaker output selected';
    }
    if (source.id == monitor.id) {
      return 'TV source and PC speaker output are the same endpoint';
    }
    if (!source.isLikelyVirtual) {
      return 'No separate virtual audio endpoint found';
    }
    return null;
  }

  bool get canSelectExperimental4k30 {
    final display = selectedDisplay;
    return display != null && display.width >= 3840 && display.height >= 2160;
  }

  String? get experimental4kUnavailableReason {
    final display = selectedDisplay;
    if (display == null) {
      return '4K unavailable: select a display first';
    }
    if (display.width < 3840 || display.height < 2160) {
      return '4K unavailable: capture source is below 3840x2160';
    }
    return null;
  }

  bool get isRunning =>
      _state == MirrorSessionState.starting ||
      _state == MirrorSessionState.listening ||
      _state == MirrorSessionState.connecting ||
      _state == MirrorSessionState.negotiating ||
      _state == MirrorSessionState.waitingForSurface ||
      _state == MirrorSessionState.waitingForKeyFrame ||
      _state == MirrorSessionState.streaming ||
      _state == MirrorSessionState.paused ||
      _state == MirrorSessionState.resuming;

  Future<void> loadDisplays() async {
    _setBusy(true);
    try {
      _displays = await _nativeApi.listDisplays();
      _audioDevices = await _nativeApi.listAudioDevices();
      _selectedDisplayId = _displays
          .where((display) => display.isPrimary)
          .map((display) => display.id)
          .firstOrNull;
      _selectedDisplayId ??= _displays.firstOrNull?.id;
      _selectDefaultAudioDevices();
      _state = MirrorSessionState.idle;
      _userMessage = _displays.isEmpty
          ? 'No displays were reported by Windows.'
          : 'Select a display and enter the receiver IP.';
      _appendLog('Loaded ${_displays.length} display source(s).');
      _appendLog('Loaded ${_audioDevices.length} audio output device(s).');
    } catch (error) {
      _state = MirrorSessionState.failed;
      _userMessage = 'Could not list Windows display or audio devices.';
      _developerMessage = '$error';
      _appendLog('Source enumeration failed.');
    } finally {
      _setBusy(false);
    }
  }

  void selectDisplay(String displayId) {
    if (_selectedDisplayId == displayId || isRunning) {
      return;
    }
    _selectedDisplayId = displayId;
    _appendLog('Selected $displayId.');
    notifyListeners();
  }

  void selectTvAudioSourceDevice(String deviceId) {
    if (_selectedTvAudioSourceDeviceId == deviceId || isRunning) {
      return;
    }
    _selectedTvAudioSourceDeviceId = deviceId;
    _appendLog('Selected TV audio source.');
    notifyListeners();
  }

  void selectPcMonitorDevice(String deviceId) {
    if (_selectedPcMonitorDeviceId == deviceId || isRunning) {
      return;
    }
    _selectedPcMonitorDeviceId = deviceId;
    _appendLog('Selected PC speaker output.');
    notifyListeners();
  }

  Future<void> refreshAudioDevices() async {
    if (_busy || isRunning) {
      return;
    }
    _setBusy(true);
    try {
      _audioDevices = await _nativeApi.listAudioDevices();
      _selectDefaultAudioDevices(preserveExisting: true);
      _appendLog('Refreshed ${_audioDevices.length} audio output device(s).');
    } catch (error) {
      _developerMessage = '$error';
      _appendLog('Audio device refresh failed.');
    } finally {
      _setBusy(false);
    }
  }

  void setSystemAudioEnabled(bool enabled) {
    if (_systemAudioEnabled == enabled || isRunning) {
      return;
    }
    _systemAudioEnabled = enabled;
    if (!enabled) {
      _pcLocalAudioMuteRequested = false;
    }
    _appendLog('System audio ${enabled ? 'enabled' : 'disabled'}.');
    notifyListeners();
  }

  void setPcLocalAudioMuteRequested(bool enabled) {
    if (_pcLocalAudioMuteRequested == enabled) {
      return;
    }
    if (!_systemAudioEnabled) {
      return;
    }
    _pcLocalAudioMuteRequested = enabled;
    _appendLog(
      enabled
          ? 'Mute PC speakers requested; TV audio transport remains enabled.'
          : 'Mute PC speakers disabled.',
    );
    if (isRunning) {
      unawaited(_applyPcLocalAudioMuteRequested(enabled));
    }
    notifyListeners();
  }

  Future<void> _applyPcLocalAudioMuteRequested(bool enabled) async {
    try {
      final snapshot = await _nativeApi.setPcLocalAudioMuteRequested(enabled);
      _applySnapshot(snapshot);
    } catch (error) {
      _developerMessage = '$error';
      _appendLog('Mute PC speakers request failed.');
      notifyListeners();
    }
  }

  void setVideoProfile(SenderVideoProfile profile) {
    if (_videoProfile == profile || isRunning) {
      return;
    }
    if (profile == SenderVideoProfile.experimental4k30 &&
        !canSelectExperimental4k30) {
      final reason = experimental4kUnavailableReason ?? '4K is unavailable.';
      _developerMessage = reason;
      _appendLog(reason);
      notifyListeners();
      return;
    }
    _videoProfile = profile;
    final video = profile.videoProfile;
    _appendLog(
      'Selected ${video.width}x${video.height}@${video.fps} '
      '${video.bitrateKbps} kbps.',
    );
    notifyListeners();
  }

  Future<void> start({
    required String receiverHost,
    required int receiverPort,
  }) async {
    if (_busy || isRunning) {
      return;
    }
    final sourceId = _selectedDisplayId;
    if (sourceId == null) {
      _state = MirrorSessionState.failed;
      _userMessage = 'Select a monitor before starting.';
      notifyListeners();
      return;
    }

    _setBusy(true);
    _state = MirrorSessionState.connecting;
    _userMessage = 'Preparing the native video path.';
    _appendLog(
      'Starting ${_videoProfile.videoProfile.performanceProfile.wireName} '
      'video session '
      'with system audio ${_systemAudioEnabled ? 'enabled' : 'disabled'} '
      'and PC speaker mute '
      '${_pcLocalAudioMuteRequested ? 'requested' : 'off'}.',
    );
    notifyListeners();

    final sessionId = 'stage1-${DateTime.now().microsecondsSinceEpoch}';
    final request = StreamStartRequest(
      sessionId: sessionId,
      sourceType: SourceType.display,
      sourceId: sourceId,
      video: _videoProfile.videoProfile,
      audio: _systemAudioEnabled
          ? const AudioProfile.systemAacLc()
          : const AudioProfile.disabled(),
    );

    try {
      final snapshot = await _nativeApi.startSession(
        StartMirrorSessionRequest(
          receiverHost: receiverHost,
          receiverPort: receiverPort,
          streamRequest: request,
          pcLocalAudioMuteRequested: _pcLocalAudioMuteRequested,
          tvAudioSourceDeviceId: _selectedTvAudioSourceDeviceId,
          pcMonitorDeviceId: _selectedPcMonitorDeviceId,
        ),
      );
      _activeSessionId = sessionId;
      _applySnapshot(snapshot);
      _startPolling();
      _appendLog(snapshot.userMessage);
    } catch (error) {
      _state = MirrorSessionState.failed;
      _userMessage = 'Could not start the native sender.';
      _developerMessage = '$error';
      _appendLog('Native start failed.');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> stop() async {
    if (_busy) {
      return;
    }
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      _state = MirrorSessionState.idle;
      notifyListeners();
      return;
    }

    _setBusy(true);
    _state = MirrorSessionState.stopping;
    _userMessage = 'Stopping the video session.';
    _appendLog('Stopping session $sessionId.');
    notifyListeners();

    try {
      final snapshot = await _nativeApi.stopSession(sessionId);
      _activeSessionId = null;
      _stopPolling();
      _applySnapshot(snapshot);
      _appendLog(snapshot.userMessage);
    } catch (error) {
      _state = MirrorSessionState.restoring;
      _userMessage = 'Native stop failed; local cleanup is required.';
      _developerMessage = '$error';
      _appendLog('Native stop failed.');
    } finally {
      _setBusy(false);
    }
  }

  void _applySnapshot(NativeSessionSnapshot snapshot) {
    _snapshot = snapshot;
    _state = snapshot.state;
    _userMessage = snapshot.userMessage;
    _developerMessage =
        snapshot.lastEncodeError ??
        snapshot.lastSendError ??
        snapshot.developerMessage;
    notifyListeners();
  }

  void _selectDefaultAudioDevices({bool preserveExisting = false}) {
    String? existingSource = preserveExisting
        ? _selectedTvAudioSourceDeviceId
        : null;
    String? existingMonitor = preserveExisting
        ? _selectedPcMonitorDeviceId
        : null;
    if (existingSource != null &&
        !_audioDevices.any((device) => device.id == existingSource)) {
      existingSource = null;
    }
    if (existingMonitor != null &&
        !_audioDevices.any((device) => device.id == existingMonitor)) {
      existingMonitor = null;
    }

    _selectedTvAudioSourceDeviceId =
        existingSource ??
        _audioDevices
            .where((device) => device.isLikelyVirtual)
            .map((device) => device.id)
            .firstOrNull ??
        _audioDevices
            .where((device) => device.isDefault)
            .map((device) => device.id)
            .firstOrNull ??
        _audioDevices.firstOrNull?.id;
    _selectedPcMonitorDeviceId =
        existingMonitor ??
        _audioDevices
            .where(
              (device) =>
                  device.isDefault &&
                  device.id != _selectedTvAudioSourceDeviceId,
            )
            .map((device) => device.id)
            .firstOrNull ??
        _audioDevices
            .where(
              (device) =>
                  !device.isLikelyVirtual &&
                  device.id != _selectedTvAudioSourceDeviceId,
            )
            .map((device) => device.id)
            .firstOrNull;
  }

  void _startPolling() {
    _statusTimer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollStatus(),
    );
  }

  void _stopPolling() {
    _statusTimer?.cancel();
    _statusTimer = null;
    _pollingStatus = false;
  }

  Future<void> _pollStatus() async {
    if (_pollingStatus || _activeSessionId == null) {
      return;
    }
    _pollingStatus = true;
    try {
      final snapshot = await _nativeApi.getSessionStatus();
      _applySnapshot(snapshot);
      if (snapshot.state == MirrorSessionState.idle ||
          snapshot.state == MirrorSessionState.failed) {
        _stopPolling();
      }
    } catch (error) {
      _developerMessage = '$error';
      _appendLog('Sender status polling failed.');
      _stopPolling();
      notifyListeners();
    } finally {
      _pollingStatus = false;
    }
  }

  void _setBusy(bool value) {
    if (_busy == value) {
      return;
    }
    _busy = value;
    notifyListeners();
  }

  void _appendLog(String message) {
    _log = [_timestamped(message), ..._log].take(8).toList(growable: false);
  }

  String _timestamped(String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss  $message';
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
