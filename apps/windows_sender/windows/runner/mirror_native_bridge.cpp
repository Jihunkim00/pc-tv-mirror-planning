#include "mirror_native_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>

#include "native/display/display_enumerator.h"
#include "native/audio/audio_device_enumerator.h"
#include "native/session/mirror_session.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableList;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

constexpr char kChannelName[] = "pc_tv_mirror/windows_sender";

std::string ReadString(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return {};
  }
  const auto* value = std::get_if<std::string>(&it->second);
  return value == nullptr ? std::string() : *value;
}

int ReadInt(const EncodableMap& map, const char* key, int fallback) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

bool ReadBool(const EncodableMap& map, const char* key, bool fallback) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  const auto* value = std::get_if<bool>(&it->second);
  return value == nullptr ? fallback : *value;
}

EncodableValue ToEncodable(const pctv::NativeSnapshot& snapshot) {
  EncodableMap map;
  map[EncodableValue("workerD3dLockWaitAverageMs")] =
      EncodableValue(snapshot.worker_d3d_lock_wait_average_ms);
  map[EncodableValue("workerD3dLockWaitP95Ms")] =
      EncodableValue(snapshot.worker_d3d_lock_wait_p95_ms);
  map[EncodableValue("workerCopyResourceAverageMs")] =
      EncodableValue(snapshot.worker_copy_resource_average_ms);
  map[EncodableValue("workerCopyResourceP95Ms")] =
      EncodableValue(snapshot.worker_copy_resource_p95_ms);
  map[EncodableValue("workerMapAverageMs")] =
      EncodableValue(snapshot.worker_map_average_ms);
  map[EncodableValue("workerMapP95Ms")] =
      EncodableValue(snapshot.worker_map_p95_ms);
  map[EncodableValue("workerCpuBgraCopyAverageMs")] =
      EncodableValue(snapshot.worker_cpu_bgra_copy_average_ms);
  map[EncodableValue("workerCpuBgraCopyP95Ms")] =
      EncodableValue(snapshot.worker_cpu_bgra_copy_p95_ms);
  map[EncodableValue("workerBgraToNv12AverageMs")] =
      EncodableValue(snapshot.worker_bgra_to_nv12_average_ms);
  map[EncodableValue("workerBgraToNv12P95Ms")] =
      EncodableValue(snapshot.worker_bgra_to_nv12_p95_ms);
  map[EncodableValue("workerTotalAverageMs")] =
      EncodableValue(snapshot.worker_total_average_ms);
  map[EncodableValue("workerTotalP95Ms")] =
      EncodableValue(snapshot.worker_total_p95_ms);
  map[EncodableValue("state")] = EncodableValue(snapshot.state);
  map[EncodableValue("userMessage")] = EncodableValue(snapshot.user_message);
  map[EncodableValue("captureReady")] = EncodableValue(snapshot.capture_ready);
  map[EncodableValue("encoderReady")] = EncodableValue(snapshot.encoder_ready);
  map[EncodableValue("signalingReady")] =
      EncodableValue(snapshot.signaling_ready);
  map[EncodableValue("nativeVideoPathReady")] =
      EncodableValue(snapshot.native_video_path_ready);
  map[EncodableValue("targetFps")] = EncodableValue(snapshot.target_fps);
  map[EncodableValue("framePoolApi")] =
      EncodableValue(snapshot.frame_pool_api);
  map[EncodableValue("framePoolBufferCount")] =
      EncodableValue(snapshot.frame_pool_buffer_count);
  map[EncodableValue("frameArrivedCallbackEnterCount")] =
      EncodableValue(static_cast<int64_t>(
          snapshot.frame_arrived_callback_enter_count));
  map[EncodableValue("frameArrivedCallbackExitCount")] =
      EncodableValue(static_cast<int64_t>(
          snapshot.frame_arrived_callback_exit_count));
  map[EncodableValue("frameArrivedCallbackAverageMs")] =
      EncodableValue(snapshot.frame_arrived_callback_average_ms);
  map[EncodableValue("frameArrivedCallbackP95Ms")] =
      EncodableValue(snapshot.frame_arrived_callback_p95_ms);
  map[EncodableValue("frameArrivedCallbackMaxMs")] =
      EncodableValue(snapshot.frame_arrived_callback_max_ms);
  map[EncodableValue("frameHeldAverageMs")] =
      EncodableValue(snapshot.frame_held_average_ms);
  map[EncodableValue("frameHeldP95Ms")] =
      EncodableValue(snapshot.frame_held_p95_ms);
  map[EncodableValue("frameHeldMaxMs")] =
      EncodableValue(snapshot.frame_held_max_ms);
  map[EncodableValue("ownedTextureCopyFps")] =
      EncodableValue(snapshot.owned_texture_copy_fps);
  map[EncodableValue("ownedTextureCopyAverageMs")] =
      EncodableValue(snapshot.owned_texture_copy_average_ms);
  map[EncodableValue("ownedTextureCopyP95Ms")] =
      EncodableValue(snapshot.owned_texture_copy_p95_ms);
  map[EncodableValue("workerProcessingAverageMs")] =
      EncodableValue(snapshot.worker_processing_average_ms);
  map[EncodableValue("workerProcessingP95Ms")] =
      EncodableValue(snapshot.worker_processing_p95_ms);
  map[EncodableValue("handoffSlots")] =
      EncodableValue(snapshot.handoff_slots);
  map[EncodableValue("handoffInUse")] =
      EncodableValue(snapshot.handoff_in_use);
  map[EncodableValue("workerQueueDepth")] =
      EncodableValue(snapshot.worker_queue_depth);
  map[EncodableValue("workerFramesAccepted")] =
      EncodableValue(static_cast<int64_t>(snapshot.worker_frames_accepted));
  map[EncodableValue("workerFramesProcessed")] =
      EncodableValue(static_cast<int64_t>(snapshot.worker_frames_processed));
  map[EncodableValue("workerFrameReplacementCount")] =
      EncodableValue(static_cast<int64_t>(
          snapshot.worker_frame_replacement_count));
  map[EncodableValue("workerFrameDropCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.worker_frame_drop_count));
  map[EncodableValue("latestFrameAgeMs")] =
      EncodableValue(snapshot.latest_frame_age_ms);
  map[EncodableValue("captureThreadId")] =
      EncodableValue(static_cast<int64_t>(snapshot.capture_thread_id));
  map[EncodableValue("conversionThreadId")] =
      EncodableValue(static_cast<int64_t>(snapshot.conversion_thread_id));
  map[EncodableValue("callbackOverlapCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.callback_overlap_count));
  map[EncodableValue("callbackReentrantCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.callback_reentrant_count));
  map[EncodableValue("d3dMultithreadProtectionEnabled")] =
      EncodableValue(snapshot.d3d_multithread_protection_enabled);
  map[EncodableValue("measuredDeliveryBottleneck")] =
      EncodableValue(snapshot.measured_delivery_bottleneck);
  map[EncodableValue("captureCallbackFps")] =
      EncodableValue(snapshot.capture_callback_fps);
  map[EncodableValue("capturedFps")] = EncodableValue(snapshot.captured_fps);
  map[EncodableValue("targetAdmissionFps")] =
      EncodableValue(snapshot.target_admission_fps);
  map[EncodableValue("admittedFrameFps")] =
      EncodableValue(snapshot.admitted_frame_fps);
  map[EncodableValue("convertedFps")] = EncodableValue(snapshot.converted_fps);
  map[EncodableValue("encoderAcceptedFps")] =
      EncodableValue(snapshot.encoder_accepted_fps);
  map[EncodableValue("encoderInputFps")] =
      EncodableValue(snapshot.encoder_input_fps);
  map[EncodableValue("encodedFps")] = EncodableValue(snapshot.encoded_fps);
  map[EncodableValue("sentVideoFps")] =
      EncodableValue(snapshot.sent_video_fps);
  map[EncodableValue("sentAccessUnitFps")] =
      EncodableValue(snapshot.sent_access_unit_fps);
  map[EncodableValue("cadenceDroppedFps")] =
      EncodableValue(snapshot.cadence_dropped_fps);
  map[EncodableValue("encoderBusyDroppedFps")] =
      EncodableValue(snapshot.encoder_busy_dropped_fps);
  map[EncodableValue("conversionBusyDroppedFps")] =
      EncodableValue(snapshot.conversion_busy_dropped_fps);
  map[EncodableValue("captureFrameIntervalAverageMs")] =
      EncodableValue(snapshot.capture_frame_interval_average_ms);
  map[EncodableValue("captureFrameIntervalP95Ms")] =
      EncodableValue(snapshot.capture_frame_interval_p95_ms);
  map[EncodableValue("encodeFrameIntervalAverageMs")] =
      EncodableValue(snapshot.encode_frame_interval_average_ms);
  map[EncodableValue("sendFrameIntervalAverageMs")] =
      EncodableValue(snapshot.send_frame_interval_average_ms);
  map[EncodableValue("sendFrameIntervalP95Ms")] =
      EncodableValue(snapshot.send_frame_interval_p95_ms);
  map[EncodableValue("captureToConvertAverageMs")] =
      EncodableValue(snapshot.capture_to_convert_average_ms);
  map[EncodableValue("convertToEncodeAverageMs")] =
      EncodableValue(snapshot.convert_to_encode_average_ms);
  map[EncodableValue("encodeDurationAverageMs")] =
      EncodableValue(snapshot.encode_duration_average_ms);
  map[EncodableValue("encodeDurationP95Ms")] =
      EncodableValue(snapshot.encode_duration_p95_ms);
  map[EncodableValue("frameArrivedCallbackFps")] =
      EncodableValue(snapshot.frame_arrived_callback_fps);
  map[EncodableValue("tryGetNextFrameSuccessFps")] =
      EncodableValue(snapshot.try_get_next_frame_success_fps);
  map[EncodableValue("tryGetNextFrameNullCount")] =
      EncodableValue(static_cast<int64_t>(
          snapshot.try_get_next_frame_null_count));
  map[EncodableValue("rawWgcIntervalP50Ms")] =
      EncodableValue(snapshot.raw_wgc_interval_p50_ms);
  map[EncodableValue("rawWgcIntervalP95Ms")] =
      EncodableValue(snapshot.raw_wgc_interval_p95_ms);
  map[EncodableValue("frameAcquireAverageMs")] =
      EncodableValue(snapshot.frame_acquire_average_ms);
  map[EncodableValue("frameAcquireP95Ms")] =
      EncodableValue(snapshot.frame_acquire_p95_ms);
  map[EncodableValue("copyResourceAverageMs")] =
      EncodableValue(snapshot.copy_resource_average_ms);
  map[EncodableValue("copyResourceP95Ms")] =
      EncodableValue(snapshot.copy_resource_p95_ms);
  map[EncodableValue("mapReadbackAverageMs")] =
      EncodableValue(snapshot.map_readback_average_ms);
  map[EncodableValue("mapReadbackP95Ms")] =
      EncodableValue(snapshot.map_readback_p95_ms);
  map[EncodableValue("scaleAverageMs")] =
      EncodableValue(snapshot.scale_average_ms);
  map[EncodableValue("scaleP95Ms")] =
      EncodableValue(snapshot.scale_p95_ms);
  map[EncodableValue("bgraToNv12AverageMs")] =
      EncodableValue(snapshot.bgra_to_nv12_average_ms);
  map[EncodableValue("bgraToNv12P95Ms")] =
      EncodableValue(snapshot.bgra_to_nv12_p95_ms);
  map[EncodableValue("nv12CopyAverageMs")] =
      EncodableValue(snapshot.nv12_copy_average_ms);
  map[EncodableValue("nv12CopyP95Ms")] =
      EncodableValue(snapshot.nv12_copy_p95_ms);
  map[EncodableValue("samplePrepareAverageMs")] =
      EncodableValue(snapshot.sample_prepare_average_ms);
  map[EncodableValue("samplePrepareP95Ms")] =
      EncodableValue(snapshot.sample_prepare_p95_ms);
  map[EncodableValue("captureToEncoderReadyAverageMs")] =
      EncodableValue(snapshot.capture_to_encoder_ready_average_ms);
  map[EncodableValue("captureToEncoderReadyP95Ms")] =
      EncodableValue(snapshot.capture_to_encoder_ready_p95_ms);
  map[EncodableValue("processInputAverageMs")] =
      EncodableValue(snapshot.process_input_average_ms);
  map[EncodableValue("processInputP95Ms")] =
      EncodableValue(snapshot.process_input_p95_ms);
  map[EncodableValue("encodeToSendAverageMs")] =
      EncodableValue(snapshot.encode_to_send_average_ms);
  map[EncodableValue("videoQueueWaitAverageMs")] =
      EncodableValue(snapshot.video_queue_wait_average_ms);
  map[EncodableValue("videoQueueWaitP95Ms")] =
      EncodableValue(snapshot.video_queue_wait_p95_ms);
  map[EncodableValue("capturedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.captured_frames));
  map[EncodableValue("captureReplacedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.capture_replaced_frames));
  map[EncodableValue("cadenceSkippedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.cadence_skipped_frames));
  map[EncodableValue("cadenceSkippedRecent")] =
      EncodableValue(snapshot.cadence_skipped_recent);
  map[EncodableValue("cadenceSkipReason")] =
      EncodableValue(snapshot.cadence_skip_reason);
  map[EncodableValue("conversionBackpressureDroppedFrames")] =
      EncodableValue(static_cast<int64_t>(
          snapshot.conversion_backpressure_dropped_frames));
  map[EncodableValue("encoderBackpressureDroppedFrames")] =
      EncodableValue(
          static_cast<int64_t>(snapshot.encoder_backpressure_dropped_frames));
  map[EncodableValue("transportBackpressureDroppedFrames")] =
      EncodableValue(
          static_cast<int64_t>(snapshot.transport_backpressure_dropped_frames));
  map[EncodableValue("staleVideoDroppedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.stale_video_dropped_frames));
  map[EncodableValue("shutdownDroppedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.shutdown_dropped_frames));
  map[EncodableValue("totalDroppedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.total_dropped_frames));
  map[EncodableValue("captureDroppedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.capture_dropped_frames));
  map[EncodableValue("conversionDroppedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.conversion_dropped_frames));
  map[EncodableValue("encoderInputDroppedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.encoder_input_dropped_frames));
  map[EncodableValue("encodedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.encoded_frames));
  map[EncodableValue("transportDroppedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.transport_dropped_frames));
  map[EncodableValue("duplicatedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.duplicated_frames));
  map[EncodableValue("lastProcessedFrameSequence")] =
      EncodableValue(static_cast<int64_t>(snapshot.last_processed_frame_sequence));
  map[EncodableValue("codecConfigSent")] =
      EncodableValue(static_cast<int64_t>(snapshot.codec_config_sent));
  map[EncodableValue("keyFramesSent")] =
      EncodableValue(static_cast<int64_t>(snapshot.key_frames_sent));
  map[EncodableValue("packetsSent")] =
      EncodableValue(static_cast<int64_t>(snapshot.packets_sent));
  map[EncodableValue("bytesSent")] =
      EncodableValue(static_cast<int64_t>(snapshot.bytes_sent));
  map[EncodableValue("sendCompletedBytes")] =
      EncodableValue(static_cast<int64_t>(snapshot.send_completed_bytes));
  map[EncodableValue("socketSendCallsPerSecond")] =
      EncodableValue(snapshot.socket_send_calls_per_second);
  map[EncodableValue("averagePacketSendDurationMs")] =
      EncodableValue(snapshot.average_packet_send_duration_ms);
  map[EncodableValue("accessUnitSendDurationAverageMs")] =
      EncodableValue(snapshot.access_unit_send_duration_average_ms);
  map[EncodableValue("accessUnitSendDurationP95Ms")] =
      EncodableValue(snapshot.access_unit_send_duration_p95_ms);
  map[EncodableValue("pendingSendBytes")] =
      EncodableValue(static_cast<int64_t>(snapshot.pending_send_bytes));
  if (!snapshot.last_socket_error.empty()) {
    map[EncodableValue("lastSocketError")] =
        EncodableValue(snapshot.last_socket_error);
  }
  map[EncodableValue("queueDepthCapture")] =
      EncodableValue(snapshot.queue_depth_capture);
  map[EncodableValue("queueDepthEncoder")] =
      EncodableValue(snapshot.queue_depth_encoder);
  map[EncodableValue("queueDepthTransport")] =
      EncodableValue(snapshot.queue_depth_transport);
  map[EncodableValue("lastCaptureToEncodeMs")] =
      EncodableValue(snapshot.last_capture_to_encode_ms);
  map[EncodableValue("averageCaptureToEncodeMs")] =
      EncodableValue(snapshot.average_capture_to_encode_ms);
  map[EncodableValue("maxCaptureToEncodeMs")] =
      EncodableValue(snapshot.max_capture_to_encode_ms);
  map[EncodableValue("admittedToEncodedRatio")] =
      EncodableValue(snapshot.admitted_to_encoded_ratio);
  map[EncodableValue("selectedProfile")] =
      EncodableValue(snapshot.selected_profile);
  map[EncodableValue("outputResolution")] =
      EncodableValue(snapshot.output_resolution);
  map[EncodableValue("currentBitrateKbps")] =
      EncodableValue(snapshot.current_bitrate_kbps);
  map[EncodableValue("targetFrameIntervalMs")] =
      EncodableValue(snapshot.target_frame_interval_ms);
  map[EncodableValue("staleVideoDroppedFps")] =
      EncodableValue(snapshot.stale_video_dropped_fps);
  map[EncodableValue("sourceDisplayWidth")] =
      EncodableValue(snapshot.source_display_width);
  map[EncodableValue("sourceDisplayHeight")] =
      EncodableValue(snapshot.source_display_height);
  map[EncodableValue("sourceDisplayRefreshHz")] =
      EncodableValue(snapshot.source_display_refresh_hz);
  map[EncodableValue("sourceDisplayDeviceName")] =
      EncodableValue(snapshot.source_display_device_name);
  map[EncodableValue("captureSystemRelativeTimeNs")] =
      EncodableValue(static_cast<int64_t>(snapshot.capture_system_relative_time_ns));
  map[EncodableValue("senderGeneratedPtsUs")] =
      EncodableValue(static_cast<int64_t>(snapshot.sender_generated_pts_us));
  map[EncodableValue("sourceTimestampDeltaUs")] =
      EncodableValue(static_cast<int64_t>(snapshot.source_timestamp_delta_us));
  map[EncodableValue("videoPtsSource")] = EncodableValue(snapshot.video_pts_source);
  map[EncodableValue("captureIntervalFromSourceP50Ms")] =
      EncodableValue(snapshot.capture_interval_from_source_p50_ms);
  map[EncodableValue("captureIntervalFromSourceP95Ms")] = EncodableValue(snapshot.capture_interval_from_source_p95_ms);
  map[EncodableValue("captureIntervalFromSourceMaxMs")] =
      EncodableValue(snapshot.capture_interval_from_source_max_ms);
  map[EncodableValue("receiverMaxFps")] =
      EncodableValue(snapshot.receiver_max_fps);
  map[EncodableValue("selectedEncoderName")] =
      EncodableValue(snapshot.selected_encoder_name);
  map[EncodableValue("selectedEncoderHardware")] =
      EncodableValue(snapshot.selected_encoder_hardware);
  map[EncodableValue("selectedEncoderAsync")] =
      EncodableValue(snapshot.selected_encoder_async);
  map[EncodableValue("encoderD3D11Aware")] =
      EncodableValue(snapshot.encoder_d3d11_aware);
  map[EncodableValue("encoderInputFormat")] =
      EncodableValue(snapshot.encoder_input_format);
  map[EncodableValue("encoderOutputFormat")] =
      EncodableValue(snapshot.encoder_output_format);
  map[EncodableValue("averageEncodeDurationMs")] =
      EncodableValue(snapshot.average_encode_duration_ms);
  map[EncodableValue("encoderBackpressureCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.encoder_backpressure_count));
  map[EncodableValue("encoderNotAcceptingCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.encoder_not_accepting_count));
  map[EncodableValue("processInputCalls")] =
      EncodableValue(static_cast<int64_t>(snapshot.process_input_calls));
  map[EncodableValue("processInputAccepted")] =
      EncodableValue(static_cast<int64_t>(snapshot.process_input_accepted));
  map[EncodableValue("processInputNotAccepting")] =
      EncodableValue(
          static_cast<int64_t>(snapshot.process_input_not_accepting));
  map[EncodableValue("processInputRetries")] =
      EncodableValue(static_cast<int64_t>(snapshot.process_input_retries));
  map[EncodableValue("processOutputCalls")] =
      EncodableValue(static_cast<int64_t>(snapshot.process_output_calls));
  map[EncodableValue("processOutputFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.process_output_frames));
  map[EncodableValue("mftInputStreamFlags")] =
      EncodableValue(static_cast<int64_t>(snapshot.mft_input_stream_flags));
  map[EncodableValue("mftDoesNotAddref")] =
      EncodableValue(snapshot.mft_does_not_addref);
  map[EncodableValue("mftHoldsBuffers")] =
      EncodableValue(snapshot.mft_holds_buffers);
  map[EncodableValue("mftInputBufferSize")] =
      EncodableValue(static_cast<int64_t>(snapshot.mft_input_buffer_size));
  map[EncodableValue("mftInputBufferAlignment")] =
      EncodableValue(static_cast<int64_t>(snapshot.mft_input_buffer_alignment));
  map[EncodableValue("encoderInputSampleId")] =
      EncodableValue(static_cast<int64_t>(snapshot.encoder_input_sample_id));
  map[EncodableValue("encoderInputBufferId")] =
      EncodableValue(static_cast<int64_t>(snapshot.encoder_input_buffer_id));
  map[EncodableValue("inputSampleCreateCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.input_sample_create_count));
  map[EncodableValue("inputBufferCreateCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.input_buffer_create_count));
  map[EncodableValue("inputBufferPoolSize")] =
      EncodableValue(snapshot.input_buffer_pool_size);
  map[EncodableValue("inputBuffersInFlight")] =
      EncodableValue(snapshot.input_buffers_in_flight);
  map[EncodableValue("inputBufferReuseCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.input_buffer_reuse_count));
  map[EncodableValue("unsafeInputBufferReuseDetected")] =
      EncodableValue(static_cast<int64_t>(snapshot.unsafe_input_buffer_reuse_detected));
  map[EncodableValue("nv12GuardCorruptionCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.nv12_guard_corruption_count));
  map[EncodableValue("keyFrameCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.key_frame_count));
  map[EncodableValue("framesSinceLastKeyFrame")] =
      EncodableValue(static_cast<int64_t>(snapshot.frames_since_last_key_frame));
  map[EncodableValue("lastKeyFramePtsUs")] =
      EncodableValue(static_cast<int64_t>(snapshot.last_key_frame_pts_us));
  map[EncodableValue("lastKeyFrameSizeBytes")] =
      EncodableValue(static_cast<int64_t>(snapshot.last_key_frame_size_bytes));
  map[EncodableValue("lastKeyFrameIntervalFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.last_key_frame_interval_frames));
  map[EncodableValue("lastKeyFrameIntervalMs")] =
      EncodableValue(static_cast<int64_t>(snapshot.last_key_frame_interval_ms));
  map[EncodableValue("keyframeIntervalFrames")] =
      EncodableValue(snapshot.keyframe_interval_frames);
  map[EncodableValue("processInputDurationAverageMs")] =
      EncodableValue(snapshot.process_input_duration_average_ms);
  map[EncodableValue("processInputDurationP95Ms")] =
      EncodableValue(snapshot.process_input_duration_p95_ms);
  map[EncodableValue("processOutputDurationAverageMs")] =
      EncodableValue(snapshot.process_output_duration_average_ms);
  map[EncodableValue("processOutputDurationP95Ms")] =
      EncodableValue(snapshot.process_output_duration_p95_ms);
  map[EncodableValue("sourceTextureWidth")] =
      EncodableValue(static_cast<int64_t>(snapshot.source_texture_width));
  map[EncodableValue("sourceTextureHeight")] =
      EncodableValue(static_cast<int64_t>(snapshot.source_texture_height));
  map[EncodableValue("sourceTextureFormat")] =
      EncodableValue(snapshot.source_texture_format);
  map[EncodableValue("sourceRowPitch")] =
      EncodableValue(static_cast<int64_t>(snapshot.source_row_pitch));
  map[EncodableValue("sourceBgraStride")] =
      EncodableValue(static_cast<int64_t>(snapshot.source_bgra_stride));
  map[EncodableValue("nv12YOffset")] = EncodableValue(static_cast<int64_t>(snapshot.nv12_y_offset));
  map[EncodableValue("nv12UvOffset")] = EncodableValue(static_cast<int64_t>(snapshot.nv12_uv_offset));
  map[EncodableValue("nv12YStride")] = EncodableValue(static_cast<int64_t>(snapshot.nv12_y_stride));
  map[EncodableValue("nv12UvStride")] = EncodableValue(static_cast<int64_t>(snapshot.nv12_uv_stride));
  map[EncodableValue("nv12ExpectedBytes")] =
      EncodableValue(static_cast<int64_t>(snapshot.nv12_expected_bytes));
  map[EncodableValue("nv12AllocatedBytes")] =
      EncodableValue(static_cast<int64_t>(snapshot.nv12_allocated_bytes));
  map[EncodableValue("nv12UsedBytes")] = EncodableValue(static_cast<int64_t>(snapshot.nv12_used_bytes));
  map[EncodableValue("encoderInputStride")] =
      EncodableValue(static_cast<int64_t>(snapshot.encoder_input_stride));
  map[EncodableValue("bgraToNv12Mode")] =
      EncodableValue(snapshot.bgra_to_nv12_mode);
  map[EncodableValue("gpuReadbackPerFrame")] =
      EncodableValue(snapshot.gpu_readback_per_frame);
  map[EncodableValue("textureReuseEnabled")] =
      EncodableValue(snapshot.texture_reuse_enabled);
  map[EncodableValue("lowLatencyOptionsApplied")] =
      EncodableValue(snapshot.low_latency_options_applied);
  map[EncodableValue("unsupportedEncoderOptions")] =
      EncodableValue(snapshot.unsupported_encoder_options);
  map[EncodableValue("bottleneckSummary")] =
      EncodableValue(snapshot.bottleneck_summary);
  map[EncodableValue("captureBottleneckStage")] =
      EncodableValue(snapshot.capture_bottleneck_stage_name);
  if (!snapshot.last_encode_error.empty()) {
    map[EncodableValue("lastEncodeError")] =
        EncodableValue(snapshot.last_encode_error);
  }
  if (!snapshot.last_send_error.empty()) {
    map[EncodableValue("lastSendError")] =
        EncodableValue(snapshot.last_send_error);
  }
  map[EncodableValue("audioEnabled")] = EncodableValue(snapshot.audio_enabled);
  map[EncodableValue("audioCaptureState")] =
      EncodableValue(snapshot.audio_capture_state);
  map[EncodableValue("audioDeviceName")] =
      EncodableValue(snapshot.audio_device_name);
  map[EncodableValue("audioInputSampleRate")] =
      EncodableValue(snapshot.audio_input_sample_rate);
  map[EncodableValue("audioInputChannels")] =
      EncodableValue(snapshot.audio_input_channels);
  map[EncodableValue("audioEncodedSampleRate")] =
      EncodableValue(snapshot.audio_encoded_sample_rate);
  map[EncodableValue("audioEncodedChannels")] =
      EncodableValue(snapshot.audio_encoded_channels);
  map[EncodableValue("capturedAudioPackets")] =
      EncodableValue(static_cast<int64_t>(snapshot.captured_audio_packets));
  map[EncodableValue("encodedAudioPackets")] =
      EncodableValue(static_cast<int64_t>(snapshot.encoded_audio_packets));
  map[EncodableValue("sentAudioPackets")] =
      EncodableValue(static_cast<int64_t>(snapshot.sent_audio_packets));
  map[EncodableValue("audioCaptureFps")] =
      EncodableValue(snapshot.audio_capture_fps);
  map[EncodableValue("audioEncodeAverageMs")] =
      EncodableValue(snapshot.audio_encode_average_ms);
  map[EncodableValue("audioQueueDepth")] =
      EncodableValue(snapshot.audio_queue_depth);
  map[EncodableValue("audioDroppedPackets")] =
      EncodableValue(static_cast<int64_t>(snapshot.audio_dropped_packets));
  map[EncodableValue("audioLastError")] =
      EncodableValue(snapshot.audio_last_error);
  map[EncodableValue("videoFpsAudioDisabled")] =
      EncodableValue(snapshot.video_fps_audio_disabled);
  map[EncodableValue("videoFpsAudioEnabled")] =
      EncodableValue(snapshot.video_fps_audio_enabled);
  map[EncodableValue("audioCpuTimeMs")] =
      EncodableValue(snapshot.audio_cpu_time_ms);
  map[EncodableValue("packetWriterVideoWaitMs")] =
      EncodableValue(snapshot.packet_writer_video_wait_ms);
  map[EncodableValue("packetWriterAudioWaitMs")] =
      EncodableValue(snapshot.packet_writer_audio_wait_ms);
  map[EncodableValue("playbackState")] =
      EncodableValue(snapshot.playback_state);
  map[EncodableValue("pauseRequestsReceived")] =
      EncodableValue(static_cast<int64_t>(snapshot.pause_requests_received));
  map[EncodableValue("resumeRequestsReceived")] =
      EncodableValue(static_cast<int64_t>(snapshot.resume_requests_received));
  map[EncodableValue("playbackCommandAcksSent")] =
      EncodableValue(static_cast<int64_t>(snapshot.playback_command_acks_sent));
  map[EncodableValue("playbackCommandErrorsSent")] =
      EncodableValue(
          static_cast<int64_t>(snapshot.playback_command_errors_sent));
  map[EncodableValue("resumeCodecConfigResends")] =
      EncodableValue(static_cast<int64_t>(snapshot.resume_codec_config_resends));
  map[EncodableValue("localSpeakerMuteMode")] =
      EncodableValue(snapshot.local_speaker_mute_mode);
  map[EncodableValue("localSpeakerMuteState")] =
      EncodableValue(snapshot.local_speaker_mute_state);
  map[EncodableValue("localSpeakerMuteLastError")] =
      EncodableValue(snapshot.local_speaker_mute_last_error);
  map[EncodableValue("pcLocalAudioMuteRequested")] =
      EncodableValue(snapshot.pc_local_audio_mute_requested);
  map[EncodableValue("pcLocalAudioMuteSupported")] =
      EncodableValue(snapshot.pc_local_audio_mute_supported);
  map[EncodableValue("pcLocalAudioMuteApplied")] =
      EncodableValue(snapshot.pc_local_audio_mute_applied);
  map[EncodableValue("pcLocalAudioOriginalMuteState")] =
      EncodableValue(snapshot.pc_local_audio_original_mute_state);
  map[EncodableValue("tvAudioStreaming")] =
      EncodableValue(snapshot.tv_audio_streaming);
  map[EncodableValue("audioCaptureActive")] =
      EncodableValue(snapshot.audio_capture_active);
  map[EncodableValue("audioEncoderActive")] =
      EncodableValue(snapshot.audio_encoder_active);
  map[EncodableValue("audioTransportActive")] =
      EncodableValue(snapshot.audio_transport_active);
  map[EncodableValue("audioRoutingMode")] =
      EncodableValue(snapshot.audio_routing_mode);
  map[EncodableValue("audioMuteUnsupportedReason")] =
      EncodableValue(snapshot.audio_mute_unsupported_reason);
  map[EncodableValue("tvAudioSourceDeviceId")] =
      EncodableValue(snapshot.tv_audio_source_device_id);
  map[EncodableValue("tvAudioSourceDeviceName")] =
      EncodableValue(snapshot.tv_audio_source_device_name);
  map[EncodableValue("pcMonitorDeviceId")] =
      EncodableValue(snapshot.pc_monitor_device_id);
  map[EncodableValue("pcMonitorDeviceName")] =
      EncodableValue(snapshot.pc_monitor_device_name);
  map[EncodableValue("localMonitorActive")] =
      EncodableValue(snapshot.local_monitor_active);
  map[EncodableValue("localMonitorMuted")] =
      EncodableValue(snapshot.local_monitor_muted);
  map[EncodableValue("localMonitorQueueDepth")] =
      EncodableValue(snapshot.local_monitor_queue_depth);
  map[EncodableValue("localMonitorDroppedBuffers")] =
      EncodableValue(
          static_cast<int64_t>(snapshot.local_monitor_dropped_buffers));
  map[EncodableValue("audioCaptureFormat")] =
      EncodableValue(snapshot.audio_capture_format);
  map[EncodableValue("audioMonitorFormat")] =
      EncodableValue(snapshot.audio_monitor_format);
  map[EncodableValue("audioRoutingUnsupportedReason")] =
      EncodableValue(snapshot.audio_routing_unsupported_reason);
  map[EncodableValue("requestedProfile")] =
      EncodableValue(snapshot.requested_profile);
  map[EncodableValue("appliedProfile")] =
      EncodableValue(snapshot.applied_profile);
  map[EncodableValue("profileFallbackReason")] =
      EncodableValue(snapshot.profile_fallback_reason);
  map[EncodableValue("outputWidth")] = EncodableValue(snapshot.output_width);
  map[EncodableValue("outputHeight")] = EncodableValue(snapshot.output_height);
  map[EncodableValue("targetBitrateKbps")] =
      EncodableValue(snapshot.target_bitrate_kbps);
  map[EncodableValue("encoderName")] =
      EncodableValue(snapshot.encoder_name);
  map[EncodableValue("hardwareEncoderActive")] =
      EncodableValue(snapshot.hardware_encoder_active);
  map[EncodableValue("encoderSupportsRequestedResolution")] =
      EncodableValue(snapshot.encoder_supports_requested_resolution);
  map[EncodableValue("receiverMaxWidth")] =
      EncodableValue(snapshot.receiver_max_width);
  map[EncodableValue("receiverMaxHeight")] =
      EncodableValue(snapshot.receiver_max_height);
  map[EncodableValue("receiverSupports4k30")] =
      EncodableValue(snapshot.receiver_supports_4k30);
  map[EncodableValue("captureFpsRecent")] =
      EncodableValue(snapshot.capture_fps_recent);
  map[EncodableValue("conversionFpsRecent")] =
      EncodableValue(snapshot.conversion_fps_recent);
  map[EncodableValue("encoderInputFpsRecent")] =
      EncodableValue(snapshot.encoder_input_fps_recent);
  map[EncodableValue("encoderOutputFpsRecent")] =
      EncodableValue(snapshot.encoder_output_fps_recent);
  map[EncodableValue("transportVideoFpsRecent")] =
      EncodableValue(snapshot.transport_video_fps_recent);
  map[EncodableValue("receiverPresentedFpsRecent")] =
      EncodableValue(snapshot.receiver_presented_fps_recent);
  map[EncodableValue("receiverReceivedFpsRecent")] =
      EncodableValue(snapshot.receiver_received_fps_recent);
  map[EncodableValue("receiverDecoderInputFpsRecent")] =
      EncodableValue(snapshot.receiver_decoder_input_fps_recent);
  map[EncodableValue("receiverDecoderOutputFpsRecent")] =
      EncodableValue(snapshot.receiver_decoder_output_fps_recent);
  map[EncodableValue("receiverDecoderOutputReleased")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_output_released));
  map[EncodableValue("receiverDecoderOutputReleasedImmediate")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_output_released_immediate));
  map[EncodableValue("receiverDecoderOutputReleasedScheduled")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_output_released_scheduled));
  map[EncodableValue("receiverOnFrameRenderedCallbacks")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_on_frame_rendered_callbacks));
  map[EncodableValue("receiverVideoRenderMode")] =
      EncodableValue(snapshot.receiver_video_render_mode);
  map[EncodableValue("receiverPtsIntervalP50Ms")] =
      EncodableValue(snapshot.receiver_pts_interval_p50_ms);
  map[EncodableValue("receiverPtsRegressionCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_pts_regression_count));
  map[EncodableValue("receiverAccessUnitBytes")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_access_unit_bytes));
  map[EncodableValue("receiverKeyFramesReceived")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_key_frames_received));
  map[EncodableValue("receiverCodecConfigsReceived")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_codec_configs_received));
  map[EncodableValue("receiverDecoderConfiguredWidth")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_configured_width));
  map[EncodableValue("receiverDecoderConfiguredHeight")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_configured_height));
  map[EncodableValue("receiverDecoderOutputWidth")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_output_width));
  map[EncodableValue("receiverDecoderOutputHeight")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_output_height));
  map[EncodableValue("receiverDecoderCropLeft")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_crop_left));
  map[EncodableValue("receiverDecoderCropTop")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_crop_top));
  map[EncodableValue("receiverDecoderCropRight")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_crop_right));
  map[EncodableValue("receiverDecoderCropBottom")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_crop_bottom));
  map[EncodableValue("receiverDecoderFormatChangeCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_decoder_format_change_count));
  map[EncodableValue("receiverSurfaceWidth")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_surface_width));
  map[EncodableValue("receiverSurfaceHeight")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_surface_height));
  map[EncodableValue("encodedAccessUnitBytes")] =
      EncodableValue(static_cast<int64_t>(snapshot.encoded_access_unit_bytes));
  map[EncodableValue("transportedAccessUnitBytes")] =
      EncodableValue(static_cast<int64_t>(snapshot.transported_access_unit_bytes));
  map[EncodableValue("videoAuSizeMismatchCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.video_au_size_mismatch_count));
  map[EncodableValue("videoFragmentMissingCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.video_fragment_missing_count));
  map[EncodableValue("videoAuReassemblyErrorCount")] =
      EncodableValue(static_cast<int64_t>(snapshot.video_au_reassembly_error_count));
  map[EncodableValue("receiverAccessUnitBytes")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_access_unit_bytes));
  map[EncodableValue("receiverKeyFramesReceived")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_key_frames_received));
  map[EncodableValue("receiverCodecConfigsReceived")] =
      EncodableValue(static_cast<int64_t>(snapshot.receiver_codec_configs_received));
  map[EncodableValue("conversionDurationP95Ms")] =
      EncodableValue(snapshot.conversion_duration_p95_ms);
  map[EncodableValue("encoderQueueWaitP95Ms")] =
      EncodableValue(snapshot.encoder_queue_wait_p95_ms);
  map[EncodableValue("transportSendP95Ms")] =
      EncodableValue(snapshot.transport_send_p95_ms);
  if (!snapshot.error_code.empty()) {
    map[EncodableValue("errorCode")] = EncodableValue(snapshot.error_code);
  }
  if (!snapshot.developer_message.empty()) {
    map[EncodableValue("developerMessage")] =
        EncodableValue(snapshot.developer_message);
  }
  return EncodableValue(map);
}

class MirrorNativeBridge {
 public:
  void Handle(const MethodCall<EncodableValue>& call,
              std::unique_ptr<MethodResult<EncodableValue>> result) {
    if (call.method_name() == "listDisplays") {
      result->Success(pctv::ListDisplays());
      return;
    }

    if (call.method_name() == "listAudioDevices") {
      EncodableList devices;
      for (const auto& device : pctv::EnumerateAudioRenderDevices()) {
        EncodableMap item;
        item[EncodableValue("id")] = EncodableValue(device.id);
        item[EncodableValue("name")] = EncodableValue(device.name);
        item[EncodableValue("isDefault")] = EncodableValue(device.is_default);
        item[EncodableValue("isLikelyVirtual")] =
            EncodableValue(device.is_likely_virtual);
        devices.emplace_back(item);
      }
      result->Success(EncodableValue(devices));
      return;
    }

    if (call.method_name() == "startSession") {
      StartSession(call, std::move(result));
      return;
    }

    if (call.method_name() == "stopSession") {
      result->Success(ToEncodable(session_.Stop()));
      return;
    }

    if (call.method_name() == "getSessionStatus") {
      result->Success(ToEncodable(session_.Snapshot()));
      return;
    }

    if (call.method_name() == "setPcLocalAudioMuteRequested") {
      const auto* args = std::get_if<EncodableMap>(call.arguments());
      if (args == nullptr) {
        result->Error("INVALID_ARGUMENTS",
                      "setPcLocalAudioMuteRequested expects an object");
        return;
      }
      result->Success(ToEncodable(session_.SetPcLocalAudioMuteRequested(
          ReadBool(*args, "requested", false))));
      return;
    }

    result->NotImplemented();
  }

 private:
  void StartSession(const MethodCall<EncodableValue>& call,
                    std::unique_ptr<MethodResult<EncodableValue>> result) {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("INVALID_ARGUMENTS", "startSession expects an object");
      return;
    }

    pctv::StartSessionOptions options;
    options.receiver_host = ReadString(*args, "receiverHost");
    options.receiver_port = ReadInt(*args, "receiverPort", 50720);
    options.request_json = ReadString(*args, "requestJson");
    options.source_id = ReadString(*args, "sourceId");
    options.audio_enabled = ReadBool(*args, "audioEnabled", true);
    options.tv_audio_source_device_id =
        ReadString(*args, "tvAudioSourceDeviceId");
    options.pc_monitor_device_id = ReadString(*args, "pcMonitorDeviceId");
    options.pc_local_audio_mute_requested = ReadBool(
        *args, "pcLocalAudioMuteRequested",
        ReadBool(*args, "tvOnlyAudioRequested", false));
    options.video.width = ReadInt(*args, "videoWidth", 1280);
    options.video.height = ReadInt(*args, "videoHeight", 720);
    options.video.fps = ReadInt(*args, "videoFps", 30);
    options.video.bitrate_kbps = ReadInt(*args, "videoBitrateKbps", 6000);
    options.video.performance_profile =
        ReadString(*args, "videoPerformanceProfile");
    if (options.video.performance_profile.empty()) {
      options.video.performance_profile = "lowLatency720p30";
    }
    options.video.keyframe_interval_frames = options.video.fps;
    options.video.require_hardware_encoder =
        options.video.performance_profile == "experimental4k30";
    result->Success(ToEncodable(session_.Start(options)));
  }

  pctv::MirrorSession session_;
};

}  // namespace

void RegisterMirrorNativeBridge(flutter::FlutterEngine* engine) {
  static std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  auto bridge = std::make_shared<MirrorNativeBridge>();
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [bridge](const MethodCall<EncodableValue>& call,
               std::unique_ptr<MethodResult<EncodableValue>> result) {
        bridge->Handle(call, std::move(result));
      });
}
