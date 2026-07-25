#ifndef RUNNER_NATIVE_AUDIO_AUDIO_DEVICE_ENUMERATOR_H_
#define RUNNER_NATIVE_AUDIO_AUDIO_DEVICE_ENUMERATOR_H_

#include <optional>
#include <string>
#include <vector>

namespace pctv {

struct AudioDeviceInfo {
  std::string id;
  std::string name;
  bool is_default = false;
  bool is_likely_virtual = false;
};

std::vector<AudioDeviceInfo> EnumerateAudioRenderDevices();
std::optional<AudioDeviceInfo> FindAudioRenderDeviceById(
    const std::string& device_id);
std::string GetDefaultAudioRenderDeviceId();
bool IsLikelyVirtualAudioDeviceName(const std::string& name);
std::wstring Utf8ToWide(const std::string& value);
std::string WideToUtf8(const wchar_t* value);

}  // namespace pctv

#endif  // RUNNER_NATIVE_AUDIO_AUDIO_DEVICE_ENUMERATOR_H_
