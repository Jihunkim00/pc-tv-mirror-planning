#ifndef RUNNER_NATIVE_VIDEO_H264_ENCODER_H_
#define RUNNER_NATIVE_VIDEO_H264_ENCODER_H_

#include "native/video/video_types.h"

#include <mfidl.h>
#include <mftransform.h>

#include <atomic>
#include <deque>
#include <mutex>
#include <string>
#include <vector>

#include <winrt/base.h>

namespace pctv {

struct H264EncoderDiagnostics {
  std::string selected_encoder_name = "unknown";
  bool selected_encoder_hardware = false;
  bool selected_encoder_async = false;
  bool encoder_d3d11_aware = false;
  std::string encoder_input_format = "NV12 1280x720@30";
  std::string encoder_output_format = "H.264 1280x720@30";
  std::uint64_t encoder_backpressure_count = 0;
  std::uint64_t encoder_backpressure_dropped_frames = 0;
  std::uint64_t process_input_calls = 0;
  std::uint64_t process_input_accepted = 0;
  std::uint64_t process_input_not_accepting = 0;
  std::uint64_t process_input_retries = 0;
  std::uint64_t process_output_calls = 0;
  std::uint64_t process_output_frames = 0;
  std::uint32_t mft_input_stream_flags = 0;
  bool mft_does_not_addref = false;
  bool mft_holds_buffers = false;
  std::uint32_t mft_input_buffer_size = 0;
  std::uint32_t mft_input_buffer_alignment = 0;
  std::uint64_t encoder_input_sample_id = 0;
  std::uint64_t encoder_input_buffer_id = 0;
  std::uint64_t input_sample_create_count = 0;
  std::uint64_t input_buffer_create_count = 0;
  int input_buffer_pool_size = 0;
  int input_buffers_in_flight = 0;
  std::uint64_t input_buffer_reuse_count = 0;
  std::uint64_t unsafe_input_buffer_reuse_detected = 0;
  std::uint64_t nv12_guard_corruption_count = 0;
  std::uint64_t key_frame_count = 0;
  std::uint64_t frames_since_last_key_frame = 0;
  std::uint64_t last_key_frame_pts_us = 0;
  std::uint64_t last_key_frame_size_bytes = 0;
  std::uint64_t last_key_frame_interval_frames = 0;
  std::uint64_t last_key_frame_interval_ms = 0;
  int keyframe_interval_frames = 0;
  double process_input_duration_average_ms = 0.0;
  double process_input_duration_p95_ms = 0.0;
  double process_output_duration_average_ms = 0.0;
  double process_output_duration_p95_ms = 0.0;
  std::string low_latency_options_applied;
  std::string unsupported_encoder_options;
};

class H264Encoder {
 public:
  H264Encoder();
  ~H264Encoder();

  H264Encoder(const H264Encoder&) = delete;
  H264Encoder& operator=(const H264Encoder&) = delete;

  bool Start(const VideoStreamConfig& config, std::string* error);
  bool Start(std::string* error) {
    return Start(VideoStreamConfig{}, error);
  }
  bool Encode(const Nv12Frame& frame,
              std::vector<EncodedAccessUnit>* output,
              bool* input_accepted,
              bool* backpressure_dropped,
              std::string* error);
  void RequestKeyFrame();
  void Stop();
  H264ParameterSets parameter_sets() const { return parameter_sets_; }
  H264EncoderDiagnostics diagnostics() const;

 private:
  bool CreateHardwareEncoder(std::string* error);
  bool CreateSoftwareEncoder(std::string* error);
  bool ConfigureTypes(std::string* error);
  bool ForceNextKeyFrame(std::string* error);
  bool RefreshSequenceHeaderFromCurrentType(bool require_header,
                                            std::string* error);
  bool ReadAvailableOutput(std::vector<EncodedAccessUnit>* output,
                           std::string* error);
  void RecordProcessInputDuration(std::uint64_t now_us, double value_ms);
  void RecordProcessOutputDuration(std::uint64_t now_us, double value_ms);
  std::vector<std::uint8_t> NormalizeAnnexB(
      const std::vector<std::uint8_t>& encoded) const;

  bool first_pts_set_ = false;
  winrt::com_ptr<IMFTransform> transform_;
  VideoStreamConfig config_;
  std::vector<std::uint8_t> sequence_header_;
  H264ParameterSets parameter_sets_;
  H264EncoderDiagnostics diagnostics_;
  mutable std::mutex diagnostics_mutex_;
  std::deque<std::pair<std::uint64_t, double>> process_input_samples_;
  std::deque<std::pair<std::uint64_t, double>> process_output_samples_;
  std::uint64_t first_pts_us_ = 0;
  std::uint64_t next_input_sample_id_ = 1;
  std::uint64_t next_input_buffer_id_ = 1;
  std::uint64_t output_frame_index_ = 0;
  std::uint64_t previous_key_frame_output_index_ = 0;
  std::uint64_t previous_key_frame_pts_us_ = 0;
  bool previous_key_frame_seen_ = false;
  std::uint64_t encoder_backpressure_count_ = 0;
  std::uint64_t encoder_backpressure_dropped_frames_ = 0;
  std::atomic_bool force_next_key_frame_{false};
  bool mf_started_ = false;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_VIDEO_H264_ENCODER_H_
