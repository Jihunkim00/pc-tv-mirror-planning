#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "native/audio/system_audio_loopback.h"

#include <functiondiscoverykeys_devpkey.h>
#include <mmreg.h>
#include <propvarutil.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <sstream>

namespace pctv {
namespace {

std::uint64_t NowUs() {
  const auto now = std::chrono::steady_clock::now().time_since_epoch();
  return static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

std::string HResultText(const char* operation, HRESULT hr) {
  std::ostringstream stream;
  stream << operation << " failed with HRESULT 0x" << std::hex << hr;
  return stream.str();
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

std::int16_t FloatToS16(float value) {
  value = std::clamp(value, -1.0f, 1.0f);
  return static_cast<std::int16_t>(std::lrint(value * 32767.0f));
}

}  // namespace

SystemAudioLoopback::SystemAudioLoopback() {
  capture_event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
}

SystemAudioLoopback::~SystemAudioLoopback() {
  Stop();
  if (capture_event_ != nullptr) {
    CloseHandle(capture_event_);
    capture_event_ = nullptr;
  }
}

bool SystemAudioLoopback::Start(std::string* error) {
  Stop();

  winrt::com_ptr<IMMDeviceEnumerator> enumerator;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(enumerator.put()));
  if (FAILED(hr)) {
    *error = HResultText("CoCreateInstance(MMDeviceEnumerator)", hr);
    return false;
  }

  hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, device_.put());
  if (FAILED(hr)) {
    *error = HResultText("GetDefaultAudioEndpoint(loopback render)", hr);
    return false;
  }

  winrt::com_ptr<IPropertyStore> properties;
  if (SUCCEEDED(device_->OpenPropertyStore(STGM_READ, properties.put()))) {
    PROPVARIANT name;
    PropVariantInit(&name);
    if (SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &name)) &&
        name.vt == VT_LPWSTR) {
      device_name_ = WideToUtf8(name.pwszVal);
    }
    PropVariantClear(&name);
  }
  if (device_name_.empty()) {
    device_name_ = "Default system audio";
  }

  hr = device_->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                         audio_client_.put_void());
  if (FAILED(hr)) {
    *error = HResultText("IAudioClient activation", hr);
    return false;
  }

  hr = audio_client_->GetMixFormat(&mix_format_);
  if (FAILED(hr) || mix_format_ == nullptr) {
    *error = FAILED(hr) ? HResultText("IAudioClient::GetMixFormat", hr)
                        : "IAudioClient::GetMixFormat returned null";
    return false;
  }

  input_sample_rate_ = static_cast<int>(mix_format_->nSamplesPerSec);
  input_channels_ = static_cast<int>(mix_format_->nChannels);
  input_bits_per_sample_ = static_cast<int>(mix_format_->wBitsPerSample);
  input_format_tag_ = mix_format_->wFormatTag;
  if (input_format_tag_ == WAVE_FORMAT_EXTENSIBLE) {
    const auto* extensible =
        reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(mix_format_);
    if (extensible->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) {
      input_format_tag_ = WAVE_FORMAT_IEEE_FLOAT;
    } else if (extensible->SubFormat == KSDATAFORMAT_SUBTYPE_PCM) {
      input_format_tag_ = WAVE_FORMAT_PCM;
    }
  }

  constexpr REFERENCE_TIME kBufferDuration100Ns = 1'000'000;  // 100ms.
  DWORD stream_flags =
      AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK;
  hr = audio_client_->Initialize(AUDCLNT_SHAREMODE_SHARED, stream_flags,
                                 kBufferDuration100Ns, 0, mix_format_,
                                 nullptr);
  event_driven_ = SUCCEEDED(hr);
  if (FAILED(hr)) {
    stream_flags = AUDCLNT_STREAMFLAGS_LOOPBACK;
    hr = audio_client_->Initialize(AUDCLNT_SHAREMODE_SHARED, stream_flags,
                                   kBufferDuration100Ns, 0, mix_format_,
                                   nullptr);
    if (FAILED(hr)) {
      *error = HResultText("IAudioClient::Initialize(loopback)", hr);
      return false;
    }
  }

  if (event_driven_) {
    hr = audio_client_->SetEventHandle(capture_event_);
    if (FAILED(hr)) {
      *error = HResultText("IAudioClient::SetEventHandle", hr);
      return false;
    }
  }

  hr = audio_client_->GetService(IID_PPV_ARGS(capture_client_.put()));
  if (FAILED(hr)) {
    *error = HResultText("IAudioClient::GetService(IAudioCaptureClient)", hr);
    return false;
  }

  stream_start_pts_us_ = NowUs();
  output_frame_cursor_ = 0;
  pending_pcm_.clear();
  hr = audio_client_->Start();
  if (FAILED(hr)) {
    *error = HResultText("IAudioClient::Start", hr);
    return false;
  }
  return true;
}

bool SystemAudioLoopback::CaptureNext(PcmAudioFrame* frame,
                                      int timeout_ms,
                                      std::string* error) {
  if (!capture_client_) {
    *error = "system audio loopback is not running";
    return false;
  }

  if (pending_pcm_.size() < kAudioFramesPerAccessUnit * kAudioChannels) {
    if (event_driven_) {
      const DWORD wait_result =
          WaitForSingleObject(capture_event_, static_cast<DWORD>(timeout_ms));
      if (wait_result == WAIT_TIMEOUT) {
        return false;
      }
      if (wait_result != WAIT_OBJECT_0) {
        *error = "waiting for WASAPI loopback event failed";
        return false;
      }
    } else {
      Sleep(static_cast<DWORD>(std::min(timeout_ms, 10)));
    }

    UINT32 packet_frames = 0;
    HRESULT hr = capture_client_->GetNextPacketSize(&packet_frames);
    if (FAILED(hr)) {
      *error = HResultText("IAudioCaptureClient::GetNextPacketSize", hr);
      return false;
    }
    while (packet_frames > 0) {
      BYTE* data = nullptr;
      UINT32 frames = 0;
      DWORD flags = 0;
      hr = capture_client_->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
      if (FAILED(hr)) {
        *error = HResultText("IAudioCaptureClient::GetBuffer", hr);
        return false;
      }
      AppendCapturedFrames(data, frames, flags);
      capture_client_->ReleaseBuffer(frames);
      hr = capture_client_->GetNextPacketSize(&packet_frames);
      if (FAILED(hr)) {
        *error = HResultText("IAudioCaptureClient::GetNextPacketSize", hr);
        return false;
      }
    }
  }

  const std::size_t samples_per_frame = kAudioFramesPerAccessUnit * kAudioChannels;
  if (pending_pcm_.size() < samples_per_frame) {
    return false;
  }

  frame->pcm_s16le.resize(samples_per_frame * sizeof(std::int16_t));
  auto* destination = reinterpret_cast<std::int16_t*>(frame->pcm_s16le.data());
  std::copy(pending_pcm_.begin(), pending_pcm_.begin() + samples_per_frame,
            destination);
  pending_pcm_.erase(pending_pcm_.begin(), pending_pcm_.begin() + samples_per_frame);
  frame->pts_us =
      stream_start_pts_us_ +
      (output_frame_cursor_ * 1'000'000ULL) / kAudioSampleRate;
  frame->frame_count = kAudioFramesPerAccessUnit;
  frame->sample_rate = kAudioSampleRate;
  frame->channels = kAudioChannels;
  output_frame_cursor_ += kAudioFramesPerAccessUnit;
  return true;
}

void SystemAudioLoopback::Stop() {
  if (audio_client_) {
    audio_client_->Stop();
  }
  capture_client_ = nullptr;
  audio_client_ = nullptr;
  device_ = nullptr;
  if (mix_format_ != nullptr) {
    CoTaskMemFree(mix_format_);
    mix_format_ = nullptr;
  }
  pending_pcm_.clear();
  input_sample_rate_ = 0;
  input_channels_ = 0;
  input_bits_per_sample_ = 0;
  input_format_tag_ = 0;
  event_driven_ = false;
}

void SystemAudioLoopback::AppendCapturedFrames(const BYTE* data,
                                               UINT32 frame_count,
                                               DWORD flags) {
  if (frame_count == 0 || input_sample_rate_ <= 0 || input_channels_ <= 0) {
    return;
  }
  const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr;
  const auto output_frames = static_cast<UINT32>(
      std::max<std::uint64_t>(
          1, (static_cast<std::uint64_t>(frame_count) * kAudioSampleRate) /
                 static_cast<std::uint64_t>(input_sample_rate_)));
  for (UINT32 out = 0; out < output_frames; ++out) {
    const UINT32 source_frame =
        std::min<UINT32>(frame_count - 1,
                         static_cast<UINT32>(
                             (static_cast<std::uint64_t>(out) * frame_count) /
                             output_frames));
    float left = 0.0f;
    float right = 0.0f;
    if (!silent) {
      left = ReadSourceSample(data, source_frame, 0);
      right = input_channels_ == 1 ? left : ReadSourceSample(data, source_frame, 1);
    }
    AppendStereoPcm16(left, right);
  }
}

float SystemAudioLoopback::ReadSourceSample(const BYTE* data,
                                            UINT32 frame,
                                            int channel) const {
  const int safe_channel = std::clamp(channel, 0, input_channels_ - 1);
  const BYTE* sample =
      data + frame * mix_format_->nBlockAlign +
      safe_channel * (input_bits_per_sample_ / 8);
  if (input_format_tag_ == WAVE_FORMAT_IEEE_FLOAT &&
      input_bits_per_sample_ == 32) {
    return *reinterpret_cast<const float*>(sample);
  }
  if (input_format_tag_ == WAVE_FORMAT_PCM && input_bits_per_sample_ == 16) {
    return static_cast<float>(*reinterpret_cast<const std::int16_t*>(sample)) /
           32768.0f;
  }
  if (input_format_tag_ == WAVE_FORMAT_PCM && input_bits_per_sample_ == 24) {
    const int value = (static_cast<int>(sample[0]) << 8) |
                      (static_cast<int>(sample[1]) << 16) |
                      (static_cast<int>(sample[2]) << 24);
    return static_cast<float>(value >> 8) / 8388608.0f;
  }
  if (input_format_tag_ == WAVE_FORMAT_PCM && input_bits_per_sample_ == 32) {
    return static_cast<float>(*reinterpret_cast<const std::int32_t*>(sample)) /
           2147483648.0f;
  }
  return 0.0f;
}

void SystemAudioLoopback::AppendStereoPcm16(float left, float right) {
  pending_pcm_.push_back(FloatToS16(left));
  pending_pcm_.push_back(FloatToS16(right));
}

}  // namespace pctv
