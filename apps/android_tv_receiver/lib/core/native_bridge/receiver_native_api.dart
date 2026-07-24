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
    this.receiverBindAddress = '0.0.0.0',
    this.localIpv4Addresses = const <String>[],
    this.bytesReceived = 0,
    this.configPacketsReceived = 0,
    this.accessUnitsReceived = 0,
    this.keyFramesReceived = 0,
    this.decoderInputFrames = 0,
    this.decoderOutputFrames = 0,
    int? releasedToSurfaceFrames,
    int? renderedFrames,
    this.droppedFrames = 0,
    this.codecCreateCount = 0,
    this.codecReleaseCount = 0,
    this.surfaceCreatedCount = 0,
    this.surfaceChangedCount = 0,
    this.surfaceDestroyedCount = 0,
    this.surfaceIsValid = false,
    this.surfaceWidth = 0,
    this.surfaceHeight = 0,
    this.zOrderMode = 'unknown',
    this.firstSurfaceTestDrawSucceeded = false,
    this.sourceWidth = 1280,
    this.sourceHeight = 720,
    this.containerWidth = 0,
    this.containerHeight = 0,
    this.renderedViewWidth = 0,
    this.renderedViewHeight = 0,
    this.scaleMode = 'fitCenter',
    this.aspectRatioError = 0,
    this.configuredWidth = 0,
    this.configuredHeight = 0,
    this.outputWidth = 0,
    this.outputHeight = 0,
    this.outputFormatChangedCount = 0,
    this.outputCropLeft,
    this.outputCropRight,
    this.outputCropTop,
    this.outputCropBottom,
    this.networkToDecoderInputMs = 0,
    this.decoderInputToOutputMs = 0,
    this.estimatedEndToEndLatencyMs = 0,
    this.latencyAverageMs = 0,
    this.latencyP95Ms = 0,
    this.maxReceiverQueueDepth = 0,
    this.staleAccessUnitsDropped = 0,
    this.lastFrameAgeMs = 0,
    this.lastDecoderError,
    this.developerMessage,
    this.errorCode,
  }) : releasedToSurfaceFrames = releasedToSurfaceFrames ?? renderedFrames ?? 0;

  final MirrorSessionState state;
  final String userMessage;
  final int receiverPort;
  final bool decoderReady;
  final bool surfaceRendererReady;
  final String receiverBindAddress;
  final List<String> localIpv4Addresses;
  final int bytesReceived;
  final int configPacketsReceived;
  final int accessUnitsReceived;
  final int keyFramesReceived;
  final int decoderInputFrames;
  final int decoderOutputFrames;
  final int releasedToSurfaceFrames;
  final int droppedFrames;
  final int codecCreateCount;
  final int codecReleaseCount;
  final int surfaceCreatedCount;
  final int surfaceChangedCount;
  final int surfaceDestroyedCount;
  final bool surfaceIsValid;
  final int surfaceWidth;
  final int surfaceHeight;
  final String zOrderMode;
  final bool firstSurfaceTestDrawSucceeded;
  final int sourceWidth;
  final int sourceHeight;
  final int containerWidth;
  final int containerHeight;
  final int renderedViewWidth;
  final int renderedViewHeight;
  final String scaleMode;
  final double aspectRatioError;
  final int configuredWidth;
  final int configuredHeight;
  final int outputWidth;
  final int outputHeight;
  final int outputFormatChangedCount;
  final int? outputCropLeft;
  final int? outputCropRight;
  final int? outputCropTop;
  final int? outputCropBottom;
  final double networkToDecoderInputMs;
  final double decoderInputToOutputMs;
  final double estimatedEndToEndLatencyMs;
  final double latencyAverageMs;
  final double latencyP95Ms;
  final int maxReceiverQueueDepth;
  final int staleAccessUnitsDropped;
  final double lastFrameAgeMs;
  final String? lastDecoderError;
  final String? developerMessage;
  final MirrorErrorCode? errorCode;

  @Deprecated('Use releasedToSurfaceFrames; latch/render is not verified.')
  int get renderedFrames => releasedToSurfaceFrames;

  factory ReceiverSessionSnapshot.fromJson(Map<String, Object?> json) {
    final errorCode = json['errorCode'];
    return ReceiverSessionSnapshot(
      state: MirrorSessionState.fromWireName(_readString(json, 'state')),
      userMessage: _readString(json, 'userMessage'),
      receiverPort: _readInt(json, 'receiverPort'),
      decoderReady: _readBool(json, 'decoderReady'),
      surfaceRendererReady: _readBool(json, 'surfaceRendererReady'),
      receiverBindAddress: _readOptionalString(
        json,
        'receiverBindAddress',
        defaultValue: '0.0.0.0',
      ),
      localIpv4Addresses: _readOptionalStringList(json, 'localIpv4Addresses'),
      bytesReceived: _readOptionalInt(json, 'bytesReceived'),
      configPacketsReceived: _readOptionalInt(json, 'configPacketsReceived'),
      accessUnitsReceived: _readOptionalInt(json, 'accessUnitsReceived'),
      keyFramesReceived: _readOptionalInt(json, 'keyFramesReceived'),
      decoderInputFrames: _readOptionalInt(json, 'decoderInputFrames'),
      decoderOutputFrames: _readOptionalInt(json, 'decoderOutputFrames'),
      releasedToSurfaceFrames: _readOptionalInt(
        json,
        'releasedToSurfaceFrames',
        fallbackKey: 'renderedFrames',
      ),
      droppedFrames: _readOptionalInt(json, 'droppedFrames'),
      codecCreateCount: _readOptionalInt(json, 'codecCreateCount'),
      codecReleaseCount: _readOptionalInt(json, 'codecReleaseCount'),
      surfaceCreatedCount: _readOptionalInt(json, 'surfaceCreatedCount'),
      surfaceChangedCount: _readOptionalInt(json, 'surfaceChangedCount'),
      surfaceDestroyedCount: _readOptionalInt(json, 'surfaceDestroyedCount'),
      surfaceIsValid: _readOptionalBool(json, 'surfaceIsValid'),
      surfaceWidth: _readOptionalInt(json, 'surfaceWidth'),
      surfaceHeight: _readOptionalInt(json, 'surfaceHeight'),
      zOrderMode: _readOptionalString(json, 'zOrderMode'),
      firstSurfaceTestDrawSucceeded: _readOptionalBool(
        json,
        'firstSurfaceTestDrawSucceeded',
      ),
      sourceWidth: _readOptionalInt(json, 'sourceWidth'),
      sourceHeight: _readOptionalInt(json, 'sourceHeight'),
      containerWidth: _readOptionalInt(json, 'containerWidth'),
      containerHeight: _readOptionalInt(json, 'containerHeight'),
      renderedViewWidth: _readOptionalInt(json, 'renderedViewWidth'),
      renderedViewHeight: _readOptionalInt(json, 'renderedViewHeight'),
      scaleMode: _readOptionalString(
        json,
        'scaleMode',
        defaultValue: 'fitCenter',
      ),
      aspectRatioError: _readOptionalDouble(json, 'aspectRatioError'),
      configuredWidth: _readOptionalInt(json, 'configuredWidth'),
      configuredHeight: _readOptionalInt(json, 'configuredHeight'),
      outputWidth: _readOptionalInt(json, 'outputWidth'),
      outputHeight: _readOptionalInt(json, 'outputHeight'),
      outputFormatChangedCount: _readOptionalInt(
        json,
        'outputFormatChangedCount',
      ),
      outputCropLeft: _readOptionalNullableInt(json, 'outputCropLeft'),
      outputCropRight: _readOptionalNullableInt(json, 'outputCropRight'),
      outputCropTop: _readOptionalNullableInt(json, 'outputCropTop'),
      outputCropBottom: _readOptionalNullableInt(json, 'outputCropBottom'),
      networkToDecoderInputMs: _readOptionalDouble(
        json,
        'networkToDecoderInputMs',
      ),
      decoderInputToOutputMs: _readOptionalDouble(
        json,
        'decoderInputToOutputMs',
      ),
      estimatedEndToEndLatencyMs: _readOptionalDouble(
        json,
        'estimatedEndToEndLatencyMs',
      ),
      latencyAverageMs: _readOptionalDouble(json, 'latencyAverageMs'),
      latencyP95Ms: _readOptionalDouble(json, 'latencyP95Ms'),
      maxReceiverQueueDepth: _readOptionalInt(json, 'maxReceiverQueueDepth'),
      staleAccessUnitsDropped: _readOptionalInt(
        json,
        'staleAccessUnitsDropped',
      ),
      lastFrameAgeMs: _readOptionalDouble(json, 'lastFrameAgeMs'),
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

List<String> _readOptionalStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const <String>[];
  }
  if (value is List && value.every((item) => item is String)) {
    return value.cast<String>();
  }
  throw FormatException('Expected string list for $key');
}

double _readOptionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return 0;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected number for $key');
}

int _readOptionalInt(
  Map<String, Object?> json,
  String key, {
  String? fallbackKey,
}) {
  final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
  if (value == null) {
    return 0;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('Expected int for $key');
}

int? _readOptionalNullableInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('Expected int for $key');
}
