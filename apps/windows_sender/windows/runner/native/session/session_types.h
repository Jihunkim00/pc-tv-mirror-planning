#ifndef RUNNER_NATIVE_SESSION_SESSION_TYPES_H_
#define RUNNER_NATIVE_SESSION_SESSION_TYPES_H_

#include <cstdint>
#include <string>

namespace pctv {

struct NativeSnapshot {
  std::string state;
  std::string user_message;
  bool capture_ready = false;
  bool encoder_ready = false;
  bool signaling_ready = false;
  bool native_video_path_ready = false;
  std::string error_code;
  std::string developer_message;
  double target_fps = 30.0;
  double capture_callback_fps = 0.0;
  double captured_fps = 0.0;
  double converted_fps = 0.0;
  double encoder_input_fps = 0.0;
  double encoded_fps = 0.0;
  double sent_access_unit_fps = 0.0;
  double capture_frame_interval_average_ms = 0.0;
  double capture_frame_interval_p95_ms = 0.0;
  double encode_frame_interval_average_ms = 0.0;
  double send_frame_interval_average_ms = 0.0;
  double capture_to_convert_average_ms = 0.0;
  double convert_to_encode_average_ms = 0.0;
  double encode_duration_average_ms = 0.0;
  double encode_duration_p95_ms = 0.0;
  double encode_to_send_average_ms = 0.0;
  std::uint64_t captured_frames = 0;
  std::uint64_t capture_dropped_frames = 0;
  std::uint64_t conversion_dropped_frames = 0;
  std::uint64_t encoder_input_dropped_frames = 0;
  std::uint64_t encoded_frames = 0;
  std::uint64_t transport_dropped_frames = 0;
  std::uint64_t duplicated_frames = 0;
  std::uint64_t last_processed_frame_sequence = 0;
  std::uint64_t codec_config_sent = 0;
  std::uint64_t key_frames_sent = 0;
  std::uint64_t packets_sent = 0;
  std::uint64_t bytes_sent = 0;
  std::uint64_t send_completed_bytes = 0;
  double socket_send_calls_per_second = 0.0;
  double average_packet_send_duration_ms = 0.0;
  double access_unit_send_duration_average_ms = 0.0;
  double access_unit_send_duration_p95_ms = 0.0;
  std::uint64_t pending_send_bytes = 0;
  std::string last_socket_error;
  int queue_depth_capture = 0;
  int queue_depth_encoder = 0;
  int queue_depth_transport = 0;
  double last_capture_to_encode_ms = 0.0;
  double average_capture_to_encode_ms = 0.0;
  double max_capture_to_encode_ms = 0.0;
  std::string selected_encoder_name = "unknown";
  bool selected_encoder_hardware = false;
  bool selected_encoder_async = false;
  bool encoder_d3d11_aware = false;
  std::string encoder_input_format;
  std::string encoder_output_format;
  double average_encode_duration_ms = 0.0;
  std::uint64_t encoder_backpressure_count = 0;
  std::string low_latency_options_applied;
  std::string unsupported_encoder_options;
  std::string bottleneck_summary = "unknown";
  std::string last_encode_error;
  std::string last_send_error;
};

struct StartSessionOptions {
  std::string receiver_host;
  int receiver_port = 50720;
  std::string request_json;
  std::string source_id;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_SESSION_SESSION_TYPES_H_
