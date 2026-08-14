#ifndef RUNNER_NATIVE_VIDEO_VIDEO_TYPES_H_
#define RUNNER_NATIVE_VIDEO_VIDEO_TYPES_H_

#include <cstdint>
#include <string>
#include <vector>

namespace pctv {

struct VideoStreamConfig {
  int width = 1280;
  int height = 720;
  int fps = 30;
  int bitrate_kbps = 6000;
  int keyframe_interval_frames = 30;
  std::string performance_profile = "lowLatency720p30";
  bool require_hardware_encoder = false;
};

struct Nv12Frame {
  int width = 1280;
  int height = 720;
  std::uint64_t capture_system_relative_time_ns = 0;
  std::uint64_t source_timestamp_delta_us = 0;
  bool source_pts_valid = false;
  std::string video_pts_source = "fallback_frame_clock";
  std::uint64_t pts_us = 0;
  std::uint64_t capture_callback_us = 0;
  std::uint64_t convert_started_us = 0;
  std::uint64_t converted_us = 0;
  std::uint64_t convert_duration_us = 0;
  std::uint64_t scale_duration_us = 0;
  std::uint64_t bgra_to_nv12_duration_us = 0;
  int dropped_frames = 0;
  std::uint32_t source_texture_width = 0;
  std::uint32_t source_texture_height = 0;
  std::string source_texture_format = "unavailable";
  std::uint32_t source_row_pitch = 0;
  std::uint32_t source_bgra_stride = 0;
  std::uint32_t nv12_y_offset = 0;
  std::uint32_t nv12_uv_offset = 0;
  std::uint32_t nv12_y_stride = 0;
  std::uint32_t nv12_uv_stride = 0;
  std::uint32_t nv12_expected_bytes = 0;
  std::uint32_t nv12_allocated_bytes = 0;
  std::uint32_t nv12_used_bytes = 0;
  std::uint32_t encoder_input_stride = 0;
  bool nv12_guard_corrupted = false;
  std::vector<std::uint8_t> data;

  std::size_t payload_size() const {
    return nv12_used_bytes == 0 ? data.size() : nv12_used_bytes;
  }
};

struct EncodedAccessUnit {
  std::uint64_t pts_us = 0;
  bool key_frame = false;
  std::vector<std::uint8_t> annex_b;
};

struct H264ParameterSets {
  std::vector<std::uint8_t> sps;
  std::vector<std::uint8_t> pps;

  bool complete() const { return !sps.empty() && !pps.empty(); }
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_VIDEO_VIDEO_TYPES_H_
