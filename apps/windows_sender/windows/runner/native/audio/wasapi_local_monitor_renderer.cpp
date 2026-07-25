#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "native/audio/wasapi_local_monitor_renderer.h"

#include "native/audio/audio_device_enumerator.h"

#include <mmreg.h>
#include <propkeydef.h>
#include <functiondiscoverykeys_devpkey.h>
#include <propvarutil.h>

#include <algorithm>
#include <cmath>
#include <sstream>

namespace pctv {
namespace {

constexpr std::size_t kMaxMonitorQueueDepth = 4;

std::string HResultText(const char* operation, HRESULT hr) {
  std::ostringstream stream;
  stream << operation << " failed with HRESULT 0x" << std::hex << hr;
  return stream.str();
}

std::string FormatDescription(const WAVEFORMATEX* format) {
  if (format == nullptr) {
    return {};
  }
  std::ostringstream stream;
  stream << format->nSamplesPerSec << " Hz " << format->nChannels << " ch ";
  WORD tag = format->wFormatTag;
  if (tag == WAVE_FORMAT_EXTENSIBLE) {
    const auto* extensible =
        reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
    if (extensible->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) {
      tag = WAVE_FORMAT_IEEE_FLOAT;
    } else if (extensible->SubFormat == KSDATAFORMAT_SUBTYPE_PCM) {
      tag = WAVE_FORMAT_PCM;
    }
  }
  stream << (tag == WAVE_FORMAT_IEEE_FLOAT ? "float" : "pcm")
         << format->wBitsPerSample;
  return stream.str();
}

std::string ReadDeviceName(IMMDevice* device) {
  winrt::com_ptr<IPropertyStore> properties;
  if (FAILED(device->OpenPropertyStore(STGM_READ, properties.put()))) {
    return "PC speaker output";
  }
  PROPVARIANT name;
  PropVariantInit(&name);
  std::string result;
  if (SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &name)) &&
      name.vt == VT_LPWSTR) {
    result = WideToUtf8(name.pwszVal);
  }
  PropVariantClear(&name);
  return result.empty() ? "PC speaker output" : result;
}

std::int32_t ClampS32(float value) {
  value = std::clamp(value, -1.0f, 1.0f);
  return static_cast<std::int32_t>(std::lrint(value * 2147483647.0f));
}

std::int16_t ClampS16(float value) {
  value = std::clamp(value, -1.0f, 1.0f);
  return static_cast<std::int16_t>(std::lrint(value * 32767.0f));
}

}  // namespace

WasapiLocalMonitorRenderer::WasapiLocalMonitorRenderer() = default;

WasapiLocalMonitorRenderer::~WasapiLocalMonitorRenderer() {
  Stop();
}

bool WasapiLocalMonitorRenderer::Start(const std::string& device_id,
                                       std::string* error) {
  Stop();
  if (device_id.empty()) {
    *error = "PC speaker output is not selected";
    return false;
  }

  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }

  winrt::com_ptr<IMMDeviceEnumerator> enumerator;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(enumerator.put()));
  if (FAILED(hr)) {
    *error = HResultText("CoCreateInstance(MMDeviceEnumerator)", hr);
    return false;
  }

  const auto wide_id = Utf8ToWide(device_id);
  hr = enumerator->GetDevice(wide_id.c_str(), device_.put());
  if (FAILED(hr)) {
    *error = HResultText("IMMDeviceEnumerator::GetDevice(monitor)", hr);
    return false;
  }
  device_name_ = ReadDeviceName(device_.get());

  hr = device_->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                         audio_client_.put_void());
  if (FAILED(hr)) {
    *error = HResultText("IAudioClient activation(monitor)", hr);
    return false;
  }
  hr = audio_client_->GetMixFormat(&mix_format_);
  if (FAILED(hr) || mix_format_ == nullptr) {
    *error = FAILED(hr) ? HResultText("IAudioClient::GetMixFormat(monitor)", hr)
                        : "IAudioClient::GetMixFormat(monitor) returned null";
    return false;
  }
  format_description_ = FormatDescription(mix_format_);

  constexpr REFERENCE_TIME kBufferDuration100Ns = 1'000'000;  // 100ms.
  hr = audio_client_->Initialize(AUDCLNT_SHAREMODE_SHARED, 0,
                                 kBufferDuration100Ns, 0, mix_format_,
                                 nullptr);
  if (FAILED(hr)) {
    *error = HResultText("IAudioClient::Initialize(monitor)", hr);
    return false;
  }
  hr = audio_client_->GetBufferSize(&endpoint_buffer_frames_);
  if (FAILED(hr)) {
    *error = HResultText("IAudioClient::GetBufferSize(monitor)", hr);
    return false;
  }
  hr = audio_client_->GetService(IID_PPV_ARGS(render_client_.put()));
  if (FAILED(hr)) {
    *error = HResultText("IAudioClient::GetService(IAudioRenderClient)", hr);
    return false;
  }
  hr = audio_client_->Start();
  if (FAILED(hr)) {
    *error = HResultText("IAudioClient::Start(monitor)", hr);
    return false;
  }

  running_.store(true);
  active_.store(true);
  muted_.store(false);
  last_error_.clear();
  render_thread_ = std::thread([this]() { RenderLoop(); });
  return true;
}

bool WasapiLocalMonitorRenderer::Enqueue(const PcmAudioFrame& frame) {
  if (!running_.load() || !active_.load()) {
    return false;
  }
  if (muted_.load()) {
    return true;
  }

  {
    std::scoped_lock lock(mutex_);
    while (queue_.size() >= kMaxMonitorQueueDepth) {
      queue_.pop_front();
      dropped_buffers_.fetch_add(1);
    }
    queue_.push_back(frame);
  }
  queue_available_.notify_one();
  return true;
}

void WasapiLocalMonitorRenderer::SetMuted(bool muted) {
  muted_.store(muted);
  if (muted) {
    std::scoped_lock lock(mutex_);
    dropped_buffers_.fetch_add(static_cast<std::uint64_t>(queue_.size()));
    queue_.clear();
  }
  queue_available_.notify_all();
}

void WasapiLocalMonitorRenderer::Stop() {
  running_.store(false);
  active_.store(false);
  queue_available_.notify_all();
  if (render_thread_.joinable()) {
    render_thread_.join();
  }
  if (audio_client_) {
    audio_client_->Stop();
  }
  {
    std::scoped_lock lock(mutex_);
    queue_.clear();
  }
  render_client_ = nullptr;
  audio_client_ = nullptr;
  device_ = nullptr;
  endpoint_buffer_frames_ = 0;
  if (mix_format_ != nullptr) {
    CoTaskMemFree(mix_format_);
    mix_format_ = nullptr;
  }
  device_name_.clear();
  format_description_.clear();
}

int WasapiLocalMonitorRenderer::queue_depth() const {
  std::scoped_lock lock(mutex_);
  return static_cast<int>(queue_.size());
}

void WasapiLocalMonitorRenderer::RenderLoop() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }

  while (running_.load()) {
    PcmAudioFrame frame;
    {
      std::unique_lock lock(mutex_);
      queue_available_.wait(lock, [&]() {
        return !running_.load() || muted_.load() || !queue_.empty();
      });
      if (!running_.load()) {
        break;
      }
      if (muted_.load()) {
        queue_.clear();
        continue;
      }
      if (queue_.empty()) {
        continue;
      }
      frame = std::move(queue_.front());
      queue_.pop_front();
    }

    std::string error;
    if (!WriteFrame(frame, &error)) {
      last_error_ = error;
      dropped_buffers_.fetch_add(1);
      Sleep(5);
    }
  }
}

bool WasapiLocalMonitorRenderer::WriteFrame(const PcmAudioFrame& frame,
                                            std::string* error) {
  if (!audio_client_ || !render_client_ || mix_format_ == nullptr ||
      frame.frame_count == 0 || frame.sample_rate <= 0) {
    *error = "local monitor renderer is not initialized";
    return false;
  }

  const UINT32 render_frames = std::max<UINT32>(
      1, static_cast<UINT32>((static_cast<std::uint64_t>(frame.frame_count) *
                              mix_format_->nSamplesPerSec) /
                             static_cast<std::uint64_t>(frame.sample_rate)));
  UINT32 rendered = 0;
  while (rendered < render_frames && running_.load() && !muted_.load()) {
    UINT32 padding = 0;
    HRESULT hr = audio_client_->GetCurrentPadding(&padding);
    if (FAILED(hr)) {
      *error = HResultText("IAudioClient::GetCurrentPadding(monitor)", hr);
      return false;
    }
    const UINT32 available =
        endpoint_buffer_frames_ > padding ? endpoint_buffer_frames_ - padding
                                          : 0;
    if (available == 0) {
      Sleep(2);
      continue;
    }

    const UINT32 count = std::min(available, render_frames - rendered);
    BYTE* destination = nullptr;
    hr = render_client_->GetBuffer(count, &destination);
    if (FAILED(hr)) {
      *error = HResultText("IAudioRenderClient::GetBuffer", hr);
      return false;
    }
    FillRenderBuffer(destination, count, rendered, render_frames, frame);
    hr = render_client_->ReleaseBuffer(count, 0);
    if (FAILED(hr)) {
      *error = HResultText("IAudioRenderClient::ReleaseBuffer", hr);
      return false;
    }
    rendered += count;
  }
  return true;
}

void WasapiLocalMonitorRenderer::FillRenderBuffer(
    BYTE* destination,
    UINT32 frame_count,
    UINT32 render_frame_offset,
    UINT32 total_render_frames,
    const PcmAudioFrame& source) {
  const int output_channels = static_cast<int>(mix_format_->nChannels);
  for (UINT32 frame_index = 0; frame_index < frame_count; ++frame_index) {
    const UINT32 absolute_output = render_frame_offset + frame_index;
    const UINT32 source_frame = std::min<UINT32>(
        source.frame_count - 1,
        static_cast<UINT32>((static_cast<std::uint64_t>(absolute_output) *
                             source.frame_count) /
                            total_render_frames));
    for (int channel = 0; channel < output_channels; ++channel) {
      const float value = channel < 2 ? ReadSourceSample(source, source_frame,
                                                        channel)
                                      : 0.0f;
      WriteOutputSample(destination, frame_index, channel, value);
    }
  }
}

float WasapiLocalMonitorRenderer::ReadSourceSample(
    const PcmAudioFrame& source,
    UINT32 source_frame,
    int channel) const {
  if (source.pcm_s16le.empty() || source.channels <= 0) {
    return 0.0f;
  }
  const int safe_channel = std::clamp(channel, 0, source.channels - 1);
  const auto* samples =
      reinterpret_cast<const std::int16_t*>(source.pcm_s16le.data());
  const auto sample_index =
      static_cast<std::size_t>(source_frame) * source.channels + safe_channel;
  return static_cast<float>(samples[sample_index]) / 32768.0f;
}

void WasapiLocalMonitorRenderer::WriteOutputSample(BYTE* destination,
                                                   UINT32 output_frame,
                                                   int channel,
                                                   float value) const {
  WORD tag = mix_format_->wFormatTag;
  if (tag == WAVE_FORMAT_EXTENSIBLE) {
    const auto* extensible =
        reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(mix_format_);
    if (extensible->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) {
      tag = WAVE_FORMAT_IEEE_FLOAT;
    } else if (extensible->SubFormat == KSDATAFORMAT_SUBTYPE_PCM) {
      tag = WAVE_FORMAT_PCM;
    }
  }
  const int bytes_per_sample = mix_format_->wBitsPerSample / 8;
  BYTE* sample = destination + output_frame * mix_format_->nBlockAlign +
                 channel * bytes_per_sample;
  if (tag == WAVE_FORMAT_IEEE_FLOAT && mix_format_->wBitsPerSample == 32) {
    *reinterpret_cast<float*>(sample) = std::clamp(value, -1.0f, 1.0f);
    return;
  }
  if (tag == WAVE_FORMAT_PCM && mix_format_->wBitsPerSample == 16) {
    *reinterpret_cast<std::int16_t*>(sample) = ClampS16(value);
    return;
  }
  if (tag == WAVE_FORMAT_PCM && mix_format_->wBitsPerSample == 24) {
    const auto scaled = ClampS32(value) >> 8;
    sample[0] = static_cast<BYTE>(scaled & 0xFF);
    sample[1] = static_cast<BYTE>((scaled >> 8) & 0xFF);
    sample[2] = static_cast<BYTE>((scaled >> 16) & 0xFF);
    return;
  }
  if (tag == WAVE_FORMAT_PCM && mix_format_->wBitsPerSample == 32) {
    *reinterpret_cast<std::int32_t*>(sample) = ClampS32(value);
    return;
  }
  std::fill(sample, sample + bytes_per_sample, static_cast<BYTE>(0));
}

}  // namespace pctv
