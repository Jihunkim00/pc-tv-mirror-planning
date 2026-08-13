import 'package:mirror_protocol/mirror_protocol.dart';

import '../../core/native_bridge/mirror_native_api.dart';

final class DiagnosticsClipboardFormatter {
  const DiagnosticsClipboardFormatter._();

  static String format({
    required NativeSessionSnapshot? snapshot,
    required DisplayInfo? sourceDisplay,
    required String? sessionId,
    String appVersion = 'unavailable',
    String build = 'unavailable',
    String commit = 'unavailable',
  }) {
    final s = snapshot;
    final timestamp = DateTime.now().toUtc().toIso8601String();
    String value(Object? item) {
      if (item == null) return 'unavailable';
      if (item is String && item.trim().isEmpty) return 'unavailable';
      return '$item';
    }

    String rate(double item) =>
        item <= 0 ? 'unavailable' : item.toStringAsFixed(2);
    String metric(double item) =>
        item <= 0 ? 'unavailable' : item.toStringAsFixed(2);

    final selectedSource = sourceDisplay == null
        ? 'unavailable'
        : '${sourceDisplay.width}x${sourceDisplay.height}@'
              '${rate(sourceDisplay.refreshRateHz)} Hz ${sourceDisplay.name}';
    final profile = s == null
        ? 'unavailable'
        : '${value(s.requestedProfile)} -> ${value(s.appliedProfile)}';
    final receiverFps = s == null || s.receiverPresentedFpsRecent <= 0
        ? 'unavailable'
        : rate(s.receiverPresentedFpsRecent);

    return <String>[
      '=== SESSION ===',
      'timestampUtc: $timestamp',
      'sessionId: ${value(sessionId)}',
      'appVersion: $appVersion',
      'build: $build',
      'gitCommit: $commit',
      'state: ${value(s?.state.wireName)}',
      'profileRequestedApplied: $profile',
      'fallbackReason: ${value(s?.profileFallbackReason)}',
      '',
      'SOURCE DISPLAY',
      'selectedDisplay: $selectedSource',
      'nativeDisplay: ${s == null ? 'unavailable' : '${s.sourceDisplayWidth}x${s.sourceDisplayHeight}@${rate(s.sourceDisplayRefreshHz)} Hz'}',
      'deviceName: ${value(s?.sourceDisplayDeviceName)}',
      '',
      'CAPTURE',
      'captureFpsRecent: ${s == null ? 'unavailable' : rate(s.captureFpsRecent)}',
      'captureIntervalFromSourceP50/P95/maxMs: ${s == null ? 'unavailable' : '${metric(s.captureIntervalFromSourceP50Ms)} / ${metric(s.captureIntervalFromSourceP95Ms)} / ${metric(s.captureIntervalFromSourceMaxMs)}'}',
      'captureToEncodeLast/avg/maxMs: ${s == null ? 'unavailable' : '${metric(s.lastCaptureToEncodeMs)} / ${metric(s.averageCaptureToEncodeMs)} / ${metric(s.maxCaptureToEncodeMs)}'}',
      'replacedFrames: ${value(s?.captureReplacedFrames)}',
      'cadenceSkippedFrames: ${value(s?.cadenceSkippedFrames)}',
      '',
      'ENCODER',
      'resolution: ${s == null ? 'unavailable' : '${s.outputWidth}x${s.outputHeight}'}',
      'bitrateKbps: ${value(s?.targetBitrateKbps)}',
      'encoder: ${value(s?.encoderName)}',
      'hardwareActive: ${value(s?.hardwareEncoderActive)}',
      'input/outputFps: ${s == null ? 'unavailable' : '${rate(s.encoderInputFpsRecent)} / ${rate(s.encoderOutputFpsRecent)}'}',
      'encodeDurationAvg/P95Ms: ${s == null ? 'unavailable' : '${metric(s.averageEncodeDurationMs)} / ${metric(s.processOutputDurationP95Ms)}'}',
      'backpressure/notAccepting: ${s == null ? 'unavailable' : '${s.encoderBackpressureCount} / ${s.encoderNotAcceptingCount}'}',
      'sourceTexture: ${s == null ? 'unavailable' : '${s.sourceTextureWidth}x${s.sourceTextureHeight} ${value(s.sourceTextureFormat)}'}',
      'sourceRowPitch/BgraStride: ${s == null ? 'unavailable' : '${s.sourceRowPitch} / ${s.sourceBgraStride}'}',
      'NV12 offsets Y/UV: ${s == null ? 'unavailable' : '${s.nv12YOffset} / ${s.nv12UvOffset}'}',
      'NV12 strides Y/UV: ${s == null ? 'unavailable' : '${s.nv12YStride} / ${s.nv12UvStride}'}',
      'NV12 bytes expected/allocated/used: ${s == null ? 'unavailable' : '${s.nv12ExpectedBytes} / ${s.nv12AllocatedBytes} / ${s.nv12UsedBytes}'}',
      'encoderInputStride: ${value(s?.encoderInputStride)}',
      'MFT flags/doesNotAddRef/holdsBuffers: ${s == null ? 'unavailable' : '${s.mftInputStreamFlags} / ${s.mftDoesNotAddref} / ${s.mftHoldsBuffers}'}',
      'input sample/buffer id: ${s == null ? 'unavailable' : '${s.encoderInputSampleId} / ${s.encoderInputBufferId}'}',
      'input pool/inFlight/reuse/unsafeReuse: ${s == null ? 'unavailable' : '${s.inputBufferPoolSize} / ${s.inputBuffersInFlight} / ${s.inputBufferReuseCount} / ${s.unsafeInputBufferReuseDetected}'}',
      'nv12GuardCorruptionCount: ${value(s?.nv12GuardCorruptionCount)}',
      'keyframes/sinceLast/lastPtsUs/lastBytes: ${s == null ? 'unavailable' : '${s.keyFrameCount} / ${s.framesSinceLastKeyFrame} / ${s.lastKeyFramePtsUs} / ${s.lastKeyFrameSizeBytes}'}',
      'keyframeIntervalFrames/lastIntervalFramesMs: ${s == null ? 'unavailable' : '${s.keyframeIntervalFrames} / ${s.lastKeyFrameIntervalFrames} / ${s.lastKeyFrameIntervalMs}'}',      '',
      'TRANSPORT',
      'sentVideoFps: ${s == null ? 'unavailable' : rate(s.transportVideoFpsRecent)}',
      'sendIntervalP95Ms: ${s == null ? 'unavailable' : metric(s.sendFrameIntervalP95Ms)}',
      'queueCapture/Encoder/Transport: ${s == null ? 'unavailable' : '${s.queueDepthCapture} / ${s.queueDepthEncoder} / ${s.queueDepthTransport}'}',
      'pendingSendBytes: ${value(s?.pendingSendBytes)}',
      'lastSocketError: ${value(s?.lastSocketError)}',
      'encoded/transported AU bytes: ${s == null ? 'unavailable' : '${s.encodedAccessUnitBytes} / ${s.transportedAccessUnitBytes}'}',
      'AU size/fragment/reassembly errors: ${s == null ? 'unavailable' : '${s.videoAuSizeMismatchCount} / ${s.videoFragmentMissingCount} / ${s.videoAuReassemblyErrorCount}'}',
      'receiver AU bytes/config/keyframes: ${s == null ? 'unavailable' : '${s.receiverAccessUnitBytes} / ${s.receiverCodecConfigsReceived} / ${s.receiverKeyFramesReceived}'}',      '',
      'RECEIVER',
      '=== RECEIVER VIDEO PIPELINE ===',
      'maxCapability: ${s == null ? 'unavailable' : '${s.receiverMaxWidth}x${s.receiverMaxHeight}@${s.receiverMaxFps}'}',
      'receiverRenderMode: ${value(s?.receiverVideoRenderMode)}',
      'received/decoderInput/decoderOutputFps: ${s == null ? 'unavailable' : '${rate(s.receiverReceivedFpsRecent)} / ${rate(s.receiverDecoderInputFpsRecent)} / ${rate(s.receiverDecoderOutputFpsRecent)}'}',
      'decoderOutputReleased total/immediate/scheduled: ${s == null ? 'unavailable' : '${s.receiverDecoderOutputReleased} / ${s.receiverDecoderOutputReleasedImmediate} / ${s.receiverDecoderOutputReleasedScheduled}'}',
      'onFrameRenderedCallbackCount: ${value(s?.receiverOnFrameRenderedCallbacks)}',
      'receiverPtsIntervalP50Ms: ${s == null ? 'unavailable' : metric(s.receiverPtsIntervalP50Ms)}',
      'receiverPtsRegressionCount: ${value(s?.receiverPtsRegressionCount)}',
      'receiver decoder configured/output: ${s == null ? 'unavailable' : '${s.receiverDecoderConfiguredWidth}x${s.receiverDecoderConfiguredHeight} / ${s.receiverDecoderOutputWidth}x${s.receiverDecoderOutputHeight}'}',
      'receiver decoder crop L/T/R/B: ${s == null ? 'unavailable' : '${s.receiverDecoderCropLeft}/${s.receiverDecoderCropTop}/${s.receiverDecoderCropRight}/${s.receiverDecoderCropBottom}'}',
      'receiver surface/outputFormatChanges: ${s == null ? 'unavailable' : '${s.receiverSurfaceWidth}x${s.receiverSurfaceHeight} / ${s.receiverDecoderFormatChangeCount}'}',      'codecRenderedFpsRecent: $receiverFps',
      'receiverPresentedFpsRecent: $receiverFps',
      'physicalDisplayMode: unavailable',
      'surfaceRequestedRateFps: unavailable',
      'frameRateModeMatch: unavailable',
      'receiverRenderIntervalsMs: unavailable',
      'receiverJitterAndLongGaps: unavailable',
      '',
      'VIDEO TIMING',
      'ptsSource: ${value(s?.videoPtsSource)}',
      'senderGeneratedPtsUs: ${value(s?.senderGeneratedPtsUs)}',
      'sourceTimestampDeltaUs: ${value(s?.sourceTimestampDeltaUs)}',
      'captureSystemRelativeTimeNs: ${value(s?.captureSystemRelativeTimeNs)}',
      'targetFrameIntervalMs: ${s == null ? 'unavailable' : metric(s.targetFrameIntervalMs)}',
      'staleVideoDroppedFps: ${s == null ? 'unavailable' : rate(s.staleVideoDroppedFps)}',
      '',
      'AUDIO',
      'enabled: ${value(s?.audioEnabled)}',
      'captureState: ${value(s?.audioCaptureState)}',
      'device: ${value(s?.audioDeviceName)}',
      'capture/encoded/sentPackets: ${s == null ? 'unavailable' : '${s.capturedAudioPackets} / ${s.encodedAudioPackets} / ${s.sentAudioPackets}'}',
      'captureFps: ${s == null ? 'unavailable' : rate(s.audioCaptureFps)}',
      'routingMode: ${value(s?.audioRoutingMode)}',
      'tvStreaming: ${value(s?.tvAudioStreaming)}',
      'localMonitor: ${value(s?.localMonitorActive)} muted=${value(s?.localMonitorMuted)}',
      'audioLastError: ${value(s?.audioLastError)}',
      '',
      'PIPELINE',
      'bottleneck: ${value(s?.bottleneckSummary)}',
      'queues capture/encoder/transport: ${s == null ? 'unavailable' : '${s.queueDepthCapture}/${s.queueDepthEncoder}/${s.queueDepthTransport}'}',
      'droppedFrames: ${value(s?.totalDroppedFrames)}',
      'codecConfig/keyFrames: ${s == null ? 'unavailable' : '${s.codecConfigSent} / ${s.keyFramesSent}'}',
      'gpuPath: ${value(s?.bgraToNv12Mode)} readback=${value(s?.gpuReadbackPerFrame)}',
      '',
      'DEBUG',
      'lastEncodeError: ${value(s?.lastEncodeError)}',
      'lastSendError: ${value(s?.lastSendError)}',
      'developerMessage: ${value(s?.developerMessage)}',
      'errorCode: ${value(s?.errorCode?.wireName)}',
      'receiverMetricsSource: VIDEO_STATS codecRenderedFpsRecent forwarded; other receiver-only metrics unavailable',
    ].join('\n');
  }
}
