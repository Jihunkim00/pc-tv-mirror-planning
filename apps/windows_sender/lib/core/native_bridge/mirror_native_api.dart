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
    this.targetFps = 30,
    this.captureCallbackFps = 0,
    this.capturedFps = 0,
    this.convertedFps = 0,
    this.encoderInputFps = 0,
    this.encodedFps = 0,
    this.sentAccessUnitFps = 0,
    this.captureFrameIntervalAverageMs = 0,
    this.captureFrameIntervalP95Ms = 0,
    this.encodeFrameIntervalAverageMs = 0,
    this.sendFrameIntervalAverageMs = 0,
    this.captureToConvertAverageMs = 0,
    this.convertToEncodeAverageMs = 0,
    this.encodeDurationAverageMs = 0,
    this.encodeDurationP95Ms = 0,
    this.encodeToSendAverageMs = 0,
    this.capturedFrames = 0,
    this.captureDroppedFrames = 0,
    this.conversionDroppedFrames = 0,
    this.encoderInputDroppedFrames = 0,
    this.encodedFrames = 0,
    this.transportDroppedFrames = 0,
    this.duplicatedFrames = 0,
    this.lastProcessedFrameSequence = 0,
    this.codecConfigSent = 0,
    this.keyFramesSent = 0,
    this.packetsSent = 0,
    this.bytesSent = 0,
    this.sendCompletedBytes = 0,
    this.socketSendCallsPerSecond = 0,
    this.averagePacketSendDurationMs = 0,
    this.accessUnitSendDurationAverageMs = 0,
    this.accessUnitSendDurationP95Ms = 0,
    this.pendingSendBytes = 0,
    this.lastSocketError,
    this.queueDepthCapture = 0,
    this.queueDepthEncoder = 0,
    this.queueDepthTransport = 0,
    this.lastCaptureToEncodeMs = 0,
    this.averageCaptureToEncodeMs = 0,
    this.maxCaptureToEncodeMs = 0,
    this.selectedEncoderName = 'unknown',
    this.selectedEncoderHardware = false,
    this.selectedEncoderAsync = false,
    this.encoderD3D11Aware = false,
    this.encoderInputFormat = 'NV12 1280x720@30',
    this.encoderOutputFormat = 'H.264 1280x720@30',
    this.averageEncodeDurationMs = 0,
    this.encoderBackpressureCount = 0,
    this.lowLatencyOptionsApplied = '',
    this.unsupportedEncoderOptions = '',
    this.bottleneckSummary = 'unknown',
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
  final double targetFps;
  final double captureCallbackFps;
  final double capturedFps;
  final double convertedFps;
  final double encoderInputFps;
  final double encodedFps;
  final double sentAccessUnitFps;
  final double captureFrameIntervalAverageMs;
  final double captureFrameIntervalP95Ms;
  final double encodeFrameIntervalAverageMs;
  final double sendFrameIntervalAverageMs;
  final double captureToConvertAverageMs;
  final double convertToEncodeAverageMs;
  final double encodeDurationAverageMs;
  final double encodeDurationP95Ms;
  final double encodeToSendAverageMs;
  final int capturedFrames;
  final int captureDroppedFrames;
  final int conversionDroppedFrames;
  final int encoderInputDroppedFrames;
  final int encodedFrames;
  final int transportDroppedFrames;
  final int duplicatedFrames;
  final int lastProcessedFrameSequence;
  final int codecConfigSent;
  final int keyFramesSent;
  final int packetsSent;
  final int bytesSent;
  final int sendCompletedBytes;
  final double socketSendCallsPerSecond;
  final double averagePacketSendDurationMs;
  final double accessUnitSendDurationAverageMs;
  final double accessUnitSendDurationP95Ms;
  final int pendingSendBytes;
  final String? lastSocketError;
  final int queueDepthCapture;
  final int queueDepthEncoder;
  final int queueDepthTransport;
  final double lastCaptureToEncodeMs;
  final double averageCaptureToEncodeMs;
  final double maxCaptureToEncodeMs;
  final String selectedEncoderName;
  final bool selectedEncoderHardware;
  final bool selectedEncoderAsync;
  final bool encoderD3D11Aware;
  final String encoderInputFormat;
  final String encoderOutputFormat;
  final double averageEncodeDurationMs;
  final int encoderBackpressureCount;
  final String lowLatencyOptionsApplied;
  final String unsupportedEncoderOptions;
  final String bottleneckSummary;
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
      targetFps: _readOptionalDouble(json, 'targetFps', defaultValue: 30),
      captureCallbackFps: _readOptionalDouble(json, 'captureCallbackFps'),
      capturedFps: _readOptionalDouble(json, 'capturedFps'),
      convertedFps: _readOptionalDouble(json, 'convertedFps'),
      encoderInputFps: _readOptionalDouble(json, 'encoderInputFps'),
      encodedFps: _readOptionalDouble(json, 'encodedFps'),
      sentAccessUnitFps: _readOptionalDouble(json, 'sentAccessUnitFps'),
      captureFrameIntervalAverageMs: _readOptionalDouble(
        json,
        'captureFrameIntervalAverageMs',
      ),
      captureFrameIntervalP95Ms: _readOptionalDouble(
        json,
        'captureFrameIntervalP95Ms',
      ),
      encodeFrameIntervalAverageMs: _readOptionalDouble(
        json,
        'encodeFrameIntervalAverageMs',
      ),
      sendFrameIntervalAverageMs: _readOptionalDouble(
        json,
        'sendFrameIntervalAverageMs',
      ),
      captureToConvertAverageMs: _readOptionalDouble(
        json,
        'captureToConvertAverageMs',
      ),
      convertToEncodeAverageMs: _readOptionalDouble(
        json,
        'convertToEncodeAverageMs',
      ),
      encodeDurationAverageMs: _readOptionalDouble(
        json,
        'encodeDurationAverageMs',
      ),
      encodeDurationP95Ms: _readOptionalDouble(json, 'encodeDurationP95Ms'),
      encodeToSendAverageMs: _readOptionalDouble(
        json,
        'encodeToSendAverageMs',
      ),
      capturedFrames: _readOptionalInt(json, 'capturedFrames'),
      captureDroppedFrames: _readOptionalInt(json, 'captureDroppedFrames'),
      conversionDroppedFrames: _readOptionalInt(
        json,
        'conversionDroppedFrames',
      ),
      encoderInputDroppedFrames: _readOptionalInt(
        json,
        'encoderInputDroppedFrames',
      ),
      encodedFrames: _readOptionalInt(json, 'encodedFrames'),
      transportDroppedFrames: _readOptionalInt(json, 'transportDroppedFrames'),
      duplicatedFrames: _readOptionalInt(json, 'duplicatedFrames'),
      lastProcessedFrameSequence: _readOptionalInt(
        json,
        'lastProcessedFrameSequence',
      ),
      codecConfigSent: _readOptionalInt(json, 'codecConfigSent'),
      keyFramesSent: _readOptionalInt(json, 'keyFramesSent'),
      packetsSent: _readOptionalInt(json, 'packetsSent'),
      bytesSent: _readOptionalInt(json, 'bytesSent'),
      sendCompletedBytes: _readOptionalInt(json, 'sendCompletedBytes'),
      socketSendCallsPerSecond: _readOptionalDouble(
        json,
        'socketSendCallsPerSecond',
      ),
      averagePacketSendDurationMs: _readOptionalDouble(
        json,
        'averagePacketSendDurationMs',
      ),
      accessUnitSendDurationAverageMs: _readOptionalDouble(
        json,
        'accessUnitSendDurationAverageMs',
      ),
      accessUnitSendDurationP95Ms: _readOptionalDouble(
        json,
        'accessUnitSendDurationP95Ms',
      ),
      pendingSendBytes: _readOptionalInt(json, 'pendingSendBytes'),
      lastSocketError: json['lastSocketError'] as String?,
      queueDepthCapture: _readOptionalInt(json, 'queueDepthCapture'),
      queueDepthEncoder: _readOptionalInt(json, 'queueDepthEncoder'),
      queueDepthTransport: _readOptionalInt(json, 'queueDepthTransport'),
      lastCaptureToEncodeMs: _readOptionalDouble(
        json,
        'lastCaptureToEncodeMs',
      ),
      averageCaptureToEncodeMs: _readOptionalDouble(
        json,
        'averageCaptureToEncodeMs',
      ),
      maxCaptureToEncodeMs: _readOptionalDouble(json, 'maxCaptureToEncodeMs'),
      selectedEncoderName: _readOptionalString(json, 'selectedEncoderName'),
      selectedEncoderHardware: _readOptionalBool(
        json,
        'selectedEncoderHardware',
      ),
      selectedEncoderAsync: _readOptionalBool(json, 'selectedEncoderAsync'),
      encoderD3D11Aware: _readOptionalBool(json, 'encoderD3D11Aware'),
      encoderInputFormat: _readOptionalString(json, 'encoderInputFormat'),
      encoderOutputFormat: _readOptionalString(json, 'encoderOutputFormat'),
      averageEncodeDurationMs: _readOptionalDouble(
        json,
        'averageEncodeDurationMs',
      ),
      encoderBackpressureCount: _readOptionalInt(
        json,
        'encoderBackpressureCount',
      ),
      lowLatencyOptionsApplied: _readOptionalString(
        json,
        'lowLatencyOptionsApplied',
        defaultValue: '',
      ),
      unsupportedEncoderOptions: _readOptionalString(
        json,
        'unsupportedEncoderOptions',
        defaultValue: '',
      ),
      bottleneckSummary: _readOptionalString(json, 'bottleneckSummary'),
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

double _readOptionalDouble(
  Map<String, Object?> json,
  String key, {
  double defaultValue = 0,
}) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  throw FormatException('Expected number for $key');
}

bool _readOptionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return false;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected bool for $key');
}

String _readOptionalString(
  Map<String, Object?> json,
  String key, {
  String defaultValue = 'unknown',
}) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('Expected string for $key');
}
