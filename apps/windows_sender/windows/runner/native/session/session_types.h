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
  std::uint64_t captured_frames = 0;
  std::uint64_t capture_dropped_frames = 0;
  std::uint64_t encoder_input_dropped_frames = 0;
  std::uint64_t encoded_frames = 0;
  std::uint64_t transport_dropped_frames = 0;
  std::uint64_t codec_config_sent = 0;
  std::uint64_t key_frames_sent = 0;
  std::uint64_t packets_sent = 0;
  std::uint64_t bytes_sent = 0;
  std::uint64_t send_completed_bytes = 0;
  int queue_depth_capture = 0;
  int queue_depth_encoder = 0;
  int queue_depth_transport = 0;
  double last_capture_to_encode_ms = 0.0;
  double average_capture_to_encode_ms = 0.0;
  double max_capture_to_encode_ms = 0.0;
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
