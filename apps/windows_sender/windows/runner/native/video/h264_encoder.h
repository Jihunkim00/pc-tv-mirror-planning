#ifndef RUNNER_NATIVE_VIDEO_H264_ENCODER_H_
#define RUNNER_NATIVE_VIDEO_H264_ENCODER_H_

#include "native/video/video_types.h"

#include <mfidl.h>
#include <mftransform.h>

#include <string>
#include <vector>

#include <winrt/base.h>

namespace pctv {

class H264Encoder {
 public:
  H264Encoder();
  ~H264Encoder();

  H264Encoder(const H264Encoder&) = delete;
  H264Encoder& operator=(const H264Encoder&) = delete;

  bool Start(std::string* error);
  bool Encode(const Nv12Frame& frame,
              std::vector<EncodedAccessUnit>* output,
              std::string* error);
  void Stop();

 private:
  bool ConfigureTypes(std::string* error);
  bool ReadAvailableOutput(std::vector<EncodedAccessUnit>* output,
                           std::string* error);
  std::vector<std::uint8_t> NormalizeAnnexB(
      const std::vector<std::uint8_t>& encoded) const;

  winrt::com_ptr<IMFTransform> transform_;
  std::vector<std::uint8_t> sequence_header_;
  std::uint64_t first_pts_us_ = 0;
  bool mf_started_ = false;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_VIDEO_H264_ENCODER_H_
