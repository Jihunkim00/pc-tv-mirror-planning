#ifndef RUNNER_NATIVE_SESSION_SESSION_TYPES_H_
#define RUNNER_NATIVE_SESSION_SESSION_TYPES_H_

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
};

struct StartSessionOptions {
  std::string receiver_host;
  int receiver_port = 50720;
  std::string request_json;
  std::string source_id;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_SESSION_SESSION_TYPES_H_
