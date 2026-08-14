import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:mirror_protocol/mirror_protocol.dart';

abstract interface class MirrorNativeApi {
  Future<List<DisplayInfo>> listDisplays();

  Future<List<AudioDeviceInfo>> listAudioDevices();

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
  Future<List<AudioDeviceInfo>> listAudioDevices() async {
    final result = await _channel.invokeListMethod<Object?>('listAudioDevices');
    return (result ?? const <Object?>[])
        .map((item) => AudioDeviceInfo.fromJson(_asJsonMap(item)))
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
    this.tvAudioSourceDeviceId,
    this.pcMonitorDeviceId,
  });

  final String receiverHost;
  final int receiverPort;
  final StreamStartRequest streamRequest;
  final bool pcLocalAudioMuteRequested;
  final String? tvAudioSourceDeviceId;
  final String? pcMonitorDeviceId;

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
      if (tvAudioSourceDeviceId != null)
        'tvAudioSourceDeviceId': tvAudioSourceDeviceId,
      if (pcMonitorDeviceId != null) 'pcMonitorDeviceId': pcMonitorDeviceId,
    };
  }
}

final class AudioDeviceInfo {
  const AudioDeviceInfo({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.isLikelyVirtual,
  });

  final String id;
  final String name;
  final bool isDefault;
  final bool isLikelyVirtual;

  factory AudioDeviceInfo.fromJson(Map<String, Object?> json) {
    return AudioDeviceInfo(
      id: _readString(json, 'id'),
      name: _readString(json, 'name'),
      isDefault: _readOptionalBool(json, 'isDefault'),
      isLikelyVirtual: _readOptionalBool(json, 'isLikelyVirtual'),
    );
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
    this.framePoolApi = 'CreateFreeThreaded',
    this.framePoolBufferCount = 3,
    this.frameArrivedCallbackEnterCount = 0,
    this.frameArrivedCallbackExitCount = 0,
    this.frameArrivedCallbackAverageMs = 0,
    this.frameArrivedCallbackP95Ms = 0,
    this.frameArrivedCallbackMaxMs = 0,
    this.frameHeldAverageMs = 0,
    this.frameHeldP95Ms = 0,
    this.frameHeldMaxMs = 0,
    this.ownedTextureCopyFps = 0,
    this.ownedTextureCopyAverageMs = 0,
    this.ownedTextureCopyP95Ms = 0,
    this.workerProcessingAverageMs = 0,
    this.workerProcessingP95Ms = 0,
    this.handoffSlots = 3,
    this.handoffInUse = 0,
    this.workerQueueDepth = 0,
    this.workerFramesAccepted = 0,
    this.workerFramesProcessed = 0,
    this.workerFrameReplacementCount = 0,
    this.workerFrameDropCount = 0,
    this.latestFrameAgeMs = 0,
    this.captureThreadId = 0,
    this.conversionThreadId = 0,
    this.callbackOverlapCount = 0,
    this.callbackReentrantCount = 0,
    this.d3dMultithreadProtectionEnabled = false,
    this.measuredDeliveryBottleneck = 'unknown',
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
    this.frameArrivedCallbackFps = 0,
    this.tryGetNextFrameSuccessFps = 0,
    this.tryGetNextFrameNullCount = 0,
    this.rawWgcIntervalP50Ms = 0,
    this.rawWgcIntervalP95Ms = 0,
    this.frameAcquireAverageMs = 0,
    this.frameAcquireP95Ms = 0,
    this.copyResourceAverageMs = 0,
    this.copyResourceP95Ms = 0,
    this.mapReadbackAverageMs = 0,
    this.mapReadbackP95Ms = 0,
    this.scaleAverageMs = 0,
    this.scaleP95Ms = 0,
    this.bgraToNv12AverageMs = 0,
    this.bgraToNv12P95Ms = 0,
    this.nv12CopyAverageMs = 0,
    this.nv12CopyP95Ms = 0,
    this.samplePrepareAverageMs = 0,
    this.samplePrepareP95Ms = 0,
    this.captureToEncoderReadyAverageMs = 0,
    this.captureToEncoderReadyP95Ms = 0,
    this.processInputAverageMs = 0,
    this.processInputP95Ms = 0,
    this.encodeToSendAverageMs = 0,
    this.videoQueueWaitAverageMs = 0,
    this.videoQueueWaitP95Ms = 0,
    this.capturedFrames = 0,
    this.captureReplacedFrames = 0,
    this.cadenceSkippedFrames = 0,
    this.cadenceSkippedRecent = 0,
    this.cadenceSkipReason = 'unavailable',
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
    this.sourceDisplayWidth = 0,
    this.sourceDisplayHeight = 0,
    this.sourceDisplayRefreshHz = 0,
    this.sourceDisplayDeviceName = '',
    this.captureSystemRelativeTimeNs = 0,
    this.senderGeneratedPtsUs = 0,
    this.sourceTimestampDeltaUs = 0,
    this.videoPtsSource = 'unavailable',
    this.captureIntervalFromSourceP50Ms = 0,
    this.captureIntervalFromSourceP95Ms = 0,
    this.captureIntervalFromSourceMaxMs = 0,
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
    this.mftInputStreamFlags = 0,
    this.mftDoesNotAddref = false,
    this.mftHoldsBuffers = false,
    this.mftInputBufferSize = 0,
    this.mftInputBufferAlignment = 0,
    this.encoderInputSampleId = 0,
    this.encoderInputBufferId = 0,
    this.inputSampleCreateCount = 0,
    this.inputBufferCreateCount = 0,
    this.inputBufferPoolSize = 0,
    this.inputBuffersInFlight = 0,
    this.inputBufferReuseCount = 0,
    this.unsafeInputBufferReuseDetected = 0,
    this.nv12GuardCorruptionCount = 0,
    this.keyFrameCount = 0,
    this.framesSinceLastKeyFrame = 0,
    this.lastKeyFramePtsUs = 0,
    this.lastKeyFrameSizeBytes = 0,
    this.lastKeyFrameIntervalFrames = 0,
    this.lastKeyFrameIntervalMs = 0,
    this.keyframeIntervalFrames = 0,
    this.processInputDurationAverageMs = 0,
    this.processInputDurationP95Ms = 0,
    this.processOutputDurationAverageMs = 0,
    this.processOutputDurationP95Ms = 0,
    this.sourceTextureWidth = 0,
    this.sourceTextureHeight = 0,
    this.sourceTextureFormat = 'unavailable',
    this.sourceRowPitch = 0,
    this.sourceBgraStride = 0,
    this.nv12YOffset = 0,
    this.nv12UvOffset = 0,
    this.nv12YStride = 0,
    this.nv12UvStride = 0,
    this.nv12ExpectedBytes = 0,
    this.nv12AllocatedBytes = 0,
    this.nv12UsedBytes = 0,
    this.encoderInputStride = 0,
    this.bgraToNv12Mode = 'cpuBgraToNv12',
    this.gpuReadbackPerFrame = true,
    this.textureReuseEnabled = true,
    this.lowLatencyOptionsApplied = '',
    this.unsupportedEncoderOptions = '',
    this.bottleneckSummary = 'unknown',
    this.captureBottleneckStage = 'unknown',
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
    this.tvAudioSourceDeviceId = '',
    this.tvAudioSourceDeviceName = '',
    this.pcMonitorDeviceId = '',
    this.pcMonitorDeviceName = '',
    this.localMonitorActive = false,
    this.localMonitorMuted = false,
    this.localMonitorQueueDepth = 0,
    this.localMonitorDroppedBuffers = 0,
    this.audioCaptureFormat = '',
    this.audioMonitorFormat = '',
    this.audioRoutingUnsupportedReason = '',
    this.requestedProfile = 'lowLatency720p30',
    this.appliedProfile = 'lowLatency720p30',
    this.profileFallbackReason = '',
    this.outputWidth = 1280,
    this.outputHeight = 720,
    this.targetBitrateKbps = 6000,
    this.encoderName = 'unknown',
    this.hardwareEncoderActive = false,
    this.encoderSupportsRequestedResolution = false,
    this.receiverMaxWidth = 0,
    this.receiverMaxFps = 0,
    this.receiverMaxHeight = 0,
    this.receiverSupports4k30 = false,
    this.captureFpsRecent = 0,
    this.conversionFpsRecent = 0,
    this.encoderInputFpsRecent = 0,
    this.encoderOutputFpsRecent = 0,
    this.transportVideoFpsRecent = 0,
    this.receiverPresentedFpsRecent = 0,
    this.receiverReceivedFpsRecent = 0,
    this.receiverDecoderInputFpsRecent = 0,
    this.receiverDecoderOutputFpsRecent = 0,
    this.receiverDecoderOutputReleased = 0,
    this.receiverDecoderOutputReleasedImmediate = 0,
    this.receiverDecoderOutputReleasedScheduled = 0,
    this.receiverOnFrameRenderedCallbacks = 0,
    this.receiverVideoRenderMode = 'unavailable',
    this.receiverPtsIntervalP50Ms = 0,
    this.receiverPtsRegressionCount = 0,
    this.encodedAccessUnitBytes = 0,
    this.transportedAccessUnitBytes = 0,
    this.videoAuSizeMismatchCount = 0,
    this.videoFragmentMissingCount = 0,
    this.videoAuReassemblyErrorCount = 0,
    this.receiverAccessUnitBytes = 0,
    this.receiverKeyFramesReceived = 0,
    this.receiverCodecConfigsReceived = 0,
    this.receiverDecoderConfiguredWidth = 0,
    this.receiverDecoderConfiguredHeight = 0,
    this.receiverDecoderOutputWidth = 0,
    this.receiverDecoderOutputHeight = 0,
    this.receiverDecoderCropLeft = 0,
    this.receiverDecoderCropTop = 0,
    this.receiverDecoderCropRight = 0,
    this.receiverDecoderCropBottom = 0,
    this.receiverDecoderFormatChangeCount = 0,
    this.receiverSurfaceWidth = 0,
    this.receiverSurfaceHeight = 0,
    this.conversionDurationP95Ms = 0,
    this.encoderQueueWaitP95Ms = 0,
    this.transportSendP95Ms = 0,
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
  final String framePoolApi;
  final int framePoolBufferCount;
  final int frameArrivedCallbackEnterCount;
  final int frameArrivedCallbackExitCount;
  final double frameArrivedCallbackAverageMs;
  final double frameArrivedCallbackP95Ms;
  final double frameArrivedCallbackMaxMs;
  final double frameHeldAverageMs;
  final double frameHeldP95Ms;
  final double frameHeldMaxMs;
  final double ownedTextureCopyFps;
  final double ownedTextureCopyAverageMs;
  final double ownedTextureCopyP95Ms;
  final double workerProcessingAverageMs;
  final double workerProcessingP95Ms;
  final int handoffSlots;
  final int handoffInUse;
  final int workerQueueDepth;
  final int workerFramesAccepted;
  final int workerFramesProcessed;
  final int workerFrameReplacementCount;
  final int workerFrameDropCount;
  final double latestFrameAgeMs;
  final int captureThreadId;
  final int conversionThreadId;
  final int callbackOverlapCount;
  final int callbackReentrantCount;
  final bool d3dMultithreadProtectionEnabled;
  final String measuredDeliveryBottleneck;
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
  final double frameArrivedCallbackFps;
  final double tryGetNextFrameSuccessFps;
  final int tryGetNextFrameNullCount;
  final double rawWgcIntervalP50Ms;
  final double rawWgcIntervalP95Ms;
  final double frameAcquireAverageMs;
  final double frameAcquireP95Ms;
  final double copyResourceAverageMs;
  final double copyResourceP95Ms;
  final double mapReadbackAverageMs;
  final double mapReadbackP95Ms;
  final double scaleAverageMs;
  final double scaleP95Ms;
  final double bgraToNv12AverageMs;
  final double bgraToNv12P95Ms;
  final double nv12CopyAverageMs;
  final double nv12CopyP95Ms;
  final double samplePrepareAverageMs;
  final double samplePrepareP95Ms;
  final double captureToEncoderReadyAverageMs;
  final double captureToEncoderReadyP95Ms;
  final double processInputAverageMs;
  final double processInputP95Ms;
  final double encodeToSendAverageMs;
  final double videoQueueWaitAverageMs;
  final double videoQueueWaitP95Ms;
  final int capturedFrames;
  final int captureReplacedFrames;
  final int cadenceSkippedFrames;
  final int cadenceSkippedRecent;
  final String cadenceSkipReason;
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
  final int sourceDisplayWidth;
  final int sourceDisplayHeight;
  final double sourceDisplayRefreshHz;
  final String sourceDisplayDeviceName;
  final int captureSystemRelativeTimeNs;
  final int senderGeneratedPtsUs;
  final int sourceTimestampDeltaUs;
  final String videoPtsSource;
  final double captureIntervalFromSourceP50Ms;
  final double captureIntervalFromSourceP95Ms;
  final double captureIntervalFromSourceMaxMs;
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
  final int mftInputStreamFlags;
  final bool mftDoesNotAddref;
  final bool mftHoldsBuffers;
  final int mftInputBufferSize;
  final int mftInputBufferAlignment;
  final int encoderInputSampleId;
  final int encoderInputBufferId;
  final int inputSampleCreateCount;
  final int inputBufferCreateCount;
  final int inputBufferPoolSize;
  final int inputBuffersInFlight;
  final int inputBufferReuseCount;
  final int unsafeInputBufferReuseDetected;
  final int nv12GuardCorruptionCount;
  final int keyFrameCount;
  final int framesSinceLastKeyFrame;
  final int lastKeyFramePtsUs;
  final int lastKeyFrameSizeBytes;
  final int lastKeyFrameIntervalFrames;
  final int lastKeyFrameIntervalMs;
  final int keyframeIntervalFrames;
  final double processInputDurationAverageMs;
  final double processInputDurationP95Ms;
  final double processOutputDurationAverageMs;
  final double processOutputDurationP95Ms;
  final int sourceTextureWidth;
  final int sourceTextureHeight;
  final String sourceTextureFormat;
  final int sourceRowPitch;
  final int sourceBgraStride;
  final int nv12YOffset;
  final int nv12UvOffset;
  final int nv12YStride;
  final int nv12UvStride;
  final int nv12ExpectedBytes;
  final int nv12AllocatedBytes;
  final int nv12UsedBytes;
  final int encoderInputStride;
  final String bgraToNv12Mode;
  final bool gpuReadbackPerFrame;
  final bool textureReuseEnabled;
  final String lowLatencyOptionsApplied;
  final String unsupportedEncoderOptions;
  final String bottleneckSummary;
  final String captureBottleneckStage;
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
  final String tvAudioSourceDeviceId;
  final String tvAudioSourceDeviceName;
  final String pcMonitorDeviceId;
  final String pcMonitorDeviceName;
  final bool localMonitorActive;
  final bool localMonitorMuted;
  final int localMonitorQueueDepth;
  final int localMonitorDroppedBuffers;
  final String audioCaptureFormat;
  final String audioMonitorFormat;
  final String audioRoutingUnsupportedReason;
  final String requestedProfile;
  final String appliedProfile;
  final String profileFallbackReason;
  final int outputWidth;
  final int outputHeight;
  final int targetBitrateKbps;
  final String encoderName;
  final bool hardwareEncoderActive;
  final bool encoderSupportsRequestedResolution;
  final int receiverMaxFps;
  final int receiverMaxWidth;
  final int receiverMaxHeight;
  final bool receiverSupports4k30;
  final double captureFpsRecent;
  final double conversionFpsRecent;
  final double encoderInputFpsRecent;
  final double encoderOutputFpsRecent;
  final double transportVideoFpsRecent;
  final double receiverPresentedFpsRecent;
  final double receiverReceivedFpsRecent;
  final double receiverDecoderInputFpsRecent;
  final double receiverDecoderOutputFpsRecent;
  final int receiverDecoderOutputReleased;
  final int receiverDecoderOutputReleasedImmediate;
  final int receiverDecoderOutputReleasedScheduled;
  final int receiverOnFrameRenderedCallbacks;
  final String receiverVideoRenderMode;
  final double receiverPtsIntervalP50Ms;
  final int receiverPtsRegressionCount;
  final int encodedAccessUnitBytes;
  final int transportedAccessUnitBytes;
  final int videoAuSizeMismatchCount;
  final int videoFragmentMissingCount;
  final int videoAuReassemblyErrorCount;
  final int receiverAccessUnitBytes;
  final int receiverKeyFramesReceived;
  final int receiverCodecConfigsReceived;
  final int receiverDecoderConfiguredWidth;
  final int receiverDecoderConfiguredHeight;
  final int receiverDecoderOutputWidth;
  final int receiverDecoderOutputHeight;
  final int receiverDecoderCropLeft;
  final int receiverDecoderCropTop;
  final int receiverDecoderCropRight;
  final int receiverDecoderCropBottom;
  final int receiverDecoderFormatChangeCount;
  final int receiverSurfaceWidth;
  final int receiverSurfaceHeight;
  final double conversionDurationP95Ms;
  final double encoderQueueWaitP95Ms;
  final double transportSendP95Ms;
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
      framePoolApi: _readOptionalString(
        json,
        'framePoolApi',
        defaultValue: 'CreateFreeThreaded',
      ),
      framePoolBufferCount: _readOptionalInt(
        json,
        'framePoolBufferCount',
        defaultValue: 3,
      ),
      frameArrivedCallbackEnterCount: _readOptionalInt(
        json,
        'frameArrivedCallbackEnterCount',
      ),
      frameArrivedCallbackExitCount: _readOptionalInt(
        json,
        'frameArrivedCallbackExitCount',
      ),
      frameArrivedCallbackAverageMs: _readOptionalDouble(
        json,
        'frameArrivedCallbackAverageMs',
      ),
      frameArrivedCallbackP95Ms: _readOptionalDouble(
        json,
        'frameArrivedCallbackP95Ms',
      ),
      frameArrivedCallbackMaxMs: _readOptionalDouble(
        json,
        'frameArrivedCallbackMaxMs',
      ),
      frameHeldAverageMs: _readOptionalDouble(json, 'frameHeldAverageMs'),
      frameHeldP95Ms: _readOptionalDouble(json, 'frameHeldP95Ms'),
      frameHeldMaxMs: _readOptionalDouble(json, 'frameHeldMaxMs'),
      ownedTextureCopyFps: _readOptionalDouble(json, 'ownedTextureCopyFps'),
      ownedTextureCopyAverageMs: _readOptionalDouble(
        json,
        'ownedTextureCopyAverageMs',
      ),
      ownedTextureCopyP95Ms: _readOptionalDouble(
        json,
        'ownedTextureCopyP95Ms',
      ),
      workerProcessingAverageMs: _readOptionalDouble(
        json,
        'workerProcessingAverageMs',
      ),
      workerProcessingP95Ms: _readOptionalDouble(
        json,
        'workerProcessingP95Ms',
      ),
      handoffSlots: _readOptionalInt(json, 'handoffSlots', defaultValue: 3),
      handoffInUse: _readOptionalInt(json, 'handoffInUse'),
      workerQueueDepth: _readOptionalInt(json, 'workerQueueDepth'),
      workerFramesAccepted: _readOptionalInt(json, 'workerFramesAccepted'),
      workerFramesProcessed: _readOptionalInt(json, 'workerFramesProcessed'),
      workerFrameReplacementCount: _readOptionalInt(
        json,
        'workerFrameReplacementCount',
      ),
      workerFrameDropCount: _readOptionalInt(json, 'workerFrameDropCount'),
      latestFrameAgeMs: _readOptionalDouble(json, 'latestFrameAgeMs'),
      captureThreadId: _readOptionalInt(json, 'captureThreadId'),
      conversionThreadId: _readOptionalInt(json, 'conversionThreadId'),
      callbackOverlapCount: _readOptionalInt(json, 'callbackOverlapCount'),
      callbackReentrantCount: _readOptionalInt(json, 'callbackReentrantCount'),
      d3dMultithreadProtectionEnabled: _readOptionalBool(
        json,
        'd3dMultithreadProtectionEnabled',
      ),
      measuredDeliveryBottleneck: _readOptionalString(
        json,
        'measuredDeliveryBottleneck',
        defaultValue: 'unknown',
      ),
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
      frameArrivedCallbackFps: _readOptionalDouble(
        json,
        'frameArrivedCallbackFps',
      ),
      tryGetNextFrameSuccessFps: _readOptionalDouble(
        json,
        'tryGetNextFrameSuccessFps',
      ),
      tryGetNextFrameNullCount: _readOptionalInt(
        json,
        'tryGetNextFrameNullCount',
      ),
      rawWgcIntervalP50Ms: _readOptionalDouble(json, 'rawWgcIntervalP50Ms'),
      rawWgcIntervalP95Ms: _readOptionalDouble(json, 'rawWgcIntervalP95Ms'),
      frameAcquireAverageMs: _readOptionalDouble(json, 'frameAcquireAverageMs'),
      frameAcquireP95Ms: _readOptionalDouble(json, 'frameAcquireP95Ms'),
      copyResourceAverageMs: _readOptionalDouble(json, 'copyResourceAverageMs'),
      copyResourceP95Ms: _readOptionalDouble(json, 'copyResourceP95Ms'),
      mapReadbackAverageMs: _readOptionalDouble(json, 'mapReadbackAverageMs'),
      mapReadbackP95Ms: _readOptionalDouble(json, 'mapReadbackP95Ms'),
      scaleAverageMs: _readOptionalDouble(json, 'scaleAverageMs'),
      scaleP95Ms: _readOptionalDouble(json, 'scaleP95Ms'),
      bgraToNv12AverageMs: _readOptionalDouble(json, 'bgraToNv12AverageMs'),
      bgraToNv12P95Ms: _readOptionalDouble(json, 'bgraToNv12P95Ms'),
      nv12CopyAverageMs: _readOptionalDouble(json, 'nv12CopyAverageMs'),
      nv12CopyP95Ms: _readOptionalDouble(json, 'nv12CopyP95Ms'),
      samplePrepareAverageMs: _readOptionalDouble(
        json,
        'samplePrepareAverageMs',
      ),
      samplePrepareP95Ms: _readOptionalDouble(json, 'samplePrepareP95Ms'),
      captureToEncoderReadyAverageMs: _readOptionalDouble(
        json,
        'captureToEncoderReadyAverageMs',
      ),
      captureToEncoderReadyP95Ms: _readOptionalDouble(
        json,
        'captureToEncoderReadyP95Ms',
      ),
      processInputAverageMs: _readOptionalDouble(json, 'processInputAverageMs'),
      processInputP95Ms: _readOptionalDouble(json, 'processInputP95Ms'),
      encodeToSendAverageMs: _readOptionalDouble(json, 'encodeToSendAverageMs'),
      videoQueueWaitAverageMs: _readOptionalDouble(
        json,
        'videoQueueWaitAverageMs',
      ),
      videoQueueWaitP95Ms: _readOptionalDouble(json, 'videoQueueWaitP95Ms'),
      capturedFrames: _readOptionalInt(json, 'capturedFrames'),
      captureReplacedFrames: _readOptionalInt(json, 'captureReplacedFrames'),
      cadenceSkippedFrames: _readOptionalInt(json, 'cadenceSkippedFrames'),
      cadenceSkippedRecent: _readOptionalInt(json, 'cadenceSkippedRecent'),
      cadenceSkipReason: _readOptionalString(
        json,
        'cadenceSkipReason',
        defaultValue: 'unavailable',
      ),
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
      sourceDisplayWidth: _readOptionalInt(json, 'sourceDisplayWidth'),
      sourceDisplayHeight: _readOptionalInt(json, 'sourceDisplayHeight'),
      sourceDisplayRefreshHz: _readOptionalDouble(
        json,
        'sourceDisplayRefreshHz',
      ),
      sourceDisplayDeviceName: _readOptionalString(
        json,
        'sourceDisplayDeviceName',
      ),
      captureSystemRelativeTimeNs: _readOptionalInt(
        json,
        'captureSystemRelativeTimeNs',
      ),
      senderGeneratedPtsUs: _readOptionalInt(json, 'senderGeneratedPtsUs'),
      sourceTimestampDeltaUs: _readOptionalInt(json, 'sourceTimestampDeltaUs'),
      videoPtsSource: _readOptionalString(
        json,
        'videoPtsSource',
        defaultValue: 'unavailable',
      ),
      captureIntervalFromSourceP50Ms: _readOptionalDouble(
        json,
        'captureIntervalFromSourceP50Ms',
      ),
      captureIntervalFromSourceP95Ms: _readOptionalDouble(
        json,
        'captureIntervalFromSourceP95Ms',
      ),
      captureIntervalFromSourceMaxMs: _readOptionalDouble(
        json,
        'captureIntervalFromSourceMaxMs',
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
      mftInputStreamFlags: _readOptionalInt(json, 'mftInputStreamFlags'),
      mftDoesNotAddref: _readOptionalBool(json, 'mftDoesNotAddref'),
      mftHoldsBuffers: _readOptionalBool(json, 'mftHoldsBuffers'),
      mftInputBufferSize: _readOptionalInt(json, 'mftInputBufferSize'),
      mftInputBufferAlignment: _readOptionalInt(
        json,
        'mftInputBufferAlignment',
      ),
      encoderInputSampleId: _readOptionalInt(json, 'encoderInputSampleId'),
      encoderInputBufferId: _readOptionalInt(json, 'encoderInputBufferId'),
      inputSampleCreateCount: _readOptionalInt(json, 'inputSampleCreateCount'),
      inputBufferCreateCount: _readOptionalInt(json, 'inputBufferCreateCount'),
      inputBufferPoolSize: _readOptionalInt(json, 'inputBufferPoolSize'),
      inputBuffersInFlight: _readOptionalInt(json, 'inputBuffersInFlight'),
      inputBufferReuseCount: _readOptionalInt(json, 'inputBufferReuseCount'),
      unsafeInputBufferReuseDetected: _readOptionalInt(
        json,
        'unsafeInputBufferReuseDetected',
      ),
      nv12GuardCorruptionCount: _readOptionalInt(
        json,
        'nv12GuardCorruptionCount',
      ),
      keyFrameCount: _readOptionalInt(json, 'keyFrameCount'),
      framesSinceLastKeyFrame: _readOptionalInt(
        json,
        'framesSinceLastKeyFrame',
      ),
      lastKeyFramePtsUs: _readOptionalInt(json, 'lastKeyFramePtsUs'),
      lastKeyFrameSizeBytes: _readOptionalInt(json, 'lastKeyFrameSizeBytes'),
      lastKeyFrameIntervalFrames: _readOptionalInt(
        json,
        'lastKeyFrameIntervalFrames',
      ),
      lastKeyFrameIntervalMs: _readOptionalInt(json, 'lastKeyFrameIntervalMs'),
      keyframeIntervalFrames: _readOptionalInt(json, 'keyframeIntervalFrames'),
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
      sourceTextureWidth: _readOptionalInt(json, 'sourceTextureWidth'),
      sourceTextureHeight: _readOptionalInt(json, 'sourceTextureHeight'),
      sourceTextureFormat: _readOptionalString(
        json,
        'sourceTextureFormat',
        defaultValue: 'unavailable',
      ),
      sourceRowPitch: _readOptionalInt(json, 'sourceRowPitch'),
      sourceBgraStride: _readOptionalInt(json, 'sourceBgraStride'),
      nv12YOffset: _readOptionalInt(json, 'nv12YOffset'),
      nv12UvOffset: _readOptionalInt(json, 'nv12UvOffset'),
      nv12YStride: _readOptionalInt(json, 'nv12YStride'),
      nv12UvStride: _readOptionalInt(json, 'nv12UvStride'),
      nv12ExpectedBytes: _readOptionalInt(json, 'nv12ExpectedBytes'),
      nv12AllocatedBytes: _readOptionalInt(json, 'nv12AllocatedBytes'),
      nv12UsedBytes: _readOptionalInt(json, 'nv12UsedBytes'),
      encoderInputStride: _readOptionalInt(json, 'encoderInputStride'),
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
      captureBottleneckStage: _readOptionalString(
        json,
        'captureBottleneckStage',
        defaultValue: 'unknown',
      ),
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
      tvAudioSourceDeviceId: _readOptionalString(
        json,
        'tvAudioSourceDeviceId',
        defaultValue: '',
      ),
      tvAudioSourceDeviceName: _readOptionalString(
        json,
        'tvAudioSourceDeviceName',
        defaultValue: '',
      ),
      pcMonitorDeviceId: _readOptionalString(
        json,
        'pcMonitorDeviceId',
        defaultValue: '',
      ),
      pcMonitorDeviceName: _readOptionalString(
        json,
        'pcMonitorDeviceName',
        defaultValue: '',
      ),
      localMonitorActive: _readOptionalBool(json, 'localMonitorActive'),
      localMonitorMuted: _readOptionalBool(json, 'localMonitorMuted'),
      localMonitorQueueDepth: _readOptionalInt(json, 'localMonitorQueueDepth'),
      localMonitorDroppedBuffers: _readOptionalInt(
        json,
        'localMonitorDroppedBuffers',
      ),
      audioCaptureFormat: _readOptionalString(
        json,
        'audioCaptureFormat',
        defaultValue: '',
      ),
      audioMonitorFormat: _readOptionalString(
        json,
        'audioMonitorFormat',
        defaultValue: '',
      ),
      audioRoutingUnsupportedReason: _readOptionalString(
        json,
        'audioRoutingUnsupportedReason',
        defaultValue: '',
      ),
      requestedProfile: _readOptionalString(
        json,
        'requestedProfile',
        defaultValue: 'lowLatency720p30',
      ),
      appliedProfile: _readOptionalString(
        json,
        'appliedProfile',
        defaultValue: 'lowLatency720p30',
      ),
      profileFallbackReason: _readOptionalString(
        json,
        'profileFallbackReason',
        defaultValue: '',
      ),
      outputWidth: _readOptionalInt(json, 'outputWidth', defaultValue: 1280),
      outputHeight: _readOptionalInt(json, 'outputHeight', defaultValue: 720),
      targetBitrateKbps: _readOptionalInt(
        json,
        'targetBitrateKbps',
        defaultValue: 6000,
      ),
      encoderName: _readOptionalString(
        json,
        'encoderName',
        defaultValue: 'unknown',
      ),
      hardwareEncoderActive: _readOptionalBool(json, 'hardwareEncoderActive'),
      encoderSupportsRequestedResolution: _readOptionalBool(
        json,
        'encoderSupportsRequestedResolution',
      ),
      receiverMaxWidth: _readOptionalInt(json, 'receiverMaxWidth'),
      receiverMaxFps: _readOptionalInt(json, 'receiverMaxFps'),
      receiverMaxHeight: _readOptionalInt(json, 'receiverMaxHeight'),
      receiverSupports4k30: _readOptionalBool(json, 'receiverSupports4k30'),
      captureFpsRecent: _readOptionalDouble(json, 'captureFpsRecent'),
      conversionFpsRecent: _readOptionalDouble(json, 'conversionFpsRecent'),
      encoderInputFpsRecent: _readOptionalDouble(json, 'encoderInputFpsRecent'),
      encoderOutputFpsRecent: _readOptionalDouble(
        json,
        'encoderOutputFpsRecent',
      ),
      transportVideoFpsRecent: _readOptionalDouble(
        json,
        'transportVideoFpsRecent',
      ),
      receiverPresentedFpsRecent: _readOptionalDouble(
        json,
        'receiverPresentedFpsRecent',
      ),
      receiverReceivedFpsRecent: _readOptionalDouble(
        json,
        'receiverReceivedFpsRecent',
      ),
      receiverDecoderInputFpsRecent: _readOptionalDouble(
        json,
        'receiverDecoderInputFpsRecent',
      ),
      receiverDecoderOutputFpsRecent: _readOptionalDouble(
        json,
        'receiverDecoderOutputFpsRecent',
      ),
      receiverDecoderOutputReleased: _readOptionalInt(
        json,
        'receiverDecoderOutputReleased',
      ),
      receiverDecoderOutputReleasedImmediate: _readOptionalInt(
        json,
        'receiverDecoderOutputReleasedImmediate',
      ),
      receiverDecoderOutputReleasedScheduled: _readOptionalInt(
        json,
        'receiverDecoderOutputReleasedScheduled',
      ),
      receiverOnFrameRenderedCallbacks: _readOptionalInt(
        json,
        'receiverOnFrameRenderedCallbacks',
      ),
      receiverVideoRenderMode: _readOptionalString(
        json,
        'receiverVideoRenderMode',
        defaultValue: 'unavailable',
      ),
      receiverPtsIntervalP50Ms: _readOptionalDouble(
        json,
        'receiverPtsIntervalP50Ms',
      ),
      encodedAccessUnitBytes: _readOptionalInt(json, 'encodedAccessUnitBytes'),
      transportedAccessUnitBytes: _readOptionalInt(
        json,
        'transportedAccessUnitBytes',
      ),
      videoAuSizeMismatchCount: _readOptionalInt(
        json,
        'videoAuSizeMismatchCount',
      ),
      videoFragmentMissingCount: _readOptionalInt(
        json,
        'videoFragmentMissingCount',
      ),
      videoAuReassemblyErrorCount: _readOptionalInt(
        json,
        'videoAuReassemblyErrorCount',
      ),
      receiverAccessUnitBytes: _readOptionalInt(
        json,
        'receiverAccessUnitBytes',
      ),
      receiverKeyFramesReceived: _readOptionalInt(
        json,
        'receiverKeyFramesReceived',
      ),
      receiverCodecConfigsReceived: _readOptionalInt(
        json,
        'receiverCodecConfigsReceived',
      ),
      receiverDecoderConfiguredWidth: _readOptionalInt(
        json,
        'receiverDecoderConfiguredWidth',
      ),
      receiverDecoderConfiguredHeight: _readOptionalInt(
        json,
        'receiverDecoderConfiguredHeight',
      ),
      receiverDecoderOutputWidth: _readOptionalInt(
        json,
        'receiverDecoderOutputWidth',
      ),
      receiverDecoderOutputHeight: _readOptionalInt(
        json,
        'receiverDecoderOutputHeight',
      ),
      receiverDecoderCropLeft: _readOptionalInt(
        json,
        'receiverDecoderCropLeft',
      ),
      receiverDecoderCropTop: _readOptionalInt(json, 'receiverDecoderCropTop'),
      receiverDecoderCropRight: _readOptionalInt(
        json,
        'receiverDecoderCropRight',
      ),
      receiverDecoderCropBottom: _readOptionalInt(
        json,
        'receiverDecoderCropBottom',
      ),
      receiverDecoderFormatChangeCount: _readOptionalInt(
        json,
        'receiverDecoderFormatChangeCount',
      ),
      receiverSurfaceWidth: _readOptionalInt(json, 'receiverSurfaceWidth'),
      receiverSurfaceHeight: _readOptionalInt(json, 'receiverSurfaceHeight'),
      receiverPtsRegressionCount: _readOptionalInt(
        json,
        'receiverPtsRegressionCount',
      ),
      conversionDurationP95Ms: _readOptionalDouble(
        json,
        'conversionDurationP95Ms',
      ),
      encoderQueueWaitP95Ms: _readOptionalDouble(json, 'encoderQueueWaitP95Ms'),
      transportSendP95Ms: _readOptionalDouble(json, 'transportSendP95Ms'),
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
