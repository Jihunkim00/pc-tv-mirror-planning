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
      '=== CAPTURE PIPELINE TIMING ===',
      'FramePool API/buffers: ${s == null ? 'unavailable' : '${value(s.framePoolApi)} / ${s.framePoolBufferCount}'}',
      'FrameArrived enter/exit: ${s == null ? 'unavailable' : '${s.frameArrivedCallbackEnterCount} / ${s.frameArrivedCallbackExitCount}'}',
      'FrameArrived FPS: ${s == null ? 'unavailable' : rate(s.frameArrivedCallbackFps)}',
      'FrameArrived callback avg/p95/maxMs: ${s == null ? 'unavailable' : '${metric(s.frameArrivedCallbackAverageMs)} / ${metric(s.frameArrivedCallbackP95Ms)} / ${metric(s.frameArrivedCallbackMaxMs)}'}',
      'WGC frame-held avg/p95/maxMs: ${s == null ? 'unavailable' : '${metric(s.frameHeldAverageMs)} / ${metric(s.frameHeldP95Ms)} / ${metric(s.frameHeldMaxMs)}'}',
      'Owned texture copy FPS/avg/p95Ms: ${s == null ? 'unavailable' : '${rate(s.ownedTextureCopyFps)} / ${metric(s.ownedTextureCopyAverageMs)} / ${metric(s.ownedTextureCopyP95Ms)}'}',
      'Handoff slots/inUse/queue: ${s == null ? 'unavailable' : '${s.handoffSlots} / ${s.handoffInUse} / ${s.workerQueueDepth}'}',
      'Worker accepted/processed/replaced/dropped: ${s == null ? 'unavailable' : '${s.workerFramesAccepted} / ${s.workerFramesProcessed} / ${s.workerFrameReplacementCount} / ${s.workerFrameDropCount}'}',
      'Worker processing avg/p95Ms/latestAgeMs: ${s == null ? 'unavailable' : '${metric(s.workerProcessingAverageMs)} / ${metric(s.workerProcessingP95Ms)} / ${metric(s.latestFrameAgeMs)}'}',
      'Worker D3D lock wait avg/p95Ms: ${s == null ? 'unavailable' : '${metric(s.workerD3dLockWaitAverageMs)} / ${metric(s.workerD3dLockWaitP95Ms)}'}',
      'Worker CopyResource avg/p95Ms: ${s == null ? 'unavailable' : '${metric(s.workerCopyResourceAverageMs)} / ${metric(s.workerCopyResourceP95Ms)}'}',
      'Worker Map avg/p95Ms: ${s == null ? 'unavailable' : '${metric(s.workerMapAverageMs)} / ${metric(s.workerMapP95Ms)}'}',
      'Worker CPU BGRA copy avg/p95Ms: ${s == null ? 'unavailable' : '${metric(s.workerCpuBgraCopyAverageMs)} / ${metric(s.workerCpuBgraCopyP95Ms)}'}',
      'Worker BGRA->NV12 avg/p95Ms: ${s == null ? 'unavailable' : '${metric(s.workerBgraToNv12AverageMs)} / ${metric(s.workerBgraToNv12P95Ms)}'}',
      'Worker total avg/p95Ms: ${s == null ? 'unavailable' : '${metric(s.workerTotalAverageMs)} / ${metric(s.workerTotalP95Ms)}'}',
      'Capture/conversion threadId: ${s == null ? 'unavailable' : '${s.captureThreadId} / ${s.conversionThreadId}'}',
      'Callback overlap/reentrant: ${s == null ? 'unavailable' : '${s.callbackOverlapCount} / ${s.callbackReentrantCount}'}',
      'D3D multithread protection: ${value(s?.d3dMultithreadProtectionEnabled)}',
      'Measured delivery bottleneck: ${value(s?.measuredDeliveryBottleneck)}',
      'TryGetNextFrame FPS: ${s == null ? 'unavailable' : rate(s.tryGetNextFrameSuccessFps)}',
      'TryGetNextFrame nulls: ${value(s?.tryGetNextFrameNullCount)}',
      'Raw WGC p50/p95: ${s == null ? 'unavailable' : '${metric(s.rawWgcIntervalP50Ms)} / ${metric(s.rawWgcIntervalP95Ms)}'}',
      'Acquire avg/p95: ${s == null ? 'unavailable' : '${metric(s.frameAcquireAverageMs)} / ${metric(s.frameAcquireP95Ms)}'}',
      'CopyResource avg/p95: ${s == null ? 'unavailable' : '${metric(s.copyResourceAverageMs)} / ${metric(s.copyResourceP95Ms)}'}',
      'Map/readback avg/p95: ${s == null ? 'unavailable' : '${metric(s.mapReadbackAverageMs)} / ${metric(s.mapReadbackP95Ms)}'}',
      'Scale avg/p95: ${s == null ? 'unavailable' : '${metric(s.scaleAverageMs)} / ${metric(s.scaleP95Ms)}'}',
      'BGRA->NV12 avg/p95: ${s == null ? 'unavailable' : '${metric(s.bgraToNv12AverageMs)} / ${metric(s.bgraToNv12P95Ms)}'}',
      'NV12 copy avg/p95: ${s == null ? 'unavailable' : '${metric(s.nv12CopyAverageMs)} / ${metric(s.nv12CopyP95Ms)}'}',
      'Sample prepare avg/p95: ${s == null ? 'unavailable' : '${metric(s.samplePrepareAverageMs)} / ${metric(s.samplePrepareP95Ms)}'}',
      'ProcessInput avg/p95: ${s == null ? 'unavailable' : '${metric(s.processInputAverageMs)} / ${metric(s.processInputP95Ms)}'}',
      'Total capture->encoder-ready avg/p95: ${s == null ? 'unavailable' : '${metric(s.captureToEncoderReadyAverageMs)} / ${metric(s.captureToEncoderReadyP95Ms)}'}',
      'Cadence target: ${s == null ? 'unavailable' : rate(s.targetFps)}',
      'Cadence accepted FPS: ${s == null ? 'unavailable' : rate(s.admittedFrameFps)}',
      'Cadence skipped total: ${value(s?.cadenceSkippedFrames)}',
      'Cadence skipped recent: ${value(s?.cadenceSkippedRecent)}',
      'Cadence skip reason: ${value(s?.cadenceSkipReason)}',
      'Measured bottleneck stage: ${value(s?.captureBottleneckStage)}',
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
      'keyframeIntervalFrames/lastIntervalFramesMs: ${s == null ? 'unavailable' : '${s.keyframeIntervalFrames} / ${s.lastKeyFrameIntervalFrames} / ${s.lastKeyFrameIntervalMs}'}',
      '',
      'TRANSPORT',
      'sentVideoFps: ${s == null ? 'unavailable' : rate(s.transportVideoFpsRecent)}',
      'sendIntervalP95Ms: ${s == null ? 'unavailable' : metric(s.sendFrameIntervalP95Ms)}',
      'queueCapture/Encoder/Transport: ${s == null ? 'unavailable' : '${s.queueDepthCapture} / ${s.queueDepthEncoder} / ${s.queueDepthTransport}'}',
      'pendingSendBytes: ${value(s?.pendingSendBytes)}',
      'lastSocketError: ${value(s?.lastSocketError)}',
      'encoded/transported AU bytes: ${s == null ? 'unavailable' : '${s.encodedAccessUnitBytes} / ${s.transportedAccessUnitBytes}'}',
      'AU size/fragment/reassembly errors: ${s == null ? 'unavailable' : '${s.videoAuSizeMismatchCount} / ${s.videoFragmentMissingCount} / ${s.videoAuReassemblyErrorCount}'}',
      'receiver AU bytes/config/keyframes: ${s == null ? 'unavailable' : '${s.receiverAccessUnitBytes} / ${s.receiverCodecConfigsReceived} / ${s.receiverKeyFramesReceived}'}',
      '',
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
      'receiver surface/outputFormatChanges: ${s == null ? 'unavailable' : '${s.receiverSurfaceWidth}x${s.receiverSurfaceHeight} / ${s.receiverDecoderFormatChangeCount}'}',
      'codecRenderedFpsRecent: $receiverFps',
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
