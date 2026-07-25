#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "native/audio/aac_encoder.h"

#include <mfapi.h>
#include <mferror.h>
#include <windows.h>
#include <wmcodecdsp.h>

#include <algorithm>
#include <sstream>

namespace pctv {
namespace {

constexpr LONGLONG kAudioFrameDuration100Ns =
    static_cast<LONGLONG>(
        (static_cast<double>(kAudioFramesPerAccessUnit) * 10'000'000.0) /
        static_cast<double>(kAudioSampleRate));

std::string HResultText(const char* operation, HRESULT hr) {
  std::ostringstream stream;
  stream << operation << " failed with HRESULT 0x" << std::hex << hr;
  return stream.str();
}

bool Failed(HRESULT hr, const char* operation, std::string* error) {
  if (SUCCEEDED(hr)) {
    return false;
  }
  *error = HResultText(operation, hr);
  return true;
}

}  // namespace

AacEncoder::AacEncoder() = default;

AacEncoder::~AacEncoder() {
  Stop();
}

bool AacEncoder::Start(std::string* error) {
  Stop();
  HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
  if (Failed(hr, "MFStartup(AAC)", error)) {
    return false;
  }
  mf_started_ = true;

  hr = CoCreateInstance(CLSID_AACMFTEncoder, nullptr, CLSCTX_INPROC_SERVER,
                        IID_PPV_ARGS(transform_.put()));
  if (Failed(hr, "CoCreateInstance(AACMFTEncoder)", error)) {
    Stop();
    return false;
  }

  if (!ConfigureTypes(error)) {
    Stop();
    return false;
  }
  transform_->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
  transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  first_pts_us_ = 0;
  return true;
}

bool AacEncoder::Encode(const PcmAudioFrame& frame,
                        std::vector<EncodedAudioAccessUnit>* output,
                        std::string* error) {
  if (!transform_) {
    *error = "AAC encoder is not running";
    return false;
  }
  if (frame.pcm_s16le.empty()) {
    return true;
  }

  winrt::com_ptr<IMFSample> sample;
  winrt::com_ptr<IMFMediaBuffer> buffer;
  HRESULT hr = MFCreateSample(sample.put());
  if (Failed(hr, "MFCreateSample(AAC input)", error)) {
    return false;
  }
  hr = MFCreateMemoryBuffer(static_cast<DWORD>(frame.pcm_s16le.size()),
                            buffer.put());
  if (Failed(hr, "MFCreateMemoryBuffer(AAC input)", error)) {
    return false;
  }
  BYTE* destination = nullptr;
  DWORD max_length = 0;
  DWORD current_length = 0;
  hr = buffer->Lock(&destination, &max_length, &current_length);
  if (Failed(hr, "AAC input buffer lock", error)) {
    return false;
  }
  std::copy(frame.pcm_s16le.begin(), frame.pcm_s16le.end(), destination);
  buffer->Unlock();
  buffer->SetCurrentLength(static_cast<DWORD>(frame.pcm_s16le.size()));
  sample->AddBuffer(buffer.get());

  if (first_pts_us_ == 0) {
    first_pts_us_ = frame.pts_us;
  }
  sample->SetSampleTime(static_cast<LONGLONG>((frame.pts_us - first_pts_us_) * 10));
  sample->SetSampleDuration(kAudioFrameDuration100Ns);

  hr = transform_->ProcessInput(0, sample.get(), 0);
  if (hr == MF_E_NOTACCEPTING) {
    if (!ReadAvailableOutput(output, error)) {
      return false;
    }
    hr = transform_->ProcessInput(0, sample.get(), 0);
    if (hr == MF_E_NOTACCEPTING) {
      return true;
    }
  }
  if (Failed(hr, "AAC IMFTransform::ProcessInput", error)) {
    return false;
  }
  return ReadAvailableOutput(output, error);
}

void AacEncoder::Stop() {
  if (transform_) {
    transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
    transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
    transform_ = nullptr;
  }
  first_pts_us_ = 0;
  if (mf_started_) {
    MFShutdown();
    mf_started_ = false;
  }
}

bool AacEncoder::ConfigureTypes(std::string* error) {
  winrt::com_ptr<IMFMediaType> output_type;
  HRESULT hr = MFCreateMediaType(output_type.put());
  if (Failed(hr, "MFCreateMediaType(AAC output)", error)) {
    return false;
  }
  output_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  output_type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
  output_type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kAudioChannels);
  output_type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kAudioSampleRate);
  output_type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  output_type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, kAudioBitrate / 8);
  output_type->SetUINT32(MF_MT_AAC_PAYLOAD_TYPE, 0);
  hr = transform_->SetOutputType(0, output_type.get(), 0);
  if (Failed(hr, "SetOutputType(AAC)", error)) {
    return false;
  }

  winrt::com_ptr<IMFMediaType> input_type;
  hr = MFCreateMediaType(input_type.put());
  if (Failed(hr, "MFCreateMediaType(AAC input)", error)) {
    return false;
  }
  input_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  input_type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  input_type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kAudioChannels);
  input_type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kAudioSampleRate);
  input_type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  input_type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT,
                        kAudioChannels * sizeof(std::int16_t));
  input_type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,
                        kAudioSampleRate * kAudioChannels *
                            sizeof(std::int16_t));
  input_type->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
  hr = transform_->SetInputType(0, input_type.get(), 0);
  if (Failed(hr, "SetInputType(AAC PCM)", error)) {
    return false;
  }
  return true;
}

bool AacEncoder::ReadAvailableOutput(
    std::vector<EncodedAudioAccessUnit>* output,
    std::string* error) {
  MFT_OUTPUT_STREAM_INFO stream_info{};
  HRESULT hr = transform_->GetOutputStreamInfo(0, &stream_info);
  if (Failed(hr, "GetOutputStreamInfo(AAC)", error)) {
    return false;
  }

  while (true) {
    winrt::com_ptr<IMFSample> sample;
    winrt::com_ptr<IMFMediaBuffer> buffer;
    if ((stream_info.dwFlags & MFT_OUTPUT_STREAM_PROVIDES_SAMPLES) == 0) {
      hr = MFCreateSample(sample.put());
      if (Failed(hr, "MFCreateSample(AAC output)", error)) {
        return false;
      }
      const DWORD buffer_size = stream_info.cbSize == 0 ? 4096 : stream_info.cbSize;
      hr = MFCreateMemoryBuffer(buffer_size, buffer.put());
      if (Failed(hr, "MFCreateMemoryBuffer(AAC output)", error)) {
        return false;
      }
      sample->AddBuffer(buffer.get());
    }

    MFT_OUTPUT_DATA_BUFFER output_buffer{};
    output_buffer.dwStreamID = 0;
    output_buffer.pSample = sample.get();
    DWORD status = 0;
    hr = transform_->ProcessOutput(0, 1, &output_buffer, &status);
    if (output_buffer.pEvents != nullptr) {
      output_buffer.pEvents->Release();
      output_buffer.pEvents = nullptr;
    }
    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
      break;
    }
    if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
      continue;
    }
    if (FAILED(hr)) {
      *error = HResultText("AAC IMFTransform::ProcessOutput", hr);
      return false;
    }

    IMFSample* raw_sample = output_buffer.pSample;
    if (raw_sample == nullptr) {
      continue;
    }
    LONGLONG sample_time = 0;
    raw_sample->GetSampleTime(&sample_time);
    winrt::com_ptr<IMFMediaBuffer> contiguous;
    hr = raw_sample->ConvertToContiguousBuffer(contiguous.put());
    if (Failed(hr, "AAC ConvertToContiguousBuffer", error)) {
      return false;
    }
    BYTE* data = nullptr;
    DWORD max_length = 0;
    DWORD current_length = 0;
    hr = contiguous->Lock(&data, &max_length, &current_length);
    if (Failed(hr, "AAC output buffer lock", error)) {
      return false;
    }
    std::vector<std::uint8_t> encoded(data, data + current_length);
    contiguous->Unlock();
    output->push_back(
        {std::move(encoded),
         first_pts_us_ + static_cast<std::uint64_t>(sample_time / 10)});
    if (output_buffer.pSample != sample.get()) {
      output_buffer.pSample->Release();
    }
  }
  return true;
}

}  // namespace pctv
