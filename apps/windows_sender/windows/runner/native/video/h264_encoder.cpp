#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "native/video/h264_encoder.h"

#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <wmcodecdsp.h>

#include <algorithm>
#include <sstream>

namespace pctv {
namespace {

constexpr UINT32 kWidth = 1280;
constexpr UINT32 kHeight = 720;
constexpr UINT32 kFps = 30;
constexpr UINT32 kBitrate = 4'000'000;
constexpr LONGLONG kFrameDuration100Ns = 10'000'000 / kFps;

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

bool StartsWithStartCode(const std::vector<std::uint8_t>& bytes) {
  return bytes.size() >= 4 && bytes[0] == 0 && bytes[1] == 0 &&
         (bytes[2] == 1 || (bytes[2] == 0 && bytes[3] == 1));
}

std::uint32_t ReadU32(const std::uint8_t* data) {
  return (static_cast<std::uint32_t>(data[0]) << 24) |
         (static_cast<std::uint32_t>(data[1]) << 16) |
         (static_cast<std::uint32_t>(data[2]) << 8) |
         static_cast<std::uint32_t>(data[3]);
}

void AppendStartCode(std::vector<std::uint8_t>* output) {
  output->push_back(0);
  output->push_back(0);
  output->push_back(0);
  output->push_back(1);
}

std::vector<std::uint8_t> ConvertLengthPrefixedToAnnexB(
    const std::vector<std::uint8_t>& bytes) {
  std::vector<std::uint8_t> output;
  std::size_t offset = 0;
  while (offset + 4 <= bytes.size()) {
    const std::uint32_t length = ReadU32(bytes.data() + offset);
    offset += 4;
    if (length == 0 || offset + length > bytes.size()) {
      return {};
    }
    AppendStartCode(&output);
    output.insert(output.end(), bytes.begin() + offset,
                  bytes.begin() + offset + length);
    offset += length;
  }
  if (offset != bytes.size()) {
    return {};
  }
  return output;
}

std::vector<std::uint8_t> ConvertAvccToAnnexB(
    const std::vector<std::uint8_t>& bytes) {
  if (StartsWithStartCode(bytes)) {
    return bytes;
  }
  if (bytes.size() < 7 || bytes[0] != 1) {
    return {};
  }

  std::vector<std::uint8_t> output;
  std::size_t offset = 5;
  const int sps_count = bytes[offset++] & 0x1F;
  for (int index = 0; index < sps_count; ++index) {
    if (offset + 2 > bytes.size()) {
      return {};
    }
    const std::uint16_t length =
        static_cast<std::uint16_t>((bytes[offset] << 8) | bytes[offset + 1]);
    offset += 2;
    if (offset + length > bytes.size()) {
      return {};
    }
    AppendStartCode(&output);
    output.insert(output.end(), bytes.begin() + offset,
                  bytes.begin() + offset + length);
    offset += length;
  }

  if (offset >= bytes.size()) {
    return output;
  }
  const int pps_count = bytes[offset++];
  for (int index = 0; index < pps_count; ++index) {
    if (offset + 2 > bytes.size()) {
      return {};
    }
    const std::uint16_t length =
        static_cast<std::uint16_t>((bytes[offset] << 8) | bytes[offset + 1]);
    offset += 2;
    if (offset + length > bytes.size()) {
      return {};
    }
    AppendStartCode(&output);
    output.insert(output.end(), bytes.begin() + offset,
                  bytes.begin() + offset + length);
    offset += length;
  }

  return output;
}

std::vector<std::uint8_t> BlobAttribute(IMFAttributes* attributes,
                                        const GUID& key) {
  UINT32 size = 0;
  if (FAILED(attributes->GetBlobSize(key, &size)) || size == 0) {
    return {};
  }
  std::vector<std::uint8_t> bytes(size);
  UINT32 actual_size = 0;
  if (FAILED(attributes->GetBlob(key, bytes.data(), size, &actual_size))) {
    return {};
  }
  bytes.resize(actual_size);
  return bytes;
}

}  // namespace

H264Encoder::H264Encoder() = default;

H264Encoder::~H264Encoder() {
  Stop();
}

bool H264Encoder::Start(std::string* error) {
  Stop();

  HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
  if (Failed(hr, "MFStartup", error)) {
    return false;
  }
  mf_started_ = true;

  hr = CoCreateInstance(CLSID_CMSH264EncoderMFT, nullptr, CLSCTX_INPROC_SERVER,
                        IID_PPV_ARGS(transform_.put()));
  if (Failed(hr, "CoCreateInstance(CMSH264EncoderMFT)", error)) {
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

bool H264Encoder::Encode(const Nv12Frame& frame,
                         std::vector<EncodedAccessUnit>* output,
                         std::string* error) {
  if (!transform_) {
    *error = "H.264 encoder is not running";
    return false;
  }

  winrt::com_ptr<IMFSample> sample;
  winrt::com_ptr<IMFMediaBuffer> buffer;
  HRESULT hr = MFCreateSample(sample.put());
  if (Failed(hr, "MFCreateSample", error)) {
    return false;
  }
  hr = MFCreateMemoryBuffer(static_cast<DWORD>(frame.data.size()),
                            buffer.put());
  if (Failed(hr, "MFCreateMemoryBuffer", error)) {
    return false;
  }

  BYTE* destination = nullptr;
  DWORD max_length = 0;
  DWORD current_length = 0;
  hr = buffer->Lock(&destination, &max_length, &current_length);
  if (Failed(hr, "IMFMediaBuffer::Lock", error)) {
    return false;
  }
  std::copy(frame.data.begin(), frame.data.end(), destination);
  buffer->Unlock();
  buffer->SetCurrentLength(static_cast<DWORD>(frame.data.size()));
  sample->AddBuffer(buffer.get());

  if (first_pts_us_ == 0) {
    first_pts_us_ = frame.pts_us;
  }
  const LONGLONG sample_time =
      static_cast<LONGLONG>((frame.pts_us - first_pts_us_) * 10);
  sample->SetSampleTime(sample_time);
  sample->SetSampleDuration(kFrameDuration100Ns);

  hr = transform_->ProcessInput(0, sample.get(), 0);
  if (Failed(hr, "IMFTransform::ProcessInput", error)) {
    return false;
  }

  return ReadAvailableOutput(output, error);
}

void H264Encoder::Stop() {
  if (transform_) {
    transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
    transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
    transform_ = nullptr;
  }
  sequence_header_.clear();
  first_pts_us_ = 0;
  if (mf_started_) {
    MFShutdown();
    mf_started_ = false;
  }
}

bool H264Encoder::ConfigureTypes(std::string* error) {
  winrt::com_ptr<IMFMediaType> output_type;
  HRESULT hr = MFCreateMediaType(output_type.put());
  if (Failed(hr, "MFCreateMediaType(output)", error)) {
    return false;
  }
  output_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  output_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  output_type->SetUINT32(MF_MT_AVG_BITRATE, kBitrate);
  output_type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  output_type->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Main);
  MFSetAttributeSize(output_type.get(), MF_MT_FRAME_SIZE, kWidth, kHeight);
  MFSetAttributeRatio(output_type.get(), MF_MT_FRAME_RATE, kFps, 1);
  MFSetAttributeRatio(output_type.get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  hr = transform_->SetOutputType(0, output_type.get(), 0);
  if (Failed(hr, "SetOutputType(H264)", error)) {
    return false;
  }

  winrt::com_ptr<IMFMediaType> input_type;
  hr = MFCreateMediaType(input_type.put());
  if (Failed(hr, "MFCreateMediaType(input)", error)) {
    return false;
  }
  input_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  input_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
  input_type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  MFSetAttributeSize(input_type.get(), MF_MT_FRAME_SIZE, kWidth, kHeight);
  MFSetAttributeRatio(input_type.get(), MF_MT_FRAME_RATE, kFps, 1);
  MFSetAttributeRatio(input_type.get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  hr = transform_->SetInputType(0, input_type.get(), 0);
  if (Failed(hr, "SetInputType(NV12)", error)) {
    return false;
  }

  sequence_header_ = ConvertAvccToAnnexB(
      BlobAttribute(output_type.get(), MF_MT_MPEG_SEQUENCE_HEADER));
  return true;
}

bool H264Encoder::ReadAvailableOutput(
    std::vector<EncodedAccessUnit>* output,
    std::string* error) {
  MFT_OUTPUT_STREAM_INFO stream_info{};
  HRESULT hr = transform_->GetOutputStreamInfo(0, &stream_info);
  if (Failed(hr, "GetOutputStreamInfo", error)) {
    return false;
  }

  while (true) {
    winrt::com_ptr<IMFSample> sample;
    winrt::com_ptr<IMFMediaBuffer> buffer;
    if ((stream_info.dwFlags & MFT_OUTPUT_STREAM_PROVIDES_SAMPLES) == 0) {
      hr = MFCreateSample(sample.put());
      if (Failed(hr, "MFCreateSample(output)", error)) {
        return false;
      }
      const DWORD buffer_size =
          stream_info.cbSize == 0 ? kWidth * kHeight : stream_info.cbSize;
      hr = MFCreateMemoryBuffer(buffer_size, buffer.put());
      if (Failed(hr, "MFCreateMemoryBuffer(output)", error)) {
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
      *error = HResultText("IMFTransform::ProcessOutput", hr);
      return false;
    }

    IMFSample* raw_sample = output_buffer.pSample;
    if (raw_sample == nullptr) {
      continue;
    }

    LONGLONG sample_time = 0;
    raw_sample->GetSampleTime(&sample_time);
    UINT32 clean_point = 0;
    raw_sample->GetUINT32(MFSampleExtension_CleanPoint, &clean_point);

    winrt::com_ptr<IMFMediaBuffer> contiguous;
    hr = raw_sample->ConvertToContiguousBuffer(contiguous.put());
    if (Failed(hr, "ConvertToContiguousBuffer", error)) {
      return false;
    }

    BYTE* data = nullptr;
    DWORD max_length = 0;
    DWORD current_length = 0;
    hr = contiguous->Lock(&data, &max_length, &current_length);
    if (Failed(hr, "EncodedBuffer::Lock", error)) {
      return false;
    }
    std::vector<std::uint8_t> encoded(data, data + current_length);
    contiguous->Unlock();

    auto annex_b = NormalizeAnnexB(encoded);
    const bool key_frame = clean_point != 0;
    if (key_frame && !sequence_header_.empty()) {
      std::vector<std::uint8_t> with_headers = sequence_header_;
      with_headers.insert(with_headers.end(), annex_b.begin(), annex_b.end());
      annex_b = std::move(with_headers);
    }

    output->push_back(
        {static_cast<std::uint64_t>(sample_time / 10), key_frame,
         std::move(annex_b)});

    if (output_buffer.pSample != sample.get()) {
      output_buffer.pSample->Release();
    }
  }

  return true;
}

std::vector<std::uint8_t> H264Encoder::NormalizeAnnexB(
    const std::vector<std::uint8_t>& encoded) const {
  if (StartsWithStartCode(encoded)) {
    return encoded;
  }
  auto converted = ConvertLengthPrefixedToAnnexB(encoded);
  if (!converted.empty()) {
    return converted;
  }
  converted.reserve(encoded.size() + 4);
  AppendStartCode(&converted);
  converted.insert(converted.end(), encoded.begin(), encoded.end());
  return converted;
}

}  // namespace pctv
