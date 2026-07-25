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
    this.receivedAccessUnitFps = 0,
    this.decoderInputFrames = 0,
    this.decoderOutputFrames = 0,
    int? releasedToSurfaceFrames,
    int? renderedFrames,
    this.droppedFrames = 0,
    this.decoderInputFps = 0,
    this.decoderOutputFps = 0,
    this.releasedToSurfaceFps = 0,
    this.lateFrameDropFps = 0,
    this.receivedFrameIntervalAverageMs = 0,
    this.receivedFrameIntervalP95Ms = 0,
    this.decoderOutputIntervalAverageMs = 0,
    this.presentedFrameIntervalAverageMs = 0,
    this.presentedFrameIntervalP95Ms = 0,
    this.receiverQueueDepth = 0,
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
    this.scaleMode = 'fit',
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
    this.lateOutputBuffersDropped = 0,
    this.frameSequenceGaps = 0,
    this.lastFrameAgeMs = 0,
    this.currentFrameAgeMs = 0,
    this.estimatedReceiverLatencyMs = 0,
    this.rendererMode = 'lowLatencyPaced',
    this.scheduledRenderFrames = 0,
    this.immediateRenderFallbackFrames = 0,
    this.averageRenderScheduleDelayMs = 0,
    this.p95RenderScheduleDelayMs = 0,
    this.playoutDelayMs = 0,
    this.pacingResyncCount = 0,
    this.fullscreenEnabled = false,
    this.autoFullscreen = true,
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
  final double receivedAccessUnitFps;
  final int decoderInputFrames;
  final int decoderOutputFrames;
  final int releasedToSurfaceFrames;
  final int droppedFrames;
  final double decoderInputFps;
  final double decoderOutputFps;
  final double releasedToSurfaceFps;
  final double lateFrameDropFps;
  final double receivedFrameIntervalAverageMs;
  final double receivedFrameIntervalP95Ms;
  final double decoderOutputIntervalAverageMs;
  final double presentedFrameIntervalAverageMs;
  final double presentedFrameIntervalP95Ms;
  final int receiverQueueDepth;
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
  final int lateOutputBuffersDropped;
  final int frameSequenceGaps;
  final double lastFrameAgeMs;
  final double currentFrameAgeMs;
  final double estimatedReceiverLatencyMs;
  final String rendererMode;
  final int scheduledRenderFrames;
  final int immediateRenderFallbackFrames;
  final double averageRenderScheduleDelayMs;
  final double p95RenderScheduleDelayMs;
  final double playoutDelayMs;
  final int pacingResyncCount;
  final bool fullscreenEnabled;
  final bool autoFullscreen;
  final String? lastDecoderError;
  final String? developerMessage;
  final MirrorErrorCode? errorCode;

  @Deprecated('Use releasedToSurfaceFrames; latch/render is not verified.')
  int get renderedFrames => releasedToSurfaceFrames;

  String get bottleneckSummary {
    if (receivedAccessUnitFps >= 27 &&
        releasedToSurfaceFps >= 27 &&
        presentedFrameIntervalP95Ms <= 50) {
      return 'healthy';
    }
    if (receivedAccessUnitFps >= 27 && decoderOutputFps < 27) {
      return 'decoder_bottleneck';
    }
    if (decoderOutputFps >= 27 && releasedToSurfaceFps < 27) {
      return 'presentation_bottleneck';
    }
    if (releasedToSurfaceFps >= 27 && presentedFrameIntervalP95Ms > 50) {
      return 'pacing_jitter';
    }
    if (receivedAccessUnitFps > 0 && receivedAccessUnitFps < 27) {
      return 'network_or_parser_bottleneck';
    }
    return 'warming_up';
  }

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
      receivedAccessUnitFps: _readOptionalDouble(
        json,
        'receivedAccessUnitFps',
      ),
      decoderInputFrames: _readOptionalInt(json, 'decoderInputFrames'),
      decoderOutputFrames: _readOptionalInt(json, 'decoderOutputFrames'),
      releasedToSurfaceFrames: _readOptionalInt(
        json,
        'releasedToSurfaceFrames',
        fallbackKey: 'renderedFrames',
      ),
      droppedFrames: _readOptionalInt(json, 'droppedFrames'),
      decoderInputFps: _readOptionalDouble(json, 'decoderInputFps'),
      decoderOutputFps: _readOptionalDouble(json, 'decoderOutputFps'),
      releasedToSurfaceFps: _readOptionalDouble(
        json,
        'releasedToSurfaceFps',
      ),
      lateFrameDropFps: _readOptionalDouble(json, 'lateFrameDropFps'),
      receivedFrameIntervalAverageMs: _readOptionalDouble(
        json,
        'receivedFrameIntervalAverageMs',
      ),
      receivedFrameIntervalP95Ms: _readOptionalDouble(
        json,
        'receivedFrameIntervalP95Ms',
      ),
      decoderOutputIntervalAverageMs: _readOptionalDouble(
        json,
        'decoderOutputIntervalAverageMs',
      ),
      presentedFrameIntervalAverageMs: _readOptionalDouble(
        json,
        'presentedFrameIntervalAverageMs',
      ),
      presentedFrameIntervalP95Ms: _readOptionalDouble(
        json,
        'presentedFrameIntervalP95Ms',
      ),
      receiverQueueDepth: _readOptionalInt(json, 'receiverQueueDepth'),
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
        defaultValue: 'fit',
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
      lateOutputBuffersDropped: _readOptionalInt(
        json,
        'lateOutputBuffersDropped',
      ),
      frameSequenceGaps: _readOptionalInt(json, 'frameSequenceGaps'),
      lastFrameAgeMs: _readOptionalDouble(json, 'lastFrameAgeMs'),
      currentFrameAgeMs: _readOptionalDouble(json, 'currentFrameAgeMs'),
      estimatedReceiverLatencyMs: _readOptionalDouble(
        json,
        'estimatedReceiverLatencyMs',
      ),
      rendererMode: _readOptionalString(json, 'rendererMode'),
      scheduledRenderFrames: _readOptionalInt(json, 'scheduledRenderFrames'),
      immediateRenderFallbackFrames: _readOptionalInt(
        json,
        'immediateRenderFallbackFrames',
      ),
      averageRenderScheduleDelayMs: _readOptionalDouble(
        json,
        'averageRenderScheduleDelayMs',
      ),
      p95RenderScheduleDelayMs: _readOptionalDouble(
        json,
        'p95RenderScheduleDelayMs',
      ),
      playoutDelayMs: _readOptionalDouble(json, 'playoutDelayMs'),
      pacingResyncCount: _readOptionalInt(json, 'pacingResyncCount'),
      fullscreenEnabled: _readOptionalBool(json, 'fullscreenEnabled'),
      autoFullscreen: _readOptionalBool(
        json,
        'autoFullscreen',
        defaultValue: true,
      ),
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

bool _readOptionalBool(
  Map<String, Object?> json,
  String key, {
  bool defaultValue = false,
}) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
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
