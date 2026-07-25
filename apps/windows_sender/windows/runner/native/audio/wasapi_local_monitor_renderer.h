#ifndef RUNNER_NATIVE_AUDIO_WASAPI_LOCAL_MONITOR_RENDERER_H_
#define RUNNER_NATIVE_AUDIO_WASAPI_LOCAL_MONITOR_RENDERER_H_

#include "native/audio/audio_types.h"

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <thread>

#include <winrt/base.h>

namespace pctv {

class WasapiLocalMonitorRenderer {
 public:
  WasapiLocalMonitorRenderer();
  ~WasapiLocalMonitorRenderer();

  WasapiLocalMonitorRenderer(const WasapiLocalMonitorRenderer&) = delete;
  WasapiLocalMonitorRenderer& operator=(const WasapiLocalMonitorRenderer&) =
      delete;

  bool Start(const std::string& device_id, std::string* error);
  bool Enqueue(const PcmAudioFrame& frame);
  void SetMuted(bool muted);
  void Stop();

  bool active() const { return active_.load(); }
  bool muted() const { return muted_.load(); }
  int queue_depth() const;
  std::uint64_t dropped_buffers() const { return dropped_buffers_.load(); }
  std::string device_name() const { return device_name_; }
  std::string format_description() const { return format_description_; }
  std::string last_error() const { return last_error_; }

 private:
  void RenderLoop();
  bool WriteFrame(const PcmAudioFrame& frame, std::string* error);
  void FillRenderBuffer(BYTE* destination,
                        UINT32 frame_count,
                        UINT32 render_frame_offset,
                        UINT32 total_render_frames,
                        const PcmAudioFrame& source);
  float ReadSourceSample(const PcmAudioFrame& source,
                         UINT32 source_frame,
                         int channel) const;
  void WriteOutputSample(BYTE* destination,
                         UINT32 output_frame,
                         int channel,
                         float value) const;

  mutable std::mutex mutex_;
  std::condition_variable queue_available_;
  std::deque<PcmAudioFrame> queue_;
  std::thread render_thread_;
  winrt::com_ptr<IMMDevice> device_;
  winrt::com_ptr<IAudioClient> audio_client_;
  winrt::com_ptr<IAudioRenderClient> render_client_;
  WAVEFORMATEX* mix_format_ = nullptr;
  UINT32 endpoint_buffer_frames_ = 0;
  std::atomic_bool running_{false};
  std::atomic_bool active_{false};
  std::atomic_bool muted_{false};
  std::atomic_uint64_t dropped_buffers_{0};
  std::string device_name_;
  std::string format_description_;
  std::string last_error_;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_AUDIO_WASAPI_LOCAL_MONITOR_RENDERER_H_
