#ifndef RUNNER_NATIVE_AUDIO_AUDIO_ENDPOINT_MUTE_CONTROLLER_H_
#define RUNNER_NATIVE_AUDIO_AUDIO_ENDPOINT_MUTE_CONTROLLER_H_

#include "native/audio/endpoint_mute_policy.h"

#include <endpointvolume.h>
#include <mmdeviceapi.h>

#include <atomic>
#include <string>

#include <winrt/base.h>

namespace pctv {

class AudioEndpointMuteController {
 public:
  AudioEndpointMuteController() = default;
  ~AudioEndpointMuteController();

  AudioEndpointMuteController(const AudioEndpointMuteController&) = delete;
  AudioEndpointMuteController& operator=(
      const AudioEndpointMuteController&) = delete;

  bool Start(IMMDevice* endpoint,
             std::string* error_code,
             std::string* error);
  bool ApplyRequestedState(bool requested,
                           std::string* error_code,
                           std::string* error);
  bool Stop(std::string* error_code, std::string* error);

  bool started() const { return endpoint_volume_ != nullptr; }
  bool actual_muted() const { return actual_muted_.load(); }
  bool original_muted() const { return policy_.original_mute_state(); }
  bool applied_by_app() const { return policy_.changed_by_app(); }
  bool externally_overridden() const { return policy_.external_override(); }

 private:
  class NotificationCallback;

  bool ReadMuteState(bool* muted,
                     std::string* error_code,
                     std::string* error);
  bool WriteMuteState(bool muted,
                      std::string* error_code,
                      std::string* error);
  void ResetError(std::string* error_code, std::string* error);

  winrt::com_ptr<IAudioEndpointVolume> endpoint_volume_;
  NotificationCallback* callback_ = nullptr;
  EndpointMutePolicy policy_;
  std::atomic_bool external_change_pending_{false};
  std::atomic_bool actual_muted_{false};
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_AUDIO_AUDIO_ENDPOINT_MUTE_CONTROLLER_H_
