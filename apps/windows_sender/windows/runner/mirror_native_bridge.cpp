#include "mirror_native_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>

#include "native/display/display_enumerator.h"
#include "native/session/mirror_session.h"

namespace {

using flutter::EncodableMap;
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
  map[EncodableValue("state")] = EncodableValue(snapshot.state);
  map[EncodableValue("userMessage")] = EncodableValue(snapshot.user_message);
  map[EncodableValue("captureReady")] = EncodableValue(snapshot.capture_ready);
  map[EncodableValue("encoderReady")] = EncodableValue(snapshot.encoder_ready);
  map[EncodableValue("signalingReady")] =
      EncodableValue(snapshot.signaling_ready);
  map[EncodableValue("nativeVideoPathReady")] =
      EncodableValue(snapshot.native_video_path_ready);
  map[EncodableValue("targetFps")] = EncodableValue(snapshot.target_fps);
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
  map[EncodableValue("captureToConvertAverageMs")] =
      EncodableValue(snapshot.capture_to_convert_average_ms);
  map[EncodableValue("convertToEncodeAverageMs")] =
      EncodableValue(snapshot.convert_to_encode_average_ms);
  map[EncodableValue("encodeDurationAverageMs")] =
      EncodableValue(snapshot.encode_duration_average_ms);
  map[EncodableValue("encodeDurationP95Ms")] =
      EncodableValue(snapshot.encode_duration_p95_ms);
  map[EncodableValue("encodeToSendAverageMs")] =
      EncodableValue(snapshot.encode_to_send_average_ms);
  map[EncodableValue("capturedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.captured_frames));
  map[EncodableValue("captureReplacedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.capture_replaced_frames));
  map[EncodableValue("cadenceSkippedFrames")] =
      EncodableValue(static_cast<int64_t>(snapshot.cadence_skipped_frames));
  map[EncodableValue("conversionBackpressureDroppedFrames")] =
      EncodableValue(static_cast<int64_t>(
          snapshot.conversion_backpressure_dropped_frames));
  map[EncodableValue("encoderBackpressureDroppedFrames")] =
      EncodableValue(
          static_cast<int64_t>(snapshot.encoder_backpressure_dropped_frames));
  map[EncodableValue("transportBackpressureDroppedFrames")] =
      EncodableValue(
          static_cast<int64_t>(snapshot.transport_backpressure_dropped_frames));
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
  map[EncodableValue("processInputDurationAverageMs")] =
      EncodableValue(snapshot.process_input_duration_average_ms);
  map[EncodableValue("processInputDurationP95Ms")] =
      EncodableValue(snapshot.process_input_duration_p95_ms);
  map[EncodableValue("processOutputDurationAverageMs")] =
      EncodableValue(snapshot.process_output_duration_average_ms);
  map[EncodableValue("processOutputDurationP95Ms")] =
      EncodableValue(snapshot.process_output_duration_p95_ms);
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
