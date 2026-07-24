import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

import '../../core/native_bridge/receiver_native_api.dart';

class ReceiverController extends ChangeNotifier {
  ReceiverController(this._nativeApi);

  static const int defaultPort = 50720;

  final ReceiverNativeApi _nativeApi;

  ReceiverCapabilities? _capabilities;
  ReceiverSessionSnapshot? _snapshot;
  MirrorSessionState _state = MirrorSessionState.idle;
  String _statusMessage = 'Receiver is starting.';
  List<String> _log = const ['Native receiver bridge is idle.'];
  bool _busy = false;
  Timer? _statusTimer;
  bool _pollingStatus = false;

  ReceiverCapabilities? get capabilities => _capabilities;
  ReceiverSessionSnapshot? get snapshot => _snapshot;
  MirrorSessionState get state => _state;
  String get statusMessage => _statusMessage;
  List<String> get log => List.unmodifiable(_log);
  bool get busy => _busy;

  Future<void> initialize() async {
    if (_busy) {
      return;
    }
    _setBusy(true);
    try {
      _capabilities = await _nativeApi.getCapabilities();
      _appendLog('Loaded receiver capabilities.');
      final snapshot = await _nativeApi.startReceiver(port: defaultPort);
      _applySnapshot(snapshot);
      _startPolling();
      _appendLog(snapshot.userMessage);
    } catch (error) {
      _state = MirrorSessionState.failed;
      _statusMessage = 'Receiver could not start.';
      _appendLog('Receiver start failed: $error');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> stop() async {
    if (_busy) {
      return;
    }
    _setBusy(true);
    try {
      final snapshot = await _nativeApi.stopReceiver();
      _stopPolling();
      _applySnapshot(snapshot);
      _appendLog(snapshot.userMessage);
    } catch (error) {
      _state = MirrorSessionState.failed;
      _statusMessage = 'Receiver stop failed.';
      _appendLog('Receiver stop failed: $error');
    } finally {
      _setBusy(false);
    }
  }

  void _applySnapshot(ReceiverSessionSnapshot snapshot, {bool notify = false}) {
    _snapshot = snapshot;
    _state = snapshot.state;
    _statusMessage = snapshot.userMessage;
    if (notify) {
      notifyListeners();
    }
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
    if (_pollingStatus) {
      return;
    }
    _pollingStatus = true;
    try {
      final snapshot = await _nativeApi.getReceiverStatus();
      _applySnapshot(snapshot, notify: true);
      if (snapshot.state == MirrorSessionState.idle) {
        _stopPolling();
      }
    } catch (error) {
      _appendLog('Receiver status polling failed: $error');
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
