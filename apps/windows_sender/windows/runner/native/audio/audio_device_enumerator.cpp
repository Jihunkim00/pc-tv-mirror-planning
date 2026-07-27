#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "native/audio/audio_device_enumerator.h"

#include <mmdeviceapi.h>
#include <propkeydef.h>
#include <functiondiscoverykeys_devpkey.h>
#include <propvarutil.h>
#include <windows.h>

#include <algorithm>
#include <cctype>

#include <winrt/base.h>

namespace pctv {
namespace {

constexpr std::size_t kMaxDeviceNameLength = 96;

std::string SanitizeDeviceName(std::string value) {
  value.erase(std::remove(value.begin(), value.end(), '\r'), value.end());
  value.erase(std::remove(value.begin(), value.end(), '\n'), value.end());
  if (value.size() > kMaxDeviceNameLength) {
    value.resize(kMaxDeviceNameLength);
  }
  return value.empty() ? "Audio output" : value;
}

std::string ReadDeviceName(IMMDevice* device) {
  winrt::com_ptr<IPropertyStore> properties;
  if (FAILED(device->OpenPropertyStore(STGM_READ, properties.put()))) {
    return "Audio output";
  }
  PROPVARIANT name;
  PropVariantInit(&name);
  std::string result;
  if (SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &name)) &&
      name.vt == VT_LPWSTR) {
    result = WideToUtf8(name.pwszVal);
  }
  PropVariantClear(&name);
  return SanitizeDeviceName(result);
}

std::string ReadDeviceId(IMMDevice* device) {
  LPWSTR raw_id = nullptr;
  if (FAILED(device->GetId(&raw_id)) || raw_id == nullptr) {
    return {};
  }
  const auto id = WideToUtf8(raw_id);
  CoTaskMemFree(raw_id);
  return id;
}

std::string LowerAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](char ch) {
    return static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  });
  return value;
}

}  // namespace

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  if (size <= 0) {
    return {};
  }
  std::wstring output(static_cast<std::size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), output.data(), size);
  return output;
}

std::string WideToUtf8(const wchar_t* value) {
  if (value == nullptr || value[0] == L'\0') {
    return {};
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                      nullptr, nullptr);
  if (size <= 1) {
    return {};
  }
  std::string output(static_cast<std::size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, output.data(), size, nullptr,
                      nullptr);
  return output;
}

bool IsLikelyVirtualAudioDeviceName(const std::string& name) {
  const auto lower = LowerAscii(name);
  return lower.find("virtual") != std::string::npos ||
         lower.find("cable input") != std::string::npos ||
         lower.find("vb-audio") != std::string::npos ||
         lower.find("voicemeeter") != std::string::npos ||
         lower.find("voice meeter") != std::string::npos ||
         lower.find("tv mirror") != std::string::npos;
}

std::string GetDefaultAudioRenderDeviceId() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }

  winrt::com_ptr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(enumerator.put())))) {
    return {};
  }
  winrt::com_ptr<IMMDevice> device;
  if (FAILED(
          enumerator->GetDefaultAudioEndpoint(eRender, eConsole, device.put()))) {
    return {};
  }
  return ReadDeviceId(device.get());
}

std::vector<AudioDeviceInfo> EnumerateAudioRenderDevices() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }

  std::vector<AudioDeviceInfo> devices;
  winrt::com_ptr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(enumerator.put())))) {
    return devices;
  }

  const auto default_id = GetDefaultAudioRenderDeviceId();
  winrt::com_ptr<IMMDeviceCollection> collection;
  if (FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE,
                                            collection.put()))) {
    return devices;
  }

  UINT count = 0;
  if (FAILED(collection->GetCount(&count))) {
    return devices;
  }
  devices.reserve(count);
  for (UINT index = 0; index < count; ++index) {
    winrt::com_ptr<IMMDevice> device;
    if (FAILED(collection->Item(index, device.put()))) {
      continue;
    }
    auto id = ReadDeviceId(device.get());
    auto name = ReadDeviceName(device.get());
    if (id.empty()) {
      continue;
    }
    devices.push_back(AudioDeviceInfo{
        id,
        name,
        !default_id.empty() && id == default_id,
        IsLikelyVirtualAudioDeviceName(name),
    });
  }
  return devices;
}

std::optional<AudioDeviceInfo> FindAudioRenderDeviceById(
    const std::string& device_id) {
  if (device_id.empty()) {
    return std::nullopt;
  }
  const auto devices = EnumerateAudioRenderDevices();
  const auto match = std::find_if(devices.begin(), devices.end(),
                                  [&](const AudioDeviceInfo& device) {
                                    return device.id == device_id;
                                  });
  if (match == devices.end()) {
    return std::nullopt;
  }
  return *match;
}

}  // namespace pctv
