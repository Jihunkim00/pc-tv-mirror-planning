#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "native/capture/display_capture.h"

#include "native/display/display_enumerator.h"

#include <dxgi.h>
#include <roapi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <algorithm>
#include <chrono>
#include <sstream>
#include <utility>
#include <vector>

namespace pctv {
namespace {

constexpr std::uint64_t kTimingRollingWindowUs = 5'000'000;

std::string HResultText(const char* operation, HRESULT hr) {
  std::ostringstream stream;
  stream << operation << " failed with HRESULT 0x" << std::hex << hr;
  return stream.str();
}

std::uint8_t ClampByte(int value) {
  return static_cast<std::uint8_t>(std::clamp(value, 0, 255));
}

#if defined(_DEBUG)
constexpr std::size_t kNv12GuardBytes = 32;
constexpr std::uint8_t kNv12GuardValue = 0xA5;
#endif

struct BgraYuv {
  std::uint8_t y;
  std::uint8_t u;
  std::uint8_t v;
};

std::uint8_t BgraToY(const std::uint8_t* bgra) {
  const int b = bgra[0];
  const int g = bgra[1];
  const int r = bgra[2];
  return ClampByte(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
}

std::uint8_t BgraToU(const std::uint8_t* bgra) {
  const int b = bgra[0];
  const int g = bgra[1];
  const int r = bgra[2];
  return ClampByte(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
}
std::optional<std::uint64_t> SystemRelativeTimeNs(
    const winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame& frame) {
  try {
    const auto time = frame.SystemRelativeTime();
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(time).count());
  } catch (...) {
    return std::nullopt;
  }
}

std::uint8_t BgraToV(const std::uint8_t* bgra) {
  const int b = bgra[0];
  const int g = bgra[1];
  const int r = bgra[2];
  return ClampByte(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
}

BgraYuv ConvertBgraToYuv(const std::uint8_t* bgra) {
  return {BgraToY(bgra), BgraToU(bgra), BgraToV(bgra)};
}

void TrimEvents(std::deque<std::uint64_t>* events, std::uint64_t now_us) {
  const auto cutoff =
      now_us > kTimingRollingWindowUs ? now_us - kTimingRollingWindowUs : 0;
  while (!events->empty() && events->front() < cutoff) {
    events->pop_front();
  }
}

void RecordEvent(std::deque<std::uint64_t>* events, std::uint64_t now_us) {
  events->push_back(now_us);
  TrimEvents(events, now_us);
}

double RollingFps(std::deque<std::uint64_t>* events, std::uint64_t now_us) {
  TrimEvents(events, now_us);
  if (events->size() < 2) {
    return 0.0;
  }
  const auto span_us = events->back() - events->front();
  return span_us == 0
             ? 0.0
             : static_cast<double>(events->size() - 1) * 1'000'000.0 /
                   static_cast<double>(span_us);
}

std::vector<double> IntervalsMs(std::deque<std::uint64_t>* events,
                                std::uint64_t now_us) {
  TrimEvents(events, now_us);
  std::vector<double> intervals;
  if (events->size() < 2) {
    return intervals;
  }
  intervals.reserve(events->size() - 1);
  for (std::size_t index = 1; index < events->size(); ++index) {
    intervals.push_back(
        static_cast<double>((*events)[index] - (*events)[index - 1]) / 1000.0);
  }
  return intervals;
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

double Percentile95(const std::deque<std::pair<std::uint64_t, double>>& samples) {
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

double AverageIntervals(std::deque<std::uint64_t>* events,
                        std::uint64_t now_us) {
  const auto intervals = IntervalsMs(events, now_us);
  if (intervals.empty()) {
    return 0.0;
  }
  double total = 0.0;
  for (const auto value : intervals) {
    total += value;
  }
  return total / static_cast<double>(intervals.size());
}

double Percentile95Intervals(std::deque<std::uint64_t>* events,
                             std::uint64_t now_us) {
  auto intervals = IntervalsMs(events, now_us);
  if (intervals.empty()) {
    return 0.0;
  }
  std::sort(intervals.begin(), intervals.end());
  return intervals[((intervals.size() - 1) * 95) / 100];
}

void TrimSamples(std::deque<std::pair<std::uint64_t, double>>* samples,
                 std::uint64_t now_us) {
  const auto cutoff =
      now_us > kTimingRollingWindowUs ? now_us - kTimingRollingWindowUs : 0;
  while (!samples->empty() && samples->front().first < cutoff) {
    samples->pop_front();
  }
}

std::uint64_t NowUs() {
  const auto now = std::chrono::steady_clock::now().time_since_epoch();
  return static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

}  // namespace

DisplayCapture::DisplayCapture() {
  frame_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
}

DisplayCapture::~DisplayCapture() {
  first_system_relative_time_ns_.reset();
  fallback_stream_start_us_ = NowUs();
  Stop();
  if (frame_event_ != nullptr) {
    CloseHandle(frame_event_);
    frame_event_ = nullptr;
  }
}

bool DisplayCapture::Start(const std::string& source_id,
                           int target_width,
                           int target_height,
                           std::string* error) {
  Stop();
  first_system_relative_time_ns_.reset();
  wgc_pts_valid_ = true;
  fallback_stream_start_us_ = NowUs();
  {
    std::scoped_lock lock(timing_mutex_);
    frame_arrived_events_us_.clear();
    try_get_next_frame_success_events_us_.clear();
    try_get_next_frame_null_events_us_.clear();
    frame_acquire_samples_.clear();
    copy_resource_samples_.clear();
    map_readback_samples_.clear();
    scale_samples_.clear();
    bgra_to_nv12_samples_.clear();
    source_x_offsets_.clear();
    source_y_indices_.clear();
    sampling_source_width_ = 0;
    sampling_source_height_ = 0;
  }
  if (target_width < 16 || target_height < 16 ||
      (target_width % 2) != 0 || (target_height % 2) != 0) {
    *error = "Invalid capture output size; NV12 requires even dimensions";
    return false;
  }
  target_width_ = target_width;
  target_height_ = target_height;

  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }

  using winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool;
  using winrt::Windows::Graphics::Capture::GraphicsCaptureItem;
  using winrt::Windows::Graphics::Capture::GraphicsCaptureSession;
  using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;

  if (!GraphicsCaptureSession::IsSupported()) {
    *error = "Windows.Graphics.Capture is not supported on this system";
    return false;
  }

  const auto monitor = FindMonitorById(source_id);
  if (!monitor.has_value()) {
    *error = "Selected monitor was not found";
    return false;
  }

  UINT device_flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
  D3D_FEATURE_LEVEL feature_level = D3D_FEATURE_LEVEL_11_0;
  const D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_1,
      D3D_FEATURE_LEVEL_11_0,
  };

  HRESULT hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, device_flags, feature_levels,
      ARRAYSIZE(feature_levels), D3D11_SDK_VERSION, d3d_device_.put(),
      &feature_level, d3d_context_.put());
  if (FAILED(hr)) {
    *error = HResultText("D3D11CreateDevice", hr);
    return false;
  }

  try {
    auto dxgi_device = d3d_device_.as<IDXGIDevice>();
    winrt::com_ptr<::IInspectable> inspectable;
    winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(
        dxgi_device.get(), inspectable.put()));
    interop_device_ = inspectable.as<
        winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice>();

    auto factory = winrt::get_activation_factory<
        GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    winrt::check_hresult(factory->CreateForMonitor(
        *monitor, winrt::guid_of<GraphicsCaptureItem>(),
        winrt::put_abi(item_)));

    frame_pool_ = Direct3D11CaptureFramePool::CreateFreeThreaded(
        interop_device_, DirectXPixelFormat::B8G8R8A8UIntNormalized, 1,
        item_.Size());
    frame_arrived_token_ =
        frame_pool_.FrameArrived([this](auto&&, auto&&) {
          RecordFrameArrived(NowUs());
          if (frame_event_ != nullptr) {
            SetEvent(frame_event_);
          }
        });
    session_ = frame_pool_.CreateCaptureSession(item_);
    session_.StartCapture();
  } catch (const winrt::hresult_error& failure) {
    *error = HResultText("Windows.Graphics.Capture setup", failure.code());
    Stop();
    return false;
  }

  return true;
}

bool DisplayCapture::CaptureNext(Nv12Frame* frame,
                                 int timeout_ms,
                                 std::string* error) {
  return CaptureNext(frame, timeout_ms, nullptr, error);
}

bool DisplayCapture::CaptureNext(
    Nv12Frame* frame,
    int timeout_ms,
    const std::function<bool(std::uint64_t capture_callback_us,
                             std::uint64_t source_pts_us,
                             bool source_pts_valid)>&
        should_convert,
    std::string* error) {
  if (!frame_pool_) {
    *error = "capture session is not running";
    return false;
  }

  const DWORD wait_result =
      WaitForSingleObject(frame_event_, static_cast<DWORD>(timeout_ms));
  if (wait_result == WAIT_TIMEOUT) {
    return false;
  }
  if (wait_result != WAIT_OBJECT_0) {
    *error = "waiting for WGC frame failed";
    return false;
  }
  const auto capture_callback_us = NowUs();
  ResetEvent(frame_event_);

  try {
    const auto frame_acquire_started_us = NowUs();
    auto try_get_next_frame = [this]() {
      auto result = frame_pool_.TryGetNextFrame();
      const auto now_us = NowUs();
      if (result) {
        RecordTryGetNextFrameSuccess(now_us);
      } else {
        RecordTryGetNextFrameNull(now_us);
      }
      return result;
    };
    auto capture_frame = try_get_next_frame();
    if (!capture_frame) {
      return false;
    }
    int dropped_frames = 0;
    while (true) {
      auto newer_frame = try_get_next_frame();
      if (!newer_frame) {
        break;
      }
      capture_frame.Close();
      capture_frame = std::move(newer_frame);
      ++dropped_frames;
    }
    const auto frame_acquired_us = NowUs();
    RecordDuration(&frame_acquire_samples_, frame_acquired_us,
                   static_cast<double>(frame_acquired_us -
                                       frame_acquire_started_us) /
                       1000.0);

    frame->width = target_width_;
    const auto source_time_ns = SystemRelativeTimeNs(capture_frame);
    const auto fallback_pts_us =
        capture_callback_us >= fallback_stream_start_us_
            ? capture_callback_us - fallback_stream_start_us_
            : 0;
    frame->capture_system_relative_time_ns = source_time_ns.value_or(0);
    frame->source_timestamp_delta_us = 0;
    frame->source_pts_valid = false;
    frame->video_pts_source = "legacy_stage5";
    frame->pts_us = fallback_pts_us;
    if (wgc_pts_valid_) {
      if (!source_time_ns.has_value() || *source_time_ns == 0) {
        wgc_pts_valid_ = false;
      } else if (!first_system_relative_time_ns_.has_value()) {
        first_system_relative_time_ns_ = *source_time_ns;
      } else if (*source_time_ns < *first_system_relative_time_ns_) {
        wgc_pts_valid_ = false;
      }
    }
    if (wgc_pts_valid_ && source_time_ns.has_value() &&
        first_system_relative_time_ns_.has_value() &&
        *source_time_ns >= *first_system_relative_time_ns_) {
      frame->source_timestamp_delta_us =
          (*source_time_ns - *first_system_relative_time_ns_) / 1000;
      frame->pts_us = frame->source_timestamp_delta_us;
      frame->source_pts_valid = true;
      frame->video_pts_source = "wgc_system_relative_time";
    }
    frame->height = target_height_;
    frame->capture_callback_us = capture_callback_us;
    frame->convert_started_us = capture_callback_us;
    frame->converted_us = capture_callback_us;
    frame->convert_duration_us = 0;
    frame->dropped_frames = dropped_frames;
    frame->data.clear();

    if (should_convert &&
        !should_convert(capture_callback_us, frame->pts_us,
                        frame->source_pts_valid)) {
      capture_frame.Close();
      return true;
    }

    auto surface = capture_frame.Surface();
    auto access =
        surface.as<::Windows::Graphics::DirectX::Direct3D11::
                       IDirect3DDxgiInterfaceAccess>();
    winrt::com_ptr<ID3D11Texture2D> texture;
    winrt::check_hresult(access->GetInterface(IID_PPV_ARGS(texture.put())));

    D3D11_TEXTURE2D_DESC desc{};
    texture->GetDesc(&desc);
    frame->source_texture_width = desc.Width;
    frame->source_texture_height = desc.Height;
    frame->source_texture_format =
        desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM ? "BGRA8" : "unsupported";
    if (desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM) {
      std::ostringstream stream;
      stream << "Unsupported WGC texture format 0x" << std::hex << desc.Format;
      *error = stream.str();
      return false;
    }
    if (!EnsureStagingTexture(desc.Width, desc.Height, error)) {
      return false;
    }

    const auto copy_started_us = NowUs();
    d3d_context_->CopyResource(staging_texture_.get(), texture.get());
    const auto copy_completed_us = NowUs();
    RecordDuration(&copy_resource_samples_, copy_completed_us,
                   static_cast<double>(copy_completed_us - copy_started_us) /
                       1000.0);

    D3D11_MAPPED_SUBRESOURCE mapped{};
    const auto map_started_us = NowUs();
    const HRESULT hr =
        d3d_context_->Map(staging_texture_.get(), 0, D3D11_MAP_READ, 0,
                          &mapped);
    if (FAILED(hr)) {
      *error = HResultText("ID3D11DeviceContext::Map", hr);
      return false;
    }

    const auto map_completed_us = NowUs();
    RecordDuration(&map_readback_samples_, map_completed_us,
                   static_cast<double>(map_completed_us - map_started_us) /
                       1000.0);
    const auto convert_started_us = NowUs();
    ConvertMappedBgraToNv12(mapped, desc.Width, desc.Height, frame);
    const auto converted_us = NowUs();
    d3d_context_->Unmap(staging_texture_.get(), 0);
    frame->convert_started_us = convert_started_us;
    frame->converted_us = converted_us;
    frame->convert_duration_us =
        converted_us >= convert_started_us ? converted_us - convert_started_us
                                           : 0;
    RecordDuration(&scale_samples_, converted_us,
                   static_cast<double>(frame->scale_duration_us) / 1000.0);
    RecordDuration(&bgra_to_nv12_samples_, converted_us,
                   static_cast<double>(frame->bgra_to_nv12_duration_us) /
                       1000.0);
  } catch (const winrt::hresult_error& failure) {
    *error = HResultText("WGC frame copy", failure.code());
    return false;
  }

  return true;
}

void DisplayCapture::Stop() {
  if (frame_pool_ && frame_arrived_token_.value != 0) {
    frame_pool_.FrameArrived(frame_arrived_token_);
    frame_arrived_token_ = {};
  }
  session_ = nullptr;
  frame_pool_ = nullptr;
  item_ = nullptr;
  interop_device_ = nullptr;
  staging_texture_ = nullptr;
  d3d_context_ = nullptr;
  d3d_device_ = nullptr;
  staging_width_ = 0;
  staging_height_ = 0;
  if (frame_event_ != nullptr) {
    ResetEvent(frame_event_);
  }
}

bool DisplayCapture::EnsureStagingTexture(UINT width,
                                          UINT height,
                                          std::string* error) {
  if (staging_texture_ && staging_width_ == width && staging_height_ == height) {
    return true;
  }

  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = width;
  desc.Height = height;
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_STAGING;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;

  winrt::com_ptr<ID3D11Texture2D> texture;
  const HRESULT hr = d3d_device_->CreateTexture2D(&desc, nullptr, texture.put());
  if (FAILED(hr)) {
    *error = HResultText("Create staging texture", hr);
    return false;
  }

  staging_texture_ = std::move(texture);
  staging_width_ = width;
  staging_height_ = height;
  return true;
}

void DisplayCapture::ConvertMappedBgraToNv12(
    const D3D11_MAPPED_SUBRESOURCE& mapped,
    UINT source_width,
    UINT source_height,
    Nv12Frame* frame) {
  frame->width = target_width_;
  frame->height = target_height_;
  frame->source_row_pitch = mapped.RowPitch;
  frame->source_bgra_stride = source_width * 4;
  frame->nv12_y_offset = 0;
  frame->nv12_uv_offset = target_width_ * target_height_;
  frame->nv12_y_stride = target_width_;
  frame->nv12_uv_stride = target_width_;
  frame->nv12_expected_bytes =
      static_cast<std::uint32_t>(target_width_ * target_height_ * 3 / 2);
  frame->nv12_used_bytes = frame->nv12_expected_bytes;
  frame->scale_duration_us = 0;
  frame->bgra_to_nv12_duration_us = 0;
#if defined(_DEBUG)
  const auto allocation_size =
      static_cast<std::size_t>(frame->nv12_expected_bytes) + kNv12GuardBytes;
#else
  const auto allocation_size =
      static_cast<std::size_t>(frame->nv12_expected_bytes);
#endif
  if (frame->data.size() != allocation_size) {
    frame->data.resize(allocation_size);
  }
#if defined(_DEBUG)
  std::fill(frame->data.begin() + frame->nv12_expected_bytes,
            frame->data.end(), kNv12GuardValue);
#endif
  frame->nv12_allocated_bytes = static_cast<std::uint32_t>(frame->data.size());
  frame->encoder_input_stride = frame->nv12_y_stride;
  frame->nv12_guard_corrupted = false;

  auto* y_plane = frame->data.data();
  auto* uv_plane = y_plane + target_width_ * target_height_;
  const auto* source = static_cast<const std::uint8_t*>(mapped.pData);

  const bool same_size =
      source_width == static_cast<UINT>(target_width_) &&
      source_height == static_cast<UINT>(target_height_);
  const auto scale_started_us = NowUs();
  if (!same_size &&
      (sampling_source_width_ != source_width ||
       sampling_source_height_ != source_height ||
       source_x_offsets_.size() != static_cast<std::size_t>(target_width_) ||
       source_y_indices_.size() != static_cast<std::size_t>(target_height_))) {
    source_x_offsets_.resize(static_cast<std::size_t>(target_width_));
    source_y_indices_.resize(static_cast<std::size_t>(target_height_));
    for (int x = 0; x < target_width_; ++x) {
      const auto source_x =
          static_cast<UINT>((static_cast<std::uint64_t>(x) * source_width) /
                            target_width_);
      source_x_offsets_[static_cast<std::size_t>(x)] = source_x * 4;
    }
    for (int y = 0; y < target_height_; ++y) {
      source_y_indices_[static_cast<std::size_t>(y)] =
          static_cast<UINT>((static_cast<std::uint64_t>(y) * source_height) /
                            target_height_);
    }
    sampling_source_width_ = source_width;
    sampling_source_height_ = source_height;
  }
  const auto scale_completed_us = NowUs();
  frame->scale_duration_us =
      same_size ? 0 : scale_completed_us - scale_started_us;

  const auto conversion_started_us = NowUs();
  for (int y = 0; y < target_height_; y += 2) {
    const UINT source_y0 =
        same_size ? static_cast<UINT>(y) : source_y_indices_[y];
    const UINT source_y1 =
        same_size ? static_cast<UINT>(y + 1) : source_y_indices_[y + 1];
    const auto* source_row0 = source + source_y0 * mapped.RowPitch;
    const auto* source_row1 = source + source_y1 * mapped.RowPitch;
    for (int x = 0; x < target_width_; x += 2) {
      const UINT source_x0 =
          same_size ? static_cast<UINT>(x * 4) : source_x_offsets_[x];
      const UINT source_x1 =
          same_size ? static_cast<UINT>((x + 1) * 4)
                    : source_x_offsets_[x + 1];
      const auto p00 = ConvertBgraToYuv(source_row0 + source_x0);
      const auto p01 = ConvertBgraToYuv(source_row0 + source_x1);
      const auto p10 = ConvertBgraToYuv(source_row1 + source_x0);
      const auto p11 = ConvertBgraToYuv(source_row1 + source_x1);
      const auto y_index0 = y * target_width_ + x;
      const auto y_index1 = y_index0 + 1;
      const auto y_index2 = y_index0 + target_width_;
      const auto y_index3 = y_index2 + 1;
      y_plane[y_index0] = p00.y;
      y_plane[y_index1] = p01.y;
      y_plane[y_index2] = p10.y;
      y_plane[y_index3] = p11.y;
      const int uv_index = (y / 2) * target_width_ + x;
      uv_plane[uv_index] = static_cast<std::uint8_t>(
          (static_cast<int>(p00.u) + p01.u + p10.u + p11.u) / 4);
      uv_plane[uv_index + 1] = static_cast<std::uint8_t>(
          (static_cast<int>(p00.v) + p01.v + p10.v + p11.v) / 4);
    }
  }
  frame->bgra_to_nv12_duration_us = NowUs() - conversion_started_us;
#if defined(_DEBUG)
  frame->nv12_guard_corrupted = !std::all_of(
      frame->data.begin() + frame->nv12_expected_bytes, frame->data.end(),
      [](std::uint8_t value) { return value == kNv12GuardValue; });
#endif
}

void DisplayCapture::RecordFrameArrived(std::uint64_t now_us) {
  std::scoped_lock lock(timing_mutex_);
  RecordEvent(&frame_arrived_events_us_, now_us);
}

void DisplayCapture::RecordTryGetNextFrameSuccess(std::uint64_t now_us) {
  std::scoped_lock lock(timing_mutex_);
  RecordEvent(&try_get_next_frame_success_events_us_, now_us);
}

void DisplayCapture::RecordTryGetNextFrameNull(std::uint64_t now_us) {
  std::scoped_lock lock(timing_mutex_);
  RecordEvent(&try_get_next_frame_null_events_us_, now_us);
}

void DisplayCapture::RecordDuration(
    std::deque<std::pair<std::uint64_t, double>>* samples,
    std::uint64_t now_us,
    double duration_ms) {
  std::scoped_lock lock(timing_mutex_);
  samples->push_back({now_us, duration_ms});
  TrimSamples(samples, now_us);
}

CapturePipelineTimingSnapshot DisplayCapture::timing_snapshot() const {
  std::scoped_lock lock(timing_mutex_);
  const auto now_us = NowUs();
  CapturePipelineTimingSnapshot snapshot;
  snapshot.frame_arrived_callback_fps =
      RollingFps(&frame_arrived_events_us_, now_us);
  snapshot.try_get_next_frame_success_fps =
      RollingFps(&try_get_next_frame_success_events_us_, now_us);
  TrimEvents(&try_get_next_frame_null_events_us_, now_us);
  snapshot.try_get_next_frame_null_count =
      try_get_next_frame_null_events_us_.size();
  snapshot.raw_wgc_interval_p50_ms =
      [&]() {
        auto intervals = IntervalsMs(&frame_arrived_events_us_, now_us);
        if (intervals.empty()) {
          return 0.0;
        }
        std::sort(intervals.begin(), intervals.end());
        return intervals[(intervals.size() - 1) / 2];
      }();
  snapshot.raw_wgc_interval_p95_ms =
      Percentile95Intervals(&frame_arrived_events_us_, now_us);
  TrimSamples(&frame_acquire_samples_, now_us);
  TrimSamples(&copy_resource_samples_, now_us);
  TrimSamples(&map_readback_samples_, now_us);
  TrimSamples(&scale_samples_, now_us);
  TrimSamples(&bgra_to_nv12_samples_, now_us);
  snapshot.frame_acquire_average_ms = Average(frame_acquire_samples_);
  snapshot.frame_acquire_p95_ms = Percentile95(frame_acquire_samples_);
  snapshot.copy_resource_average_ms = Average(copy_resource_samples_);
  snapshot.copy_resource_p95_ms = Percentile95(copy_resource_samples_);
  snapshot.map_readback_average_ms = Average(map_readback_samples_);
  snapshot.map_readback_p95_ms = Percentile95(map_readback_samples_);
  snapshot.scale_average_ms = Average(scale_samples_);
  snapshot.scale_p95_ms = Percentile95(scale_samples_);
  snapshot.bgra_to_nv12_average_ms = Average(bgra_to_nv12_samples_);
  snapshot.bgra_to_nv12_p95_ms = Percentile95(bgra_to_nv12_samples_);
  return snapshot;
}

}  // namespace pctv
