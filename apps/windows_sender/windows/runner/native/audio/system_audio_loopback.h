#ifndef RUNNER_NATIVE_AUDIO_SYSTEM_AUDIO_LOOPBACK_H_
#define RUNNER_NATIVE_AUDIO_SYSTEM_AUDIO_LOOPBACK_H_

#include "native/audio/audio_types.h"

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

#include <winrt/base.h>

namespace pctv {

class SystemAudioLoopback {
 public:
  SystemAudioLoopback();
  ~SystemAudioLoopback();

  SystemAudioLoopback(const SystemAudioLoopback&) = delete;
  SystemAudioLoopback& operator=(const SystemAudioLoopback&) = delete;

  bool Start(std::string* error);
  bool Start(const std::string& device_id, std::string* error);
  bool CaptureNext(PcmAudioFrame* frame, int timeout_ms, std::string* error);
  void Stop();

  std::string device_name() const { return device_name_; }
  std::string device_id() const { return device_id_; }
  IMMDevice* endpoint() const { return device_.get(); }
  std::string capture_format() const { return capture_format_; }
  int input_sample_rate() const { return input_sample_rate_; }
  int input_channels() const { return input_channels_; }
  bool event_driven() const { return event_driven_; }
  std::uint64_t stream_start_pts_us() const { return stream_start_pts_us_; }

 private:
  void AppendCapturedFrames(const BYTE* data,
                            UINT32 frame_count,
                            DWORD flags);
  float ReadSourceSample(const BYTE* data, UINT32 frame, int channel) const;
  void AppendStereoPcm16(float left, float right);

  HANDLE capture_event_ = nullptr;
  winrt::com_ptr<IMMDevice> device_;
  winrt::com_ptr<IAudioClient> audio_client_;
  winrt::com_ptr<IAudioCaptureClient> capture_client_;
  WAVEFORMATEX* mix_format_ = nullptr;
  std::string device_id_;
  std::string device_name_;
  std::string capture_format_;
  int input_sample_rate_ = 0;
  int input_channels_ = 0;
  int input_bits_per_sample_ = 0;
  WORD input_format_tag_ = 0;
  bool event_driven_ = false;
  std::uint64_t stream_start_pts_us_ = 0;
  std::uint64_t output_frame_cursor_ = 0;
  std::vector<std::int16_t> pending_pcm_;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_AUDIO_SYSTEM_AUDIO_LOOPBACK_H_
