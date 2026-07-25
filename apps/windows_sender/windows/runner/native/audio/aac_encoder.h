#ifndef RUNNER_NATIVE_AUDIO_AAC_ENCODER_H_
#define RUNNER_NATIVE_AUDIO_AAC_ENCODER_H_

#include "native/audio/audio_types.h"

#include <mfidl.h>
#include <mftransform.h>

#include <cstdint>
#include <string>
#include <vector>

#include <winrt/base.h>

namespace pctv {

class AacEncoder {
 public:
  AacEncoder();
  ~AacEncoder();

  AacEncoder(const AacEncoder&) = delete;
  AacEncoder& operator=(const AacEncoder&) = delete;

  bool Start(std::string* error);
  bool Encode(const PcmAudioFrame& frame,
              std::vector<EncodedAudioAccessUnit>* output,
              std::string* error);
  void Stop();

  std::vector<std::uint8_t> codec_specific_data() const {
    return {0x11, 0x90};
  }

 private:
  bool ConfigureTypes(std::string* error);
  bool ReadAvailableOutput(std::vector<EncodedAudioAccessUnit>* output,
                           std::string* error);

  winrt::com_ptr<IMFTransform> transform_;
  std::uint64_t first_pts_us_ = 0;
  bool mf_started_ = false;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_AUDIO_AAC_ENCODER_H_
