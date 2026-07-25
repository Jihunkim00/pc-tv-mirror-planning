#ifndef RUNNER_NATIVE_AUDIO_AUDIO_TYPES_H_
#define RUNNER_NATIVE_AUDIO_AUDIO_TYPES_H_

#include <cstdint>
#include <string>
#include <vector>

namespace pctv {

constexpr int kAudioSampleRate = 48000;
constexpr int kAudioChannels = 2;
constexpr int kAudioBitrate = 128000;
constexpr int kAudioFramesPerAccessUnit = 1024;

struct PcmAudioFrame {
  std::vector<std::uint8_t> pcm_s16le;
  std::uint64_t pts_us = 0;
  std::uint32_t frame_count = 0;
  int sample_rate = kAudioSampleRate;
  int channels = kAudioChannels;
};

struct EncodedAudioAccessUnit {
  std::vector<std::uint8_t> bytes;
  std::uint64_t pts_us = 0;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_AUDIO_AUDIO_TYPES_H_
