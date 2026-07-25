#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "native/video/h264_encoder.h"

#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <windows.h>
#include <wmcodecdsp.h>

#include <algorithm>
#include <chrono>
#include <sstream>

namespace pctv {
namespace {

constexpr std::uint64_t kRollingWindowUs = 5'000'000;

std::uint64_t NowUs() {
  const auto now = std::chrono::steady_clock::now().time_since_epoch();
  return static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

double UsToMs(std::uint64_t value_us) {
  return static_cast<double>(value_us) / 1000.0;
}

void TrimSamples(std::deque<std::pair<std::uint64_t, double>>* samples,
                 std::uint64_t now_us) {
  const std::uint64_t cutoff =
      now_us > kRollingWindowUs ? now_us - kRollingWindowUs : 0;
  while (!samples->empty() && samples->front().first < cutoff) {
    samples->pop_front();
  }
}

double Average(const std::deque<std::pair<std::uint64_t, double>>& samples) {
  if (samples.empty()) {
    return 0.0;
  }
  double total = 0.0;
  for (const auto& sample : samples) {
    total += sample.second;
  }
  return total / static_cast<double>(samples.size());
}

double P95(std::deque<std::pair<std::uint64_t, double>> samples) {
  if (samples.empty()) {
    return 0.0;
  }
  std::vector<double> values;
  values.reserve(samples.size());
  for (const auto& sample : samples) {
    values.push_back(sample.second);
  }
  std::sort(values.begin(), values.end());
  return values[((values.size() - 1) * 95) / 100];
}

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

std::string VideoFormatText(const char* prefix, const VideoStreamConfig& config) {
  std::ostringstream stream;
  stream << prefix << " " << config.width << "x" << config.height << "@"
         << config.fps;
  return stream.str();
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

std::size_t StartCodeLengthAt(const std::vector<std::uint8_t>& bytes,
                              std::size_t offset) {
  if (offset + 4 <= bytes.size() && bytes[offset] == 0 &&
      bytes[offset + 1] == 0 && bytes[offset + 2] == 0 &&
      bytes[offset + 3] == 1) {
    return 4;
  }
  if (offset + 3 <= bytes.size() && bytes[offset] == 0 &&
      bytes[offset + 1] == 0 && bytes[offset + 2] == 1) {
    return 3;
  }
  return 0;
}

std::size_t FindStartCode(const std::vector<std::uint8_t>& bytes,
                          std::size_t offset) {
  while (offset < bytes.size()) {
    if (StartCodeLengthAt(bytes, offset) != 0) {
      return offset;
    }
    ++offset;
  }
  return std::string::npos;
}

struct NalUnitRange {
  std::size_t payload_offset = 0;
  std::size_t end_offset = 0;
  int type = 0;
};

std::vector<NalUnitRange> FindNalUnits(
    const std::vector<std::uint8_t>& annex_b) {
  std::vector<NalUnitRange> units;
  std::size_t start = FindStartCode(annex_b, 0);
  if (start == std::string::npos) {
    if (!annex_b.empty()) {
      units.push_back({0, annex_b.size(), annex_b[0] & 0x1F});
    }
    return units;
  }

  while (start != std::string::npos) {
    const std::size_t start_code_length = StartCodeLengthAt(annex_b, start);
    const std::size_t payload_offset = start + start_code_length;
    const std::size_t next_start = FindStartCode(annex_b, payload_offset);
    const std::size_t end_offset =
        next_start == std::string::npos ? annex_b.size() : next_start;
    if (payload_offset < end_offset) {
      units.push_back(
          {payload_offset, end_offset, annex_b[payload_offset] & 0x1F});
    }
    start = next_start;
  }
  return units;
}

std::vector<std::uint8_t> CopyNalUnitWithStartCode(
    const std::vector<std::uint8_t>& annex_b,
    const NalUnitRange& range) {
  std::vector<std::uint8_t> output;
  output.reserve(4 + range.end_offset - range.payload_offset);
  AppendStartCode(&output);
  output.insert(output.end(), annex_b.begin() + range.payload_offset,
                annex_b.begin() + range.end_offset);
  return output;
}

H264ParameterSets ExtractParameterSets(
    const std::vector<std::uint8_t>& annex_b) {
  H264ParameterSets sets;
  for (const auto& unit : FindNalUnits(annex_b)) {
    if (unit.type == 7 && sets.sps.empty()) {
      sets.sps = CopyNalUnitWithStartCode(annex_b, unit);
    } else if (unit.type == 8 && sets.pps.empty()) {
      sets.pps = CopyNalUnitWithStartCode(annex_b, unit);
    }
  }
  return sets;
}

std::string NalTypesText(const std::vector<std::uint8_t>& annex_b) {
  std::ostringstream stream;
  bool first = true;
  for (const auto& unit : FindNalUnits(annex_b)) {
    if (!first) {
      stream << ",";
    }
    first = false;
    stream << unit.type;
  }
  return first ? std::string("none") : stream.str();
}

void Log(const std::string& message) {
  const std::string line = "[pc-tv-mirror] " + message + "\n";
  OutputDebugStringA(line.c_str());
}

void WarnUnsupported(HRESULT hr, const char* option) {
  std::ostringstream stream;
  stream << option << " unsupported, HRESULT 0x" << std::hex << hr;
  Log(stream.str());
}

void AppendOption(std::string* target, const std::string& option) {
  if (target == nullptr) {
    return;
  }
  if (!target->empty()) {
    *target += ", ";
  }
  *target += option;
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

void SetCodecApiBool(ICodecAPI* codec_api,
                     const GUID& key,
                     VARIANT_BOOL bool_value,
                     const char* option,
                     H264EncoderDiagnostics* diagnostics) {
  VARIANT value;
  VariantInit(&value);
  value.vt = VT_BOOL;
  value.boolVal = bool_value;
  const HRESULT hr = codec_api->SetValue(&key, &value);
  VariantClear(&value);
  if (FAILED(hr)) {
    WarnUnsupported(hr, option);
    AppendOption(&diagnostics->unsupported_encoder_options, option);
  } else {
    AppendOption(&diagnostics->low_latency_options_applied, option);
  }
}

void SetCodecApiU4(ICodecAPI* codec_api,
                   const GUID& key,
                   ULONG integer_value,
                   const char* option,
                   H264EncoderDiagnostics* diagnostics) {
  VARIANT value;
  VariantInit(&value);
  value.vt = VT_UI4;
  value.ulVal = integer_value;
  const HRESULT hr = codec_api->SetValue(&key, &value);
  VariantClear(&value);
  if (FAILED(hr)) {
    WarnUnsupported(hr, option);
    AppendOption(&diagnostics->unsupported_encoder_options, option);
  } else {
    AppendOption(&diagnostics->low_latency_options_applied, option);
  }
}

void ApplyLowLatencyOptions(IMFTransform* transform,
                            int keyframe_interval_frames,
                            H264EncoderDiagnostics* diagnostics) {
  winrt::com_ptr<IMFAttributes> attributes;
  HRESULT hr = transform->QueryInterface(IID_PPV_ARGS(attributes.put()));
  if (SUCCEEDED(hr)) {
    UINT32 d3d11_aware = FALSE;
    if (SUCCEEDED(attributes->GetUINT32(MF_SA_D3D11_AWARE, &d3d11_aware))) {
      diagnostics->encoder_d3d11_aware = d3d11_aware != FALSE;
    }
    UINT32 async_mft = FALSE;
    if (SUCCEEDED(attributes->GetUINT32(MF_TRANSFORM_ASYNC, &async_mft))) {
      diagnostics->selected_encoder_async = async_mft != FALSE;
    }
    hr = attributes->SetUINT32(MF_LOW_LATENCY, TRUE);
    if (FAILED(hr)) {
      WarnUnsupported(hr, "MF_LOW_LATENCY");
      AppendOption(&diagnostics->unsupported_encoder_options, "MF_LOW_LATENCY");
    } else {
      AppendOption(&diagnostics->low_latency_options_applied, "MF_LOW_LATENCY");
    }
  } else {
    WarnUnsupported(hr, "IMFAttributes for MF_LOW_LATENCY");
    AppendOption(&diagnostics->unsupported_encoder_options,
                 "IMFAttributes for MF_LOW_LATENCY");
  }

  winrt::com_ptr<ICodecAPI> codec_api;
  hr = transform->QueryInterface(IID_PPV_ARGS(codec_api.put()));
  if (FAILED(hr)) {
    WarnUnsupported(hr, "ICodecAPI low latency options");
    AppendOption(&diagnostics->unsupported_encoder_options,
                 "ICodecAPI low latency options");
    return;
  }

  SetCodecApiBool(codec_api.get(), CODECAPI_AVLowLatencyMode, VARIANT_TRUE,
                  "CODECAPI_AVLowLatencyMode", diagnostics);
  SetCodecApiU4(codec_api.get(), CODECAPI_AVEncMPVDefaultBPictureCount, 0,
                "CODECAPI_AVEncMPVDefaultBPictureCount", diagnostics);
  SetCodecApiU4(codec_api.get(), CODECAPI_AVEncMPVGOPSize,
                static_cast<ULONG>(std::max(1, keyframe_interval_frames)),
                "CODECAPI_AVEncMPVGOPSize", diagnostics);
  SetCodecApiU4(codec_api.get(), CODECAPI_AVEncCommonRateControlMode,
                eAVEncCommonRateControlMode_CBR,
                "CODECAPI_AVEncCommonRateControlMode", diagnostics);
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

bool H264Encoder::Start(const VideoStreamConfig& config, std::string* error) {
  Stop();
  if (config.width < 16 || config.height < 16 || config.fps <= 0 ||
      config.bitrate_kbps <= 0 || config.keyframe_interval_frames <= 0) {
    *error = "Invalid H.264 encoder video profile";
    return false;
  }
  config_ = config;
  {
    std::scoped_lock lock(diagnostics_mutex_);
    diagnostics_ = H264EncoderDiagnostics{};
    diagnostics_.encoder_input_format = VideoFormatText("NV12", config_);
    diagnostics_.encoder_output_format = VideoFormatText("H.264", config_);
    process_input_samples_.clear();
    process_output_samples_.clear();
  }
  encoder_backpressure_count_ = 0;
  encoder_backpressure_dropped_frames_ = 0;

  HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
  if (Failed(hr, "MFStartup", error)) {
    return false;
  }
  mf_started_ = true;

  std::string hardware_error;
  if (CreateHardwareEncoder(&hardware_error)) {
    ApplyLowLatencyOptions(transform_.get(), config_.keyframe_interval_frames,
                           &diagnostics_);
    if (!ConfigureTypes(error)) {
      Log("Hardware H.264 encoder rejected NV12 input; falling back: " +
          *error);
      transform_ = nullptr;
      {
        std::scoped_lock lock(diagnostics_mutex_);
        diagnostics_ = H264EncoderDiagnostics{};
        AppendOption(&diagnostics_.unsupported_encoder_options,
                     hardware_error);
      }
    }
  }

  if (!transform_) {
    if (!CreateSoftwareEncoder(error)) {
      Stop();
      return false;
    }
    ApplyLowLatencyOptions(transform_.get(), config_.keyframe_interval_frames,
                           &diagnostics_);

    if (!ConfigureTypes(error)) {
      Stop();
      return false;
    }
  }

  transform_->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
  transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  sequence_header_.clear();
  parameter_sets_ = {};
  first_pts_us_ = 0;
  force_next_key_frame_.store(true);
  return true;
}

bool H264Encoder::Encode(const Nv12Frame& frame,
                         std::vector<EncodedAccessUnit>* output,
                         bool* input_accepted,
                         bool* backpressure_dropped,
                         std::string* error) {
  if (input_accepted != nullptr) {
    *input_accepted = false;
  }
  if (backpressure_dropped != nullptr) {
    *backpressure_dropped = false;
  }
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
  sample->SetSampleDuration(10'000'000 / config_.fps);

  if (force_next_key_frame_.load() && !ForceNextKeyFrame(error)) {
    return false;
  }

  auto input_start_us = NowUs();
  hr = transform_->ProcessInput(0, sample.get(), 0);
  auto input_done_us = NowUs();
  RecordProcessInputDuration(input_done_us, UsToMs(input_done_us - input_start_us));
  {
    std::scoped_lock lock(diagnostics_mutex_);
    ++diagnostics_.process_input_calls;
  }
  if (hr == MF_E_NOTACCEPTING) {
    ++encoder_backpressure_count_;
    {
      std::scoped_lock lock(diagnostics_mutex_);
      diagnostics_.encoder_backpressure_count = encoder_backpressure_count_;
      ++diagnostics_.process_input_not_accepting;
    }
    if (!ReadAvailableOutput(output, error)) {
      return false;
    }
    {
      std::scoped_lock lock(diagnostics_mutex_);
      ++diagnostics_.process_input_retries;
    }
    input_start_us = NowUs();
    hr = transform_->ProcessInput(0, sample.get(), 0);
    input_done_us = NowUs();
    RecordProcessInputDuration(input_done_us,
                               UsToMs(input_done_us - input_start_us));
    {
      std::scoped_lock lock(diagnostics_mutex_);
      ++diagnostics_.process_input_calls;
    }
    if (hr == MF_E_NOTACCEPTING) {
      ++encoder_backpressure_dropped_frames_;
      {
        std::scoped_lock lock(diagnostics_mutex_);
        diagnostics_.encoder_backpressure_dropped_frames =
            encoder_backpressure_dropped_frames_;
        ++diagnostics_.process_input_not_accepting;
      }
      if (backpressure_dropped != nullptr) {
        *backpressure_dropped = true;
      }
      return true;
    }
  }
  if (Failed(hr, "IMFTransform::ProcessInput", error)) {
    return false;
  }
  {
    std::scoped_lock lock(diagnostics_mutex_);
    ++diagnostics_.process_input_accepted;
  }
  if (input_accepted != nullptr) {
    *input_accepted = true;
  }

  return ReadAvailableOutput(output, error);
}

void H264Encoder::RequestKeyFrame() {
  force_next_key_frame_.store(true);
}

void H264Encoder::Stop() {
  if (transform_) {
    transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
    transform_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
    transform_ = nullptr;
  }
  sequence_header_.clear();
  parameter_sets_ = {};
  first_pts_us_ = 0;
  force_next_key_frame_.store(false);
  encoder_backpressure_count_ = 0;
  encoder_backpressure_dropped_frames_ = 0;
  {
    std::scoped_lock lock(diagnostics_mutex_);
    process_input_samples_.clear();
    process_output_samples_.clear();
  }
  if (mf_started_) {
    MFShutdown();
    mf_started_ = false;
  }
}

bool H264Encoder::CreateHardwareEncoder(std::string* error) {
  MFT_REGISTER_TYPE_INFO output_info{};
  output_info.guidMajorType = MFMediaType_Video;
  output_info.guidSubtype = MFVideoFormat_H264;

  IMFActivate** activates = nullptr;
  UINT32 count = 0;
  const HRESULT hr = MFTEnumEx(
      MFT_CATEGORY_VIDEO_ENCODER,
      MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER, nullptr,
      &output_info, &activates, &count);
  if (FAILED(hr) || count == 0 || activates == nullptr) {
    if (error != nullptr) {
      *error = FAILED(hr) ? HResultText("MFTEnumEx(H.264 hardware)", hr)
                          : "No hardware H.264 encoder MFT was registered";
    }
    if (activates != nullptr) {
      CoTaskMemFree(activates);
    }
    return false;
  }

  bool created = false;
  for (UINT32 index = 0; index < count && !created; ++index) {
    IMFActivate* activate = activates[index];
    LPWSTR friendly_name = nullptr;
    UINT32 name_length = 0;
    std::string name = "Hardware H.264 encoder MFT";
    if (SUCCEEDED(activate->GetAllocatedString(
            MFT_FRIENDLY_NAME_Attribute, &friendly_name, &name_length))) {
      const auto utf8_name = WideToUtf8(friendly_name);
      if (!utf8_name.empty()) {
        name = utf8_name;
      }
      CoTaskMemFree(friendly_name);
    }

    winrt::com_ptr<IMFTransform> candidate;
    const HRESULT activate_hr =
        activate->ActivateObject(IID_PPV_ARGS(candidate.put()));
    if (SUCCEEDED(activate_hr)) {
      transform_ = std::move(candidate);
      diagnostics_.selected_encoder_name = name;
      diagnostics_.selected_encoder_hardware = true;
      created = true;
      Log("Selected hardware H.264 encoder: " + name);
    } else if (error != nullptr) {
      *error = HResultText("ActivateObject(H.264 hardware encoder)",
                           activate_hr);
    }
  }

  for (UINT32 index = 0; index < count; ++index) {
    if (activates[index] != nullptr) {
      activates[index]->Release();
    }
  }
  CoTaskMemFree(activates);
  return created;
}

bool H264Encoder::CreateSoftwareEncoder(std::string* error) {
  const HRESULT hr =
      CoCreateInstance(CLSID_CMSH264EncoderMFT, nullptr, CLSCTX_INPROC_SERVER,
                       IID_PPV_ARGS(transform_.put()));
  if (Failed(hr, "CoCreateInstance(CMSH264EncoderMFT)", error)) {
    return false;
  }
  diagnostics_.selected_encoder_name = "Microsoft H.264 Encoder MFT";
  diagnostics_.selected_encoder_hardware = false;
  Log("Selected software H.264 encoder fallback: Microsoft H.264 Encoder MFT");
  return true;
}

bool H264Encoder::ConfigureTypes(std::string* error) {
  winrt::com_ptr<IMFMediaType> output_type;
  HRESULT hr = MFCreateMediaType(output_type.put());
  if (Failed(hr, "MFCreateMediaType(output)", error)) {
    return false;
  }
  output_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  output_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  output_type->SetUINT32(MF_MT_AVG_BITRATE, config_.bitrate_kbps * 1000);
  output_type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  output_type->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Main);
  MFSetAttributeSize(output_type.get(), MF_MT_FRAME_SIZE, config_.width,
                     config_.height);
  MFSetAttributeRatio(output_type.get(), MF_MT_FRAME_RATE, config_.fps, 1);
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
  MFSetAttributeSize(input_type.get(), MF_MT_FRAME_SIZE, config_.width,
                     config_.height);
  MFSetAttributeRatio(input_type.get(), MF_MT_FRAME_RATE, config_.fps, 1);
  MFSetAttributeRatio(input_type.get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  hr = transform_->SetInputType(0, input_type.get(), 0);
  if (Failed(hr, "SetInputType(NV12)", error)) {
    return false;
  }

  return true;
}

bool H264Encoder::ForceNextKeyFrame(std::string* error) {
  winrt::com_ptr<ICodecAPI> codec_api;
  HRESULT hr = transform_->QueryInterface(IID_PPV_ARGS(codec_api.put()));
  if (FAILED(hr)) {
    WarnUnsupported(hr, "ICodecAPI force key frame");
    {
      std::scoped_lock lock(diagnostics_mutex_);
      AppendOption(&diagnostics_.unsupported_encoder_options,
                   "ICodecAPI force key frame");
    }
    force_next_key_frame_.store(false);
    return true;
  }

  VARIANT value;
  VariantInit(&value);
  value.vt = VT_UI4;
  value.ulVal = 1;
  hr = codec_api->SetValue(&CODECAPI_AVEncVideoForceKeyFrame, &value);
  VariantClear(&value);
  if (FAILED(hr)) {
    VariantInit(&value);
    value.vt = VT_BOOL;
    value.boolVal = VARIANT_TRUE;
    hr = codec_api->SetValue(&CODECAPI_AVEncVideoForceKeyFrame, &value);
    VariantClear(&value);
  }
  if (FAILED(hr)) {
    WarnUnsupported(hr, "CODECAPI_AVEncVideoForceKeyFrame");
    {
      std::scoped_lock lock(diagnostics_mutex_);
      AppendOption(&diagnostics_.unsupported_encoder_options,
                   "CODECAPI_AVEncVideoForceKeyFrame");
    }
    force_next_key_frame_.store(false);
    return true;
  }

  force_next_key_frame_.store(false);
  Log("H.264 encoder requested IDR for the next output frame");
  return true;
}

bool H264Encoder::RefreshSequenceHeaderFromCurrentType(bool require_header,
                                                       std::string* error) {
  if (parameter_sets_.complete()) {
    return true;
  }

  winrt::com_ptr<IMFMediaType> current_type;
  HRESULT hr = transform_->GetOutputCurrentType(0, current_type.put());
  if (FAILED(hr)) {
    if (require_header) {
      *error = HResultText("IMFTransform::GetOutputCurrentType", hr);
      return false;
    }
    return true;
  }

  auto sequence_header = ConvertAvccToAnnexB(
      BlobAttribute(current_type.get(), MF_MT_MPEG_SEQUENCE_HEADER));
  if (sequence_header.empty()) {
    if (require_header) {
      *error = "H.264 sequence header is unavailable before an IDR frame";
      return false;
    }
    return true;
  }

  auto sets = ExtractParameterSets(sequence_header);
  if (!sets.complete()) {
    if (require_header) {
      *error = "H.264 sequence header did not contain both SPS and PPS";
      return false;
    }
    return true;
  }

  sequence_header_ = std::move(sequence_header);
  parameter_sets_ = std::move(sets);

  std::ostringstream stream;
  stream << "H.264 SPS/PPS ready: spsBytes=" << parameter_sets_.sps.size()
         << " ppsBytes=" << parameter_sets_.pps.size()
         << " sequenceNalTypes=" << NalTypesText(sequence_header_);
  Log(stream.str());
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
          stream_info.cbSize == 0
              ? static_cast<DWORD>(config_.width * config_.height)
              : stream_info.cbSize;
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
    const auto output_start_us = NowUs();
    hr = transform_->ProcessOutput(0, 1, &output_buffer, &status);
    const auto output_done_us = NowUs();
    RecordProcessOutputDuration(output_done_us,
                                UsToMs(output_done_us - output_start_us));
    {
      std::scoped_lock lock(diagnostics_mutex_);
      ++diagnostics_.process_output_calls;
    }

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
    if (!RefreshSequenceHeaderFromCurrentType(false, error)) {
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
    if (key_frame) {
      if (!RefreshSequenceHeaderFromCurrentType(true, error)) {
        return false;
      }
      if (!parameter_sets_.complete()) {
        *error = "H.264 key frame was produced before SPS/PPS were available";
        return false;
      }
      std::vector<std::uint8_t> with_headers = sequence_header_;
      with_headers.insert(with_headers.end(), annex_b.begin(), annex_b.end());
      annex_b = std::move(with_headers);

      std::ostringstream stream;
      stream << "H.264 key frame NAL types=" << NalTypesText(annex_b);
      Log(stream.str());
    }

    const auto output_pts_us =
        first_pts_us_ + static_cast<std::uint64_t>(sample_time / 10);
    output->push_back({output_pts_us, key_frame, std::move(annex_b)});
    {
      std::scoped_lock lock(diagnostics_mutex_);
      ++diagnostics_.process_output_frames;
    }

    if (output_buffer.pSample != sample.get()) {
      output_buffer.pSample->Release();
    }
  }

  return true;
}

H264EncoderDiagnostics H264Encoder::diagnostics() const {
  std::scoped_lock lock(diagnostics_mutex_);
  return diagnostics_;
}

void H264Encoder::RecordProcessInputDuration(std::uint64_t now_us,
                                             double value_ms) {
  std::scoped_lock lock(diagnostics_mutex_);
  process_input_samples_.push_back({now_us, value_ms});
  TrimSamples(&process_input_samples_, now_us);
  diagnostics_.process_input_duration_average_ms =
      Average(process_input_samples_);
  diagnostics_.process_input_duration_p95_ms = P95(process_input_samples_);
}

void H264Encoder::RecordProcessOutputDuration(std::uint64_t now_us,
                                              double value_ms) {
  std::scoped_lock lock(diagnostics_mutex_);
  process_output_samples_.push_back({now_us, value_ms});
  TrimSamples(&process_output_samples_, now_us);
  diagnostics_.process_output_duration_average_ms =
      Average(process_output_samples_);
  diagnostics_.process_output_duration_p95_ms = P95(process_output_samples_);
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
