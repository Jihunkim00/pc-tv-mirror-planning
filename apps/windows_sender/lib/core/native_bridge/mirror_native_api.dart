import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

abstract interface class MirrorNativeApi {
  Future<List<DisplayInfo>> listDisplays();

  Future<NativeSessionSnapshot> startSession(StartMirrorSessionRequest request);

  Future<NativeSessionSnapshot> stopSession(String sessionId);

  Future<NativeSessionSnapshot> getSessionStatus();

  Future<NativeSessionSnapshot> setPcLocalAudioMuteRequested(bool requested);
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

  @override
  Future<NativeSessionSnapshot> setPcLocalAudioMuteRequested(
    bool requested,
  ) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'setPcLocalAudioMuteRequested',
      {'requested': requested},
    );
    return NativeSessionSnapshot.fromJson(_asJsonMap(result));
  }
}

final class StartMirrorSessionRequest {
  const StartMirrorSessionRequest({
    required this.receiverHost,
    required this.receiverPort,
    required this.streamRequest,
    this.pcLocalAudioMuteRequested = false,
  });

  final String receiverHost;
  final int receiverPort;
  final StreamStartRequest streamRequest;
  final bool pcLocalAudioMuteRequested;

  Map<String, Object?> toNativeArguments() {
    return {
      'receiverHost': receiverHost,
      'receiverPort': receiverPort,
      'sourceId': streamRequest.sourceId,
      'requestJson': jsonEncode(streamRequest.toJson()),
      'audioEnabled': streamRequest.audio?.enabled ?? false,
      'videoWidth': streamRequest.video.width,
      'videoHeight': streamRequest.video.height,
      'videoFps': streamRequest.video.fps,
      'videoBitrateKbps': streamRequest.video.bitrateKbps,
      'videoPerformanceProfile':
          streamRequest.video.performanceProfile.wireName,
      'pcLocalAudioMuteRequested': pcLocalAudioMuteRequested,
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
    this.targetAdmissionFps = 0,
    this.admittedFrameFps = 0,
    this.convertedFps = 0,
    this.encoderAcceptedFps = 0,
    this.encoderInputFps = 0,
    this.encodedFps = 0,
    this.sentVideoFps = 0,
    this.sentAccessUnitFps = 0,
    this.cadenceDroppedFps = 0,
    this.encoderBusyDroppedFps = 0,
    this.conversionBusyDroppedFps = 0,
    this.captureFrameIntervalAverageMs = 0,
    this.captureFrameIntervalP95Ms = 0,
    this.encodeFrameIntervalAverageMs = 0,
    this.sendFrameIntervalAverageMs = 0,
    this.sendFrameIntervalP95Ms = 0,
    this.captureToConvertAverageMs = 0,
    this.convertToEncodeAverageMs = 0,
    this.encodeDurationAverageMs = 0,
    this.encodeDurationP95Ms = 0,
    this.encodeToSendAverageMs = 0,
    this.videoQueueWaitAverageMs = 0,
    this.videoQueueWaitP95Ms = 0,
    this.capturedFrames = 0,
    this.captureReplacedFrames = 0,
    this.cadenceSkippedFrames = 0,
    this.conversionBackpressureDroppedFrames = 0,
    this.encoderBackpressureDroppedFrames = 0,
    this.transportBackpressureDroppedFrames = 0,
    this.staleVideoDroppedFrames = 0,
    this.shutdownDroppedFrames = 0,
    this.totalDroppedFrames = 0,
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
    this.admittedToEncodedRatio = 0,
    this.selectedProfile = 'lowLatency720p30',
    this.outputResolution = '1280x720',
    this.currentBitrateKbps = 6000,
    this.targetFrameIntervalMs = 33.333,
    this.staleVideoDroppedFps = 0,
    this.selectedEncoderName = 'unknown',
    this.selectedEncoderHardware = false,
    this.selectedEncoderAsync = false,
    this.encoderD3D11Aware = false,
    this.encoderInputFormat = 'NV12 1280x720@30',
    this.encoderOutputFormat = 'H.264 1280x720@30',
    this.averageEncodeDurationMs = 0,
    this.encoderBackpressureCount = 0,
    this.encoderNotAcceptingCount = 0,
    this.processInputCalls = 0,
    this.processInputAccepted = 0,
    this.processInputNotAccepting = 0,
    this.processInputRetries = 0,
    this.processOutputCalls = 0,
    this.processOutputFrames = 0,
    this.processInputDurationAverageMs = 0,
    this.processInputDurationP95Ms = 0,
    this.processOutputDurationAverageMs = 0,
    this.processOutputDurationP95Ms = 0,
    this.bgraToNv12Mode = 'cpuBgraToNv12',
    this.gpuReadbackPerFrame = true,
    this.textureReuseEnabled = true,
    this.lowLatencyOptionsApplied = '',
    this.unsupportedEncoderOptions = '',
    this.bottleneckSummary = 'unknown',
    this.lastEncodeError,
    this.lastSendError,
    this.audioEnabled = false,
    this.audioCaptureState = 'disabled',
    this.audioDeviceName = '',
    this.audioInputSampleRate = 0,
    this.audioInputChannels = 0,
    this.audioEncodedSampleRate = 48000,
    this.audioEncodedChannels = 2,
    this.capturedAudioPackets = 0,
    this.encodedAudioPackets = 0,
    this.sentAudioPackets = 0,
    this.audioCaptureFps = 0,
    this.audioEncodeAverageMs = 0,
    this.audioQueueDepth = 0,
    this.audioDroppedPackets = 0,
    this.audioLastError = '',
    this.videoFpsAudioDisabled = 0,
    this.videoFpsAudioEnabled = 0,
    this.audioCpuTimeMs = 0,
    this.packetWriterVideoWaitMs = 0,
    this.packetWriterAudioWaitMs = 0,
    this.playbackState = 'idle',
    this.pauseRequestsReceived = 0,
    this.resumeRequestsReceived = 0,
    this.playbackCommandAcksSent = 0,
    this.playbackCommandErrorsSent = 0,
    this.resumeCodecConfigResends = 0,
    this.localSpeakerMuteMode = 'pcAndTv',
    this.localSpeakerMuteState = 'disabled',
    this.localSpeakerMuteLastError = '',
    this.pcLocalAudioMuteRequested = false,
    this.pcLocalAudioMuteSupported = false,
    this.pcLocalAudioMuteApplied = false,
    this.pcLocalAudioOriginalMuteState = false,
    this.tvAudioStreaming = false,
    this.audioCaptureActive = false,
    this.audioEncoderActive = false,
    this.audioTransportActive = false,
    this.audioRoutingMode = 'defaultRenderEndpointLoopback',
    this.audioMuteUnsupportedReason = '',
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
  final double targetAdmissionFps;
  final double admittedFrameFps;
  final double convertedFps;
  final double encoderAcceptedFps;
  final double encoderInputFps;
  final double encodedFps;
  final double sentVideoFps;
  final double sentAccessUnitFps;
  final double cadenceDroppedFps;
  final double encoderBusyDroppedFps;
  final double conversionBusyDroppedFps;
  final double captureFrameIntervalAverageMs;
  final double captureFrameIntervalP95Ms;
  final double encodeFrameIntervalAverageMs;
  final double sendFrameIntervalAverageMs;
  final double sendFrameIntervalP95Ms;
  final double captureToConvertAverageMs;
  final double convertToEncodeAverageMs;
  final double encodeDurationAverageMs;
  final double encodeDurationP95Ms;
  final double encodeToSendAverageMs;
  final double videoQueueWaitAverageMs;
  final double videoQueueWaitP95Ms;
  final int capturedFrames;
  final int captureReplacedFrames;
  final int cadenceSkippedFrames;
  final int conversionBackpressureDroppedFrames;
  final int encoderBackpressureDroppedFrames;
  final int transportBackpressureDroppedFrames;
  final int staleVideoDroppedFrames;
  final int shutdownDroppedFrames;
  final int totalDroppedFrames;
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
  final double admittedToEncodedRatio;
  final String selectedProfile;
  final String outputResolution;
  final int currentBitrateKbps;
  final double targetFrameIntervalMs;
  final double staleVideoDroppedFps;
  final String selectedEncoderName;
  final bool selectedEncoderHardware;
  final bool selectedEncoderAsync;
  final bool encoderD3D11Aware;
  final String encoderInputFormat;
  final String encoderOutputFormat;
  final double averageEncodeDurationMs;
  final int encoderBackpressureCount;
  final int encoderNotAcceptingCount;
  final int processInputCalls;
  final int processInputAccepted;
  final int processInputNotAccepting;
  final int processInputRetries;
  final int processOutputCalls;
  final int processOutputFrames;
  final double processInputDurationAverageMs;
  final double processInputDurationP95Ms;
  final double processOutputDurationAverageMs;
  final double processOutputDurationP95Ms;
  final String bgraToNv12Mode;
  final bool gpuReadbackPerFrame;
  final bool textureReuseEnabled;
  final String lowLatencyOptionsApplied;
  final String unsupportedEncoderOptions;
  final String bottleneckSummary;
  final String? lastEncodeError;
  final String? lastSendError;
  final bool audioEnabled;
  final String audioCaptureState;
  final String audioDeviceName;
  final int audioInputSampleRate;
  final int audioInputChannels;
  final int audioEncodedSampleRate;
  final int audioEncodedChannels;
  final int capturedAudioPackets;
  final int encodedAudioPackets;
  final int sentAudioPackets;
  final double audioCaptureFps;
  final double audioEncodeAverageMs;
  final int audioQueueDepth;
  final int audioDroppedPackets;
  final String audioLastError;
  final double videoFpsAudioDisabled;
  final double videoFpsAudioEnabled;
  final double audioCpuTimeMs;
  final double packetWriterVideoWaitMs;
  final double packetWriterAudioWaitMs;
  final String playbackState;
  final int pauseRequestsReceived;
  final int resumeRequestsReceived;
  final int playbackCommandAcksSent;
  final int playbackCommandErrorsSent;
  final int resumeCodecConfigResends;
  final String localSpeakerMuteMode;
  final String localSpeakerMuteState;
  final String localSpeakerMuteLastError;
  final bool pcLocalAudioMuteRequested;
  final bool pcLocalAudioMuteSupported;
  final bool pcLocalAudioMuteApplied;
  final bool pcLocalAudioOriginalMuteState;
  final bool tvAudioStreaming;
  final bool audioCaptureActive;
  final bool audioEncoderActive;
  final bool audioTransportActive;
  final String audioRoutingMode;
  final String audioMuteUnsupportedReason;
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
      targetAdmissionFps: _readOptionalDouble(json, 'targetAdmissionFps'),
      admittedFrameFps: _readOptionalDouble(json, 'admittedFrameFps'),
      convertedFps: _readOptionalDouble(json, 'convertedFps'),
      encoderAcceptedFps: _readOptionalDouble(json, 'encoderAcceptedFps'),
      encoderInputFps: _readOptionalDouble(json, 'encoderInputFps'),
      encodedFps: _readOptionalDouble(json, 'encodedFps'),
      sentVideoFps: _readOptionalDouble(json, 'sentVideoFps'),
      sentAccessUnitFps: _readOptionalDouble(json, 'sentAccessUnitFps'),
      cadenceDroppedFps: _readOptionalDouble(json, 'cadenceDroppedFps'),
      encoderBusyDroppedFps: _readOptionalDouble(json, 'encoderBusyDroppedFps'),
      conversionBusyDroppedFps: _readOptionalDouble(
        json,
        'conversionBusyDroppedFps',
      ),
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
      sendFrameIntervalP95Ms: _readOptionalDouble(
        json,
        'sendFrameIntervalP95Ms',
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
      encodeToSendAverageMs: _readOptionalDouble(json, 'encodeToSendAverageMs'),
      videoQueueWaitAverageMs: _readOptionalDouble(
        json,
        'videoQueueWaitAverageMs',
      ),
      videoQueueWaitP95Ms: _readOptionalDouble(json, 'videoQueueWaitP95Ms'),
      capturedFrames: _readOptionalInt(json, 'capturedFrames'),
      captureReplacedFrames: _readOptionalInt(json, 'captureReplacedFrames'),
      cadenceSkippedFrames: _readOptionalInt(json, 'cadenceSkippedFrames'),
      conversionBackpressureDroppedFrames: _readOptionalInt(
        json,
        'conversionBackpressureDroppedFrames',
      ),
      encoderBackpressureDroppedFrames: _readOptionalInt(
        json,
        'encoderBackpressureDroppedFrames',
      ),
      transportBackpressureDroppedFrames: _readOptionalInt(
        json,
        'transportBackpressureDroppedFrames',
      ),
      staleVideoDroppedFrames: _readOptionalInt(
        json,
        'staleVideoDroppedFrames',
      ),
      shutdownDroppedFrames: _readOptionalInt(json, 'shutdownDroppedFrames'),
      totalDroppedFrames: _readOptionalInt(json, 'totalDroppedFrames'),
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
      lastCaptureToEncodeMs: _readOptionalDouble(json, 'lastCaptureToEncodeMs'),
      averageCaptureToEncodeMs: _readOptionalDouble(
        json,
        'averageCaptureToEncodeMs',
      ),
      maxCaptureToEncodeMs: _readOptionalDouble(json, 'maxCaptureToEncodeMs'),
      admittedToEncodedRatio: _readOptionalDouble(
        json,
        'admittedToEncodedRatio',
      ),
      selectedProfile: _readOptionalString(
        json,
        'selectedProfile',
        defaultValue: 'lowLatency720p30',
      ),
      outputResolution: _readOptionalString(
        json,
        'outputResolution',
        defaultValue: '1280x720',
      ),
      currentBitrateKbps: _readOptionalInt(
        json,
        'currentBitrateKbps',
        defaultValue: 6000,
      ),
      targetFrameIntervalMs: _readOptionalDouble(
        json,
        'targetFrameIntervalMs',
        defaultValue: 33.333,
      ),
      staleVideoDroppedFps: _readOptionalDouble(json, 'staleVideoDroppedFps'),
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
      encoderNotAcceptingCount: _readOptionalInt(
        json,
        'encoderNotAcceptingCount',
      ),
      processInputCalls: _readOptionalInt(json, 'processInputCalls'),
      processInputAccepted: _readOptionalInt(json, 'processInputAccepted'),
      processInputNotAccepting: _readOptionalInt(
        json,
        'processInputNotAccepting',
      ),
      processInputRetries: _readOptionalInt(json, 'processInputRetries'),
      processOutputCalls: _readOptionalInt(json, 'processOutputCalls'),
      processOutputFrames: _readOptionalInt(json, 'processOutputFrames'),
      processInputDurationAverageMs: _readOptionalDouble(
        json,
        'processInputDurationAverageMs',
      ),
      processInputDurationP95Ms: _readOptionalDouble(
        json,
        'processInputDurationP95Ms',
      ),
      processOutputDurationAverageMs: _readOptionalDouble(
        json,
        'processOutputDurationAverageMs',
      ),
      processOutputDurationP95Ms: _readOptionalDouble(
        json,
        'processOutputDurationP95Ms',
      ),
      bgraToNv12Mode: _readOptionalString(
        json,
        'bgraToNv12Mode',
        defaultValue: 'cpuBgraToNv12',
      ),
      gpuReadbackPerFrame: _readOptionalBool(
        json,
        'gpuReadbackPerFrame',
        defaultValue: true,
      ),
      textureReuseEnabled: _readOptionalBool(
        json,
        'textureReuseEnabled',
        defaultValue: true,
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
      audioEnabled: _readOptionalBool(json, 'audioEnabled'),
      audioCaptureState: _readOptionalString(
        json,
        'audioCaptureState',
        defaultValue: 'disabled',
      ),
      audioDeviceName: _readOptionalString(
        json,
        'audioDeviceName',
        defaultValue: '',
      ),
      audioInputSampleRate: _readOptionalInt(json, 'audioInputSampleRate'),
      audioInputChannels: _readOptionalInt(json, 'audioInputChannels'),
      audioEncodedSampleRate: _readOptionalInt(json, 'audioEncodedSampleRate'),
      audioEncodedChannels: _readOptionalInt(json, 'audioEncodedChannels'),
      capturedAudioPackets: _readOptionalInt(json, 'capturedAudioPackets'),
      encodedAudioPackets: _readOptionalInt(json, 'encodedAudioPackets'),
      sentAudioPackets: _readOptionalInt(json, 'sentAudioPackets'),
      audioCaptureFps: _readOptionalDouble(json, 'audioCaptureFps'),
      audioEncodeAverageMs: _readOptionalDouble(json, 'audioEncodeAverageMs'),
      audioQueueDepth: _readOptionalInt(json, 'audioQueueDepth'),
      audioDroppedPackets: _readOptionalInt(json, 'audioDroppedPackets'),
      audioLastError: _readOptionalString(
        json,
        'audioLastError',
        defaultValue: '',
      ),
      videoFpsAudioDisabled: _readOptionalDouble(json, 'videoFpsAudioDisabled'),
      videoFpsAudioEnabled: _readOptionalDouble(json, 'videoFpsAudioEnabled'),
      audioCpuTimeMs: _readOptionalDouble(json, 'audioCpuTimeMs'),
      packetWriterVideoWaitMs: _readOptionalDouble(
        json,
        'packetWriterVideoWaitMs',
      ),
      packetWriterAudioWaitMs: _readOptionalDouble(
        json,
        'packetWriterAudioWaitMs',
      ),
      playbackState: _readOptionalString(
        json,
        'playbackState',
        defaultValue: 'idle',
      ),
      pauseRequestsReceived: _readOptionalInt(json, 'pauseRequestsReceived'),
      resumeRequestsReceived: _readOptionalInt(json, 'resumeRequestsReceived'),
      playbackCommandAcksSent: _readOptionalInt(
        json,
        'playbackCommandAcksSent',
      ),
      playbackCommandErrorsSent: _readOptionalInt(
        json,
        'playbackCommandErrorsSent',
      ),
      resumeCodecConfigResends: _readOptionalInt(
        json,
        'resumeCodecConfigResends',
      ),
      localSpeakerMuteMode: _readOptionalString(
        json,
        'localSpeakerMuteMode',
        defaultValue: 'pcAndTv',
      ),
      localSpeakerMuteState: _readOptionalString(
        json,
        'localSpeakerMuteState',
        defaultValue: 'disabled',
      ),
      localSpeakerMuteLastError: _readOptionalString(
        json,
        'localSpeakerMuteLastError',
        defaultValue: '',
      ),
      pcLocalAudioMuteRequested: _readOptionalBool(
        json,
        'pcLocalAudioMuteRequested',
      ),
      pcLocalAudioMuteSupported: _readOptionalBool(
        json,
        'pcLocalAudioMuteSupported',
      ),
      pcLocalAudioMuteApplied: _readOptionalBool(
        json,
        'pcLocalAudioMuteApplied',
      ),
      pcLocalAudioOriginalMuteState: _readOptionalBool(
        json,
        'pcLocalAudioOriginalMuteState',
      ),
      tvAudioStreaming: _readOptionalBool(json, 'tvAudioStreaming'),
      audioCaptureActive: _readOptionalBool(json, 'audioCaptureActive'),
      audioEncoderActive: _readOptionalBool(json, 'audioEncoderActive'),
      audioTransportActive: _readOptionalBool(json, 'audioTransportActive'),
      audioRoutingMode: _readOptionalString(
        json,
        'audioRoutingMode',
        defaultValue: 'defaultRenderEndpointLoopback',
      ),
      audioMuteUnsupportedReason: _readOptionalString(
        json,
        'audioMuteUnsupportedReason',
        defaultValue: '',
      ),
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

int _readOptionalInt(
  Map<String, Object?> json,
  String key, {
  int defaultValue = 0,
}) {
  final value = json[key];
  if (value == null) {
    return defaultValue;
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
