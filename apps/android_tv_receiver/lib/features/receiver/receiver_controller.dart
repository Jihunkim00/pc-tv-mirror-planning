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

  ReceiverCapabilities? get capabilities => _capabilities;
  ReceiverSessionSnapshot? get snapshot => _snapshot;
  MirrorSessionState get state => _state;
  String get statusMessage => _statusMessage;
  List<String> get log => List.unmodifiable(_log);
  bool get busy => _busy;

  Future<void> initialize() async {
    _setBusy(true);
    try {
      _capabilities = await _nativeApi.getCapabilities();
      _appendLog('Loaded receiver capabilities.');
      final snapshot = await _nativeApi.startReceiver(port: defaultPort);
      _applySnapshot(snapshot);
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
    _setBusy(true);
    try {
      final snapshot = await _nativeApi.stopReceiver();
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

  void _applySnapshot(ReceiverSessionSnapshot snapshot) {
    _snapshot = snapshot;
    _state = snapshot.state;
    _statusMessage = snapshot.userMessage;
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
