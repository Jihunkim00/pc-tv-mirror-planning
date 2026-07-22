#ifndef RUNNER_NATIVE_VIDEO_VIDEO_TYPES_H_
#define RUNNER_NATIVE_VIDEO_VIDEO_TYPES_H_

#include <cstdint>
#include <vector>

namespace pctv {

struct Nv12Frame {
  int width = 1280;
  int height = 720;
  std::uint64_t pts_us = 0;
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
