#ifndef RUNNER_NATIVE_SESSION_MIRROR_SESSION_H_
#define RUNNER_NATIVE_SESSION_MIRROR_SESSION_H_

#include "native/audio/aac_encoder.h"
#include "native/audio/system_audio_loopback.h"
#include "native/capture/display_capture.h"
#include "native/session/session_types.h"
#include "native/transport/bounded_queue.h"
#include "native/transport/video_transport.h"
#include "native/video/h264_encoder.h"

#include <atomic>
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
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
    std::uint64_t sequence = 0;
    std::uint64_t encoded_done_us = 0;
  };

  struct QueuedAudioPacket {
    std::vector<std::uint8_t> bytes;
    bool config = false;
    bool access_unit = false;
    std::uint64_t sequence = 0;
    std::uint64_t encoded_done_us = 0;
  };

  void EncodeLoop();
  void AudioLoop();
  void SendLoop();
  void ControlLoop();
  void HandlePlaybackCommandLine(const std::string& line);
  void ApplyPause(std::uint64_t command_id, const std::string& command);
  void ApplyResume(std::uint64_t command_id, const std::string& command);
  void SendPlaybackAck(std::uint64_t command_id,
                       const std::string& command,
                       const std::string& sender_state);
  void SendPlaybackError(std::uint64_t command_id,
                         const std::string& command,
                         const std::string& error_code,
                         const std::string& message);
  bool IsPaused() const { return paused_.load(); }
  bool SendCodecConfig(const H264ParameterSets& parameter_sets);
  bool SendFirstAccessUnit(std::vector<std::uint8_t> packet,
                           bool key_frame,
                           std::uint64_t encoded_done_us);
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
  std::mutex transport_send_mutex_;
  std::condition_variable status_changed_;
  std::atomic_bool running_{false};
  std::string last_source_id_;
  BoundedQueue<QueuedVideoPacket> packet_queue_{2};
  BoundedQueue<QueuedAudioPacket> audio_queue_{8};
  std::unique_ptr<DisplayCapture> capture_;
  H264Encoder encoder_;
  VideoTransportClient transport_;
  std::thread encode_thread_;
  std::thread audio_thread_;
  std::thread send_thread_;
  std::thread control_thread_;
  VideoStreamConfig video_config_;
  double target_fps_ = 30.0;
  std::uint64_t target_frame_interval_us_ = 33'333;
  std::atomic_bool paused_{false};
  std::atomic_bool audio_config_requested_{false};
  std::atomic_bool tv_only_audio_requested_{false};
  std::atomic_uint64_t next_sequence_{1};
  std::atomic_uint64_t next_audio_sequence_{1};
  std::atomic_uint64_t captured_frames_{0};
  std::atomic_uint64_t capture_replaced_frames_{0};
  std::atomic_uint64_t cadence_skipped_frames_{0};
  std::atomic_uint64_t conversion_backpressure_dropped_frames_{0};
  std::atomic_uint64_t encoder_backpressure_dropped_frames_{0};
  std::atomic_uint64_t transport_backpressure_dropped_frames_{0};
  std::atomic_uint64_t shutdown_dropped_frames_{0};
  std::atomic_uint64_t capture_dropped_frames_{0};
  std::atomic_uint64_t conversion_dropped_frames_{0};
  std::atomic_uint64_t encoder_input_dropped_frames_{0};
  std::atomic_uint64_t encoded_frames_{0};
  std::atomic_uint64_t transport_dropped_frames_{0};
  std::atomic_uint64_t duplicated_frames_{0};
  std::atomic_uint64_t last_processed_frame_sequence_{0};
  std::atomic_uint64_t codec_config_sent_{0};
  std::atomic_uint64_t key_frames_sent_{0};
  std::atomic_uint64_t packets_sent_{0};
  std::atomic_uint64_t bytes_sent_{0};
  std::atomic_uint64_t send_completed_bytes_{0};
  std::atomic_bool audio_enabled_{false};
  std::atomic_uint64_t captured_audio_packets_{0};
  std::atomic_uint64_t encoded_audio_packets_{0};
  std::atomic_uint64_t sent_audio_packets_{0};
  std::atomic_uint64_t audio_dropped_packets_{0};
  std::atomic_uint64_t pause_requests_received_{0};
  std::atomic_uint64_t resume_requests_received_{0};
  std::atomic_uint64_t playback_command_acks_sent_{0};
  std::atomic_uint64_t playback_command_errors_sent_{0};
  std::atomic_uint64_t resume_codec_config_resends_{0};
  std::atomic_uint64_t last_playback_command_id_{0};
  std::uint64_t next_admission_deadline_us_ = 0;
  std::deque<std::uint64_t> capture_callback_events_us_;
  std::deque<std::uint64_t> captured_events_us_;
  std::deque<std::uint64_t> target_admission_events_us_;
  std::deque<std::uint64_t> admitted_frame_events_us_;
  std::deque<std::uint64_t> converted_events_us_;
  std::deque<std::uint64_t> encoder_accepted_events_us_;
  std::deque<std::uint64_t> encoder_input_events_us_;
  std::deque<std::uint64_t> encoded_events_us_;
  std::deque<std::uint64_t> sent_access_unit_events_us_;
  std::deque<std::uint64_t> cadence_dropped_events_us_;
  std::deque<std::uint64_t> encoder_busy_dropped_events_us_;
  std::deque<std::uint64_t> conversion_busy_dropped_events_us_;
  std::deque<std::uint64_t> socket_send_call_events_us_;
  std::deque<std::uint64_t> audio_capture_events_us_;
  std::deque<std::pair<std::uint64_t, double>> capture_to_convert_samples_;
  std::deque<std::pair<std::uint64_t, double>> convert_to_encode_samples_;
  std::deque<std::pair<std::uint64_t, double>> encode_duration_samples_;
  std::deque<std::pair<std::uint64_t, double>> encode_to_send_samples_;
  std::deque<std::pair<std::uint64_t, double>> packet_send_duration_samples_;
  std::deque<std::pair<std::uint64_t, double>> access_unit_send_duration_samples_;
  std::deque<std::pair<std::uint64_t, double>> audio_encode_duration_samples_;
  std::deque<std::pair<std::uint64_t, double>> packet_writer_video_wait_samples_;
  std::deque<std::pair<std::uint64_t, double>> packet_writer_audio_wait_samples_;
  double last_capture_to_encode_ms_ = 0.0;
  double total_capture_to_encode_ms_ = 0.0;
  double max_capture_to_encode_ms_ = 0.0;
  bool first_access_unit_sent_ = false;
  std::atomic_bool codec_config_sent_for_stream_{false};
  std::string session_error_code_;
  std::string session_user_message_;
  std::string session_developer_message_;
  std::string last_encode_error_;
  std::string last_send_error_;
  std::string audio_capture_state_ = "disabled";
  std::string audio_device_name_;
  int audio_input_sample_rate_ = 0;
  int audio_input_channels_ = 0;
  std::string audio_last_error_;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_SESSION_MIRROR_SESSION_H_
