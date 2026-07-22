import 'package:flutter/services.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

abstract interface class ReceiverNativeApi {
  Future<ReceiverCapabilities> getCapabilities();

  Future<ReceiverSessionSnapshot> startReceiver({required int port});

  Future<ReceiverSessionSnapshot> stopReceiver();

  Future<ReceiverSessionSnapshot> getReceiverStatus();
}

final class MethodChannelReceiverNativeApi implements ReceiverNativeApi {
  const MethodChannelReceiverNativeApi();

  static const MethodChannel _channel = MethodChannel(
    'pc_tv_mirror/android_tv_receiver',
  );

  @override
  Future<ReceiverCapabilities> getCapabilities() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getCapabilities',
    );
    return ReceiverCapabilities.fromJson(_asJsonMap(result));
  }

  @override
  Future<ReceiverSessionSnapshot> startReceiver({required int port}) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'startReceiver',
      {'port': port},
    );
    return ReceiverSessionSnapshot.fromJson(_asJsonMap(result));
  }

  @override
  Future<ReceiverSessionSnapshot> stopReceiver() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'stopReceiver',
    );
    return ReceiverSessionSnapshot.fromJson(_asJsonMap(result));
  }

  @override
  Future<ReceiverSessionSnapshot> getReceiverStatus() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getReceiverStatus',
    );
    return ReceiverSessionSnapshot.fromJson(_asJsonMap(result));
  }
}

final class ReceiverSessionSnapshot {
  const ReceiverSessionSnapshot({
    required this.state,
    required this.userMessage,
    required this.receiverPort,
    required this.decoderReady,
    required this.surfaceRendererReady,
    this.bytesReceived = 0,
    this.configPacketsReceived = 0,
    this.accessUnitsReceived = 0,
    this.keyFramesReceived = 0,
    this.decoderInputFrames = 0,
    this.decoderOutputFrames = 0,
    this.renderedFrames = 0,
    this.droppedFrames = 0,
    this.lastDecoderError,
    this.developerMessage,
    this.errorCode,
  });

  final MirrorSessionState state;
  final String userMessage;
  final int receiverPort;
  final bool decoderReady;
  final bool surfaceRendererReady;
  final int bytesReceived;
  final int configPacketsReceived;
  final int accessUnitsReceived;
  final int keyFramesReceived;
  final int decoderInputFrames;
  final int decoderOutputFrames;
  final int renderedFrames;
  final int droppedFrames;
  final String? lastDecoderError;
  final String? developerMessage;
  final MirrorErrorCode? errorCode;

  factory ReceiverSessionSnapshot.fromJson(Map<String, Object?> json) {
    final errorCode = json['errorCode'];
    return ReceiverSessionSnapshot(
      state: MirrorSessionState.fromWireName(_readString(json, 'state')),
      userMessage: _readString(json, 'userMessage'),
      receiverPort: _readInt(json, 'receiverPort'),
      decoderReady: _readBool(json, 'decoderReady'),
      surfaceRendererReady: _readBool(json, 'surfaceRendererReady'),
      bytesReceived: _readOptionalInt(json, 'bytesReceived'),
      configPacketsReceived: _readOptionalInt(json, 'configPacketsReceived'),
      accessUnitsReceived: _readOptionalInt(json, 'accessUnitsReceived'),
      keyFramesReceived: _readOptionalInt(json, 'keyFramesReceived'),
      decoderInputFrames: _readOptionalInt(json, 'decoderInputFrames'),
      decoderOutputFrames: _readOptionalInt(json, 'decoderOutputFrames'),
      renderedFrames: _readOptionalInt(json, 'renderedFrames'),
      droppedFrames: _readOptionalInt(json, 'droppedFrames'),
      lastDecoderError: json['lastDecoderError'] as String?,
      developerMessage: json['developerMessage'] as String?,
      errorCode: errorCode == null
          ? null
          : MirrorErrorCode.fromWireName(_readString(json, 'errorCode')),
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

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Expected int for $key');
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
