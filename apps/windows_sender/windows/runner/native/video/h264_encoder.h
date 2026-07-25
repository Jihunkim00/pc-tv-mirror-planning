#ifndef RUNNER_NATIVE_VIDEO_H264_ENCODER_H_
#define RUNNER_NATIVE_VIDEO_H264_ENCODER_H_

#include "native/video/video_types.h"

#include <mfidl.h>
#include <mftransform.h>

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

  bool Start(std::string* error);
  bool Encode(const Nv12Frame& frame,
              std::vector<EncodedAccessUnit>* output,
              bool* input_accepted,
              bool* backpressure_dropped,
              std::string* error);
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

  winrt::com_ptr<IMFTransform> transform_;
  std::vector<std::uint8_t> sequence_header_;
  H264ParameterSets parameter_sets_;
  H264EncoderDiagnostics diagnostics_;
  mutable std::mutex diagnostics_mutex_;
  std::deque<std::pair<std::uint64_t, double>> process_input_samples_;
  std::deque<std::pair<std::uint64_t, double>> process_output_samples_;
  std::uint64_t first_pts_us_ = 0;
  std::uint64_t encoder_backpressure_count_ = 0;
  std::uint64_t encoder_backpressure_dropped_frames_ = 0;
  bool force_next_key_frame_ = false;
  bool mf_started_ = false;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_VIDEO_H264_ENCODER_H_
