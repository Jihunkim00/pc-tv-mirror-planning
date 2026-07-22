import 'package:flutter/foundation.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

import '../../core/native_bridge/mirror_native_api.dart';

class MirrorController extends ChangeNotifier {
  MirrorController(this._nativeApi);

  final MirrorNativeApi _nativeApi;

  var _displays = <DisplayInfo>[];
  var _state = MirrorSessionState.idle;
  var _log = <String>['Native sender bridge is idle.'];
  String? _selectedDisplayId;
  String? _activeSessionId;
  bool _busy = false;
  String? _userMessage;
  String? _developerMessage;

  List<DisplayInfo> get displays => List.unmodifiable(_displays);
  MirrorSessionState get state => _state;
  List<String> get log => List.unmodifiable(_log);
  String? get selectedDisplayId => _selectedDisplayId;
  bool get busy => _busy;
  String? get userMessage => _userMessage;
  String? get developerMessage => _developerMessage;
  bool get canStart => !_busy && _selectedDisplayId != null && !isRunning;
  bool get canStop => !_busy && isRunning;
  bool get isRunning =>
      _state == MirrorSessionState.connecting ||
      _state == MirrorSessionState.negotiating ||
      _state == MirrorSessionState.streaming;

  Future<void> loadDisplays() async {
    _setBusy(true);
    try {
      _displays = await _nativeApi.listDisplays();
      _selectedDisplayId = _displays
          .where((display) => display.isPrimary)
          .map((display) => display.id)
          .firstOrNull;
      _selectedDisplayId ??= _displays.firstOrNull?.id;
      _state = MirrorSessionState.idle;
      _userMessage = _displays.isEmpty
          ? 'No displays were reported by Windows.'
          : 'Select a display and enter the receiver IP.';
      _appendLog('Loaded ${_displays.length} display source(s).');
    } catch (error) {
      _state = MirrorSessionState.failed;
      _userMessage = 'Could not list Windows displays.';
      _developerMessage = '$error';
      _appendLog('Display enumeration failed.');
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

  Future<void> start({
    required String receiverHost,
    required int receiverPort,
  }) async {
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
    _appendLog('Starting STAGE 1 video session.');
    notifyListeners();

    final sessionId = 'stage1-${DateTime.now().microsecondsSinceEpoch}';
    final request = StreamStartRequest(
      sessionId: sessionId,
      sourceType: SourceType.display,
      sourceId: sourceId,
      video: const VideoProfile.stageOne720p30(),
    );

    try {
      final snapshot = await _nativeApi.startSession(
        StartMirrorSessionRequest(
          receiverHost: receiverHost,
          receiverPort: receiverPort,
          streamRequest: request,
        ),
      );
      _activeSessionId = sessionId;
      _applySnapshot(snapshot);
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
    _state = snapshot.state;
    _userMessage = snapshot.userMessage;
    _developerMessage = snapshot.developerMessage;
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
}
