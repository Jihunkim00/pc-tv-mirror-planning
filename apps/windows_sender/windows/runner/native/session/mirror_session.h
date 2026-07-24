#ifndef RUNNER_NATIVE_SESSION_MIRROR_SESSION_H_
#define RUNNER_NATIVE_SESSION_MIRROR_SESSION_H_

#include "native/capture/display_capture.h"
#include "native/session/session_types.h"
#include "native/transport/bounded_queue.h"
#include "native/transport/video_transport.h"
#include "native/video/h264_encoder.h"

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace pctv {

class MirrorSession {
 public:
  NativeSnapshot Start(const StartSessionOptions& options);
  NativeSnapshot Stop();
  NativeSnapshot Snapshot();

 private:
  struct QueuedVideoPacket {
    std::vector<std::uint8_t> bytes;
    bool access_unit = false;
    bool key_frame = false;
  };

  void EncodeLoop();
  void SendLoop();
  bool SendCodecConfig(const H264ParameterSets& parameter_sets);
  bool SendFirstAccessUnit(std::vector<std::uint8_t> packet, bool key_frame);
  NativeSnapshot BuildSnapshot(const std::string& state,
                               const std::string& user_message);
  NativeSnapshot CurrentSnapshotLocked();
  void ResetCounters();
  void SetSessionError(const std::string& error_code,
                       const std::string& user_message,
                       const std::string& developer_message);
  void SetLastEncodeError(const std::string& error);
  void SetLastSendError(const std::string& error);
  void MarkFirstAccessUnitSent();

  std::mutex mutex_;
  std::mutex status_mutex_;
  std::condition_variable status_changed_;
  std::atomic_bool running_{false};
  std::string last_source_id_;
  BoundedQueue<QueuedVideoPacket> packet_queue_{2};
  std::unique_ptr<DisplayCapture> capture_;
  H264Encoder encoder_;
  VideoTransportClient transport_;
  std::thread encode_thread_;
  std::thread send_thread_;
  std::atomic_uint32_t next_sequence_{1};
  std::atomic_uint64_t captured_frames_{0};
  std::atomic_uint64_t capture_dropped_frames_{0};
  std::atomic_uint64_t encoder_input_dropped_frames_{0};
  std::atomic_uint64_t encoded_frames_{0};
  std::atomic_uint64_t transport_dropped_frames_{0};
  std::atomic_uint64_t codec_config_sent_{0};
  std::atomic_uint64_t key_frames_sent_{0};
  std::atomic_uint64_t packets_sent_{0};
  std::atomic_uint64_t bytes_sent_{0};
  std::atomic_uint64_t send_completed_bytes_{0};
  double last_capture_to_encode_ms_ = 0.0;
  double total_capture_to_encode_ms_ = 0.0;
  double max_capture_to_encode_ms_ = 0.0;
  bool first_access_unit_sent_ = false;
  bool codec_config_sent_for_stream_ = false;
  std::string session_error_code_;
  std::string session_user_message_;
  std::string session_developer_message_;
  std::string last_encode_error_;
  std::string last_send_error_;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_SESSION_MIRROR_SESSION_H_
