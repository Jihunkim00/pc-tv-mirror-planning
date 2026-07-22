import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

abstract interface class MirrorNativeApi {
  Future<List<DisplayInfo>> listDisplays();

  Future<NativeSessionSnapshot> startSession(StartMirrorSessionRequest request);

  Future<NativeSessionSnapshot> stopSession(String sessionId);

  Future<NativeSessionSnapshot> getSessionStatus();
}

final class MethodChannelMirrorNativeApi implements MirrorNativeApi {
  const MethodChannelMirrorNativeApi();

  static const MethodChannel _channel = MethodChannel(
    'pc_tv_mirror/windows_sender',
  );

  @override
  Future<List<DisplayInfo>> listDisplays() async {
    final result = await _channel.invokeListMethod<Object?>('listDisplays');
    return (result ?? const <Object?>[])
        .map((item) => DisplayInfo.fromJson(_asJsonMap(item)))
        .toList(growable: false);
  }

  @override
  Future<NativeSessionSnapshot> startSession(
    StartMirrorSessionRequest request,
  ) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'startSession',
      request.toNativeArguments(),
    );
    return NativeSessionSnapshot.fromJson(_asJsonMap(result));
  }

  @override
  Future<NativeSessionSnapshot> stopSession(String sessionId) async {
    final request = StreamStopRequest(sessionId: sessionId);
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'stopSession',
      {'sessionId': sessionId, 'requestJson': jsonEncode(request.toJson())},
    );
    return NativeSessionSnapshot.fromJson(_asJsonMap(result));
  }

  @override
  Future<NativeSessionSnapshot> getSessionStatus() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getSessionStatus',
    );
    return NativeSessionSnapshot.fromJson(_asJsonMap(result));
  }
}

final class StartMirrorSessionRequest {
  const StartMirrorSessionRequest({
    required this.receiverHost,
    required this.receiverPort,
    required this.streamRequest,
  });

  final String receiverHost;
  final int receiverPort;
  final StreamStartRequest streamRequest;

  Map<String, Object?> toNativeArguments() {
    return {
      'receiverHost': receiverHost,
      'receiverPort': receiverPort,
      'sourceId': streamRequest.sourceId,
      'requestJson': jsonEncode(streamRequest.toJson()),
    };
  }
}

final class NativeSessionSnapshot {
  const NativeSessionSnapshot({
    required this.state,
    required this.userMessage,
    required this.captureReady,
    required this.encoderReady,
    required this.signalingReady,
    required this.nativeVideoPathReady,
    this.capturedFrames = 0,
    this.encodedFrames = 0,
    this.codecConfigSent = 0,
    this.keyFramesSent = 0,
    this.packetsSent = 0,
    this.bytesSent = 0,
    this.lastEncodeError,
    this.lastSendError,
    this.errorCode,
    this.developerMessage,
  });

  final MirrorSessionState state;
  final String userMessage;
  final bool captureReady;
  final bool encoderReady;
  final bool signalingReady;
  final bool nativeVideoPathReady;
  final int capturedFrames;
  final int encodedFrames;
  final int codecConfigSent;
  final int keyFramesSent;
  final int packetsSent;
  final int bytesSent;
  final String? lastEncodeError;
  final String? lastSendError;
  final MirrorErrorCode? errorCode;
  final String? developerMessage;

  factory NativeSessionSnapshot.fromJson(Map<String, Object?> json) {
    final errorCode = json['errorCode'];
    return NativeSessionSnapshot(
      state: MirrorSessionState.fromWireName(_readString(json, 'state')),
      userMessage: _readString(json, 'userMessage'),
      captureReady: _readBool(json, 'captureReady'),
      encoderReady: _readBool(json, 'encoderReady'),
      signalingReady: _readBool(json, 'signalingReady'),
      nativeVideoPathReady: _readBool(json, 'nativeVideoPathReady'),
      capturedFrames: _readOptionalInt(json, 'capturedFrames'),
      encodedFrames: _readOptionalInt(json, 'encodedFrames'),
      codecConfigSent: _readOptionalInt(json, 'codecConfigSent'),
      keyFramesSent: _readOptionalInt(json, 'keyFramesSent'),
      packetsSent: _readOptionalInt(json, 'packetsSent'),
      bytesSent: _readOptionalInt(json, 'bytesSent'),
      lastEncodeError: json['lastEncodeError'] as String?,
      lastSendError: json['lastSendError'] as String?,
      errorCode: errorCode == null
          ? null
          : MirrorErrorCode.fromWireName(_readString(json, 'errorCode')),
      developerMessage: json['developerMessage'] as String?,
    );
  }
}

Map<String, Object?> _asJsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  throw const FormatException('Expected object from native API');
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw FormatException('Expected string for $key');
}

bool _readBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected bool for $key');
}

int _readOptionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return 0;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('Expected int for $key');
}
