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
  std::uint64_t pts_us = 0;
  std::uint64_t capture_callback_us = 0;
  std::uint64_t convert_started_us = 0;
  std::uint64_t converted_us = 0;
  std::uint64_t convert_duration_us = 0;
  int dropped_frames = 0;
  std::vector<std::uint8_t> data;
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
