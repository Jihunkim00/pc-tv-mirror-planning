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
#include <cstring>
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
    worker_d3d_lock_wait_samples_.clear();
    worker_copy_resource_samples_.clear();
    worker_map_samples_.clear();
    worker_cpu_bgra_copy_samples_.clear();
    worker_bgra_to_nv12_samples_.clear();
    worker_total_samples_.clear();
    source_x_offsets_.clear();
    source_y_indices_.clear();
    sampling_source_width_ = 0;
    sampling_source_height_ = 0;
    owned_texture_copy_events_us_.clear();
    frame_arrived_callback_samples_.clear();
    frame_held_samples_.clear();
    owned_texture_copy_samples_.clear();
    worker_processing_samples_.clear();
    worker_frames_accepted_ = 0;
    worker_frames_processed_ = 0;
    worker_frame_replacement_count_ = 0;
    worker_frame_drop_count_ = 0;
    capture_thread_id_ = 0;
    conversion_thread_id_ = 0;
    callback_enter_count_ = 0;
    callback_exit_count_ = 0;
    callback_thread_id_ = 0;
    callback_overlap_count_ = 0;
    callback_reentrant_count_ = 0;
    d3d_multithread_protection_enabled_ = false;
  }
  {
    std::scoped_lock lock(handoff_mutex_);
    handoff_pool_.Reset();
    ready_frames_.Clear();
    worker_error_.clear();
    latest_frame_capture_us_ = 0;
    for (auto& slot : handoff_slots_) {
      slot.texture = nullptr;
      slot.frame = Nv12Frame{};

    }
  }
  {
    std::scoped_lock lock(admission_mutex_);
    admission_callback_ = nullptr;
  }
  stop_requested_ = false;
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
    auto multithread = d3d_context_.as<ID3D11Multithread>();
    multithread->SetMultithreadProtected(TRUE);
    d3d_multithread_protection_enabled_ = true;
  } catch (...) {
    d3d_multithread_protection_enabled_ = false;
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
        interop_device_, DirectXPixelFormat::B8G8R8A8UIntNormalized,
        static_cast<int>(kHandoffSlotCount),
        item_.Size());
    frame_arrived_token_ =
        frame_pool_.FrameArrived([this](auto&&, auto&&) {
          HandleFrameArrived();
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
  if (!frame_pool_) {
    *error = "capture session is not running";
    return false;
  }
  StartWorkers();

  std::unique_lock lock(handoff_mutex_);
  const bool ready = ready_available_.wait_for(
      lock, std::chrono::milliseconds(timeout_ms), [this]() {
        return stop_requested_.load() || ready_frames_.Size() > 0 ||
               !worker_error_.empty();
      });
  if (!ready || ready_frames_.Size() == 0) {
    if (!worker_error_.empty()) {
      *error = worker_error_;
    }
    return false;
  }
  ready_frames_.Pop(frame);
  return true;
}

bool DisplayCapture::CaptureNext(
    Nv12Frame* frame,
    int timeout_ms,
    const FrameAdmissionCallback& should_convert,
    std::string* error) {
  {
    std::scoped_lock lock(admission_mutex_);
    admission_callback_ = should_convert;
  }
  return CaptureNext(frame, timeout_ms, error);
}

void DisplayCapture::StartWorkers() {
  if (capture_thread_.joinable() || stop_requested_.load()) {
    return;
  }
  stop_requested_ = false;
  capture_thread_ = std::thread([this]() { CaptureLoop(); });
  conversion_thread_ = std::thread([this]() { ConversionLoop(); });
}

void DisplayCapture::HandleFrameArrived() {
  const auto entered_us = NowUs();
  const auto thread_id = static_cast<std::uint64_t>(GetCurrentThreadId());
  const auto active_before = callback_active_.fetch_add(1);
  {
    std::scoped_lock lock(timing_mutex_);
    RecordEvent(&frame_arrived_events_us_, entered_us);
    ++callback_enter_count_;
    if (active_before > 0) {
      ++callback_overlap_count_;
      if (callback_thread_id_ == thread_id) {
        ++callback_reentrant_count_;
      }
    }
    callback_thread_id_ = thread_id;
  }
  if (frame_event_ != nullptr) {
    SetEvent(frame_event_);
  }
  const auto exited_us = NowUs();
  RecordDuration(&frame_arrived_callback_samples_, exited_us,
                 static_cast<double>(exited_us - entered_us) / 1000.0);
  callback_active_.fetch_sub(1);
  {
    std::scoped_lock lock(timing_mutex_);
    ++callback_exit_count_;
  }
}

void DisplayCapture::CaptureLoop() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }
  {
    std::scoped_lock lock(timing_mutex_);
    capture_thread_id_ = static_cast<std::uint64_t>(GetCurrentThreadId());
  }

  while (!stop_requested_.load()) {
    const auto wait_result = WaitForSingleObject(frame_event_, 100);
    if (stop_requested_.load()) {
      break;
    }
    if (wait_result == WAIT_TIMEOUT) {
      continue;
    }
    if (wait_result != WAIT_OBJECT_0) {
      SetWorkerError("waiting for WGC frame failed");
      break;
    }
    ResetEvent(frame_event_);

    try {
      const auto acquire_started_us = NowUs();
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
        continue;
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
      const auto acquired_us = NowUs();
      RecordDuration(&frame_acquire_samples_, acquired_us,
                     static_cast<double>(acquired_us - acquire_started_us) /
                         1000.0);

      const auto capture_callback_us = acquired_us;
      Nv12Frame metadata;
      PopulateFrameMetadata(capture_frame, capture_callback_us, dropped_frames,
                            &metadata);

      FrameAdmissionCallback admission;
      {
        std::scoped_lock lock(admission_mutex_);
        admission = admission_callback_;
      }
      if (admission &&
          !admission(capture_callback_us, metadata.pts_us,
                     metadata.source_pts_valid)) {
        capture_frame.Close();
        RecordDuration(&frame_held_samples_, NowUs(),
                       static_cast<double>(NowUs() - acquired_us) / 1000.0);
        continue;
      }

      auto surface = capture_frame.Surface();
      auto access =
          surface.as<::Windows::Graphics::DirectX::Direct3D11::
                         IDirect3DDxgiInterfaceAccess>();
      winrt::com_ptr<ID3D11Texture2D> texture;
      winrt::check_hresult(access->GetInterface(IID_PPV_ARGS(texture.put())));

      D3D11_TEXTURE2D_DESC desc{};
      texture->GetDesc(&desc);
      if (desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM) {
        std::ostringstream stream;
        stream << "Unsupported WGC texture format 0x" << std::hex
               << desc.Format;
        capture_frame.Close();
        SetWorkerError(stream.str());
        break;
      }
      metadata.source_texture_width = desc.Width;
      metadata.source_texture_height = desc.Height;
      metadata.source_texture_format = "BGRA8";

      std::optional<std::size_t> slot_index;
      {
        std::scoped_lock lock(handoff_mutex_);
        slot_index = handoff_pool_.ReserveLatest();
        if (!slot_index.has_value()) {
          ++worker_frame_drop_count_;
        }
        worker_frame_replacement_count_ =
            handoff_pool_.replacement_count();
      }
      if (!slot_index.has_value()) {
        capture_frame.Close();
        RecordDuration(&frame_held_samples_, NowUs(),
                       static_cast<double>(NowUs() - acquired_us) / 1000.0);
        continue;
      }

      std::string copy_error;
      if (!EnsureOwnedTexture(*slot_index, desc, &copy_error)) {
        {
          std::scoped_lock lock(handoff_mutex_);
          handoff_pool_.Release(*slot_index);
        }
        capture_frame.Close();
        SetWorkerError(copy_error.empty()
                           ? "Could not allocate WGC handoff texture"
                           : copy_error);
        break;
      }

      const auto copy_started_us = NowUs();
      {
        std::scoped_lock lock(d3d_mutex_);
        d3d_context_->CopyResource(handoff_slots_[*slot_index].texture.get(),
                                   texture.get());
      }
      const auto copy_completed_us = NowUs();
      const auto copy_duration_ms =
          static_cast<double>(copy_completed_us - copy_started_us) / 1000.0;
      RecordDuration(&copy_resource_samples_, copy_completed_us,
                     copy_duration_ms);
      RecordDuration(&owned_texture_copy_samples_, copy_completed_us,
                     copy_duration_ms);
      {
        std::scoped_lock lock(timing_mutex_);
        owned_texture_copy_events_us_.push_back(copy_completed_us);
        TrimEvents(&owned_texture_copy_events_us_, copy_completed_us);
      }

      capture_frame.Close();
      const auto released_us = NowUs();
      RecordDuration(&frame_held_samples_, released_us,
                     static_cast<double>(released_us - acquired_us) / 1000.0);

      {
        std::scoped_lock lock(handoff_mutex_);
        handoff_slots_[*slot_index].frame = std::move(metadata);
        handoff_pool_.Publish(*slot_index);
        latest_frame_capture_us_ = capture_callback_us;
        ++worker_frames_accepted_;
      }
      work_available_.notify_one();
    } catch (const winrt::hresult_error& failure) {
      SetWorkerError(HResultText("WGC frame acquisition", failure.code()));
      break;
    } catch (...) {
      SetWorkerError("Unexpected WGC frame acquisition failure");
      break;
    }
  }
}

void DisplayCapture::ConversionLoop() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }
  {
    std::scoped_lock lock(timing_mutex_);
    conversion_thread_id_ = static_cast<std::uint64_t>(GetCurrentThreadId());
  }

  std::vector<std::uint8_t> bgra_buffer;
  while (!stop_requested_.load()) {
    std::size_t slot_index = 0;
    Nv12Frame frame;
    winrt::com_ptr<ID3D11Texture2D> owned_texture;
    {
      std::unique_lock lock(handoff_mutex_);
      work_available_.wait(lock, [this]() {
        return stop_requested_.load() || handoff_pool_.queue_depth() > 0;
      });
      if (stop_requested_.load()) {
        break;
      }
      const auto pending_slot = handoff_pool_.TakePending();
      if (!pending_slot.has_value()) {
        continue;
      }
      slot_index = *pending_slot;
      frame = std::move(handoff_slots_[slot_index].frame);
      owned_texture = handoff_slots_[slot_index].texture;
    }

    const auto processing_started_us = NowUs();
    std::string error;
    if (!EnsureStagingTexture(frame.source_texture_width,
                              frame.source_texture_height, &error)) {
      {
        std::scoped_lock lock(handoff_mutex_);
        handoff_pool_.Release(slot_index);
      }
      SetWorkerError(error);
      continue;
    }

    UINT row_pitch = 0;
    double d3d_lock_wait_ms = 0.0;
    double worker_copy_resource_ms = 0.0;
    double worker_map_ms = 0.0;
    double worker_cpu_bgra_copy_ms = 0.0;
    bool map_succeeded = false;
    const auto d3d_lock_wait_started_us = NowUs();
    {
      std::unique_lock lock(d3d_mutex_);
      const auto d3d_lock_acquired_us = NowUs();
      d3d_lock_wait_ms =
          static_cast<double>(d3d_lock_acquired_us - d3d_lock_wait_started_us) /
          1000.0;
      const auto copy_started_us = d3d_lock_acquired_us;
      d3d_context_->CopyResource(staging_texture_.get(), owned_texture.get());
      const auto copy_completed_us = NowUs();
      worker_copy_resource_ms =
          static_cast<double>(copy_completed_us - copy_started_us) / 1000.0;
      D3D11_MAPPED_SUBRESOURCE mapped{};
      const auto map_started_us = NowUs();
      const HRESULT hr =
          d3d_context_->Map(staging_texture_.get(), 0, D3D11_MAP_READ, 0,
                            &mapped);
      const auto map_completed_us = NowUs();
      worker_map_ms =
          static_cast<double>(map_completed_us - map_started_us) / 1000.0;
      if (FAILED(hr)) {
        error = HResultText("ID3D11DeviceContext::Map", hr);
      } else {
        map_succeeded = true;
        row_pitch = mapped.RowPitch;
        bgra_buffer.resize(static_cast<std::size_t>(row_pitch) *
                           frame.source_texture_height);
        const auto cpu_copy_started_us = NowUs();
        auto* destination = bgra_buffer.data();
        const auto* source =
            static_cast<const std::uint8_t*>(mapped.pData);
        for (UINT y = 0; y < frame.source_texture_height; ++y) {
          std::memcpy(destination + static_cast<std::size_t>(y) * row_pitch,
                      source + static_cast<std::size_t>(y) * mapped.RowPitch,
                      mapped.RowPitch);
        }
        const auto cpu_copy_completed_us = NowUs();
        worker_cpu_bgra_copy_ms =
            static_cast<double>(cpu_copy_completed_us - cpu_copy_started_us) /
            1000.0;
        d3d_context_->Unmap(staging_texture_.get(), 0);
      }
    }
    const auto timing_recorded_us = NowUs();
    RecordDuration(&worker_d3d_lock_wait_samples_, timing_recorded_us,
                   d3d_lock_wait_ms);
    RecordDuration(&worker_copy_resource_samples_, timing_recorded_us,
                   worker_copy_resource_ms);
    if (map_succeeded) {
      RecordDuration(&map_readback_samples_, timing_recorded_us, worker_map_ms);
      RecordDuration(&worker_map_samples_, timing_recorded_us, worker_map_ms);
      RecordDuration(&worker_cpu_bgra_copy_samples_, timing_recorded_us,
                     worker_cpu_bgra_copy_ms);
    }
    if (!error.empty()) {
      {
        std::scoped_lock lock(handoff_mutex_);
        handoff_pool_.Release(slot_index);
      }
      SetWorkerError(error);
      continue;
    }

    D3D11_MAPPED_SUBRESOURCE cpu_mapped{};
    cpu_mapped.pData = bgra_buffer.data();
    cpu_mapped.RowPitch = row_pitch;
    frame.convert_started_us = NowUs();
    const auto bgra_to_nv12_started_us = frame.convert_started_us;
    ConvertMappedBgraToNv12(cpu_mapped, frame.source_texture_width,
                            frame.source_texture_height, &frame);
    frame.converted_us = NowUs();
    const auto bgra_to_nv12_duration_ms =
        static_cast<double>(frame.converted_us - bgra_to_nv12_started_us) /
        1000.0;
    RecordDuration(&bgra_to_nv12_samples_, frame.converted_us,
                   bgra_to_nv12_duration_ms);
    RecordDuration(&worker_bgra_to_nv12_samples_, frame.converted_us,
                   bgra_to_nv12_duration_ms);
    frame.convert_duration_us =
        frame.converted_us >= frame.convert_started_us
            ? frame.converted_us - frame.convert_started_us
            : 0;

    const auto processing_completed_us = NowUs();
    RecordDuration(&worker_processing_samples_, processing_completed_us,
                   static_cast<double>(processing_completed_us -
                                       processing_started_us) /
                       1000.0);
    RecordDuration(&worker_total_samples_, processing_completed_us,
                   static_cast<double>(processing_completed_us -
                                       processing_started_us) /
                       1000.0);
    {
      std::scoped_lock lock(handoff_mutex_);
      handoff_pool_.Release(slot_index);
      if (ready_frames_.Push(std::move(frame)) > 0) {
        ++worker_frame_drop_count_;
      }
      ++worker_frames_processed_;
    }
    ready_available_.notify_one();
  }
}

void DisplayCapture::PopulateFrameMetadata(
    const winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame& capture_frame,
    std::uint64_t capture_callback_us,
    int dropped_frames,
    Nv12Frame* frame) {
  frame->width = target_width_;
  frame->height = target_height_;
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
  frame->capture_callback_us = capture_callback_us;
  frame->convert_started_us = capture_callback_us;
  frame->converted_us = capture_callback_us;
  frame->convert_duration_us = 0;
  frame->dropped_frames = dropped_frames;
  frame->data.clear();
}

void DisplayCapture::SetWorkerError(const std::string& error) {
  {
    std::scoped_lock lock(handoff_mutex_);
    if (worker_error_.empty()) {
      worker_error_ = error;
    }
  }
  ready_available_.notify_all();
  work_available_.notify_all();
}

bool DisplayCapture::EnsureOwnedTexture(
    std::size_t slot_index,
    const D3D11_TEXTURE2D_DESC& source_desc,
    std::string* error) {
  auto& slot = handoff_slots_[slot_index];
  std::scoped_lock lock(d3d_mutex_);
  if (slot.texture) {
    D3D11_TEXTURE2D_DESC existing{};
    slot.texture->GetDesc(&existing);
    if (existing.Width == source_desc.Width &&
        existing.Height == source_desc.Height &&
        existing.Format == source_desc.Format) {
      return true;
    }
    slot.texture = nullptr;
  }

  D3D11_TEXTURE2D_DESC owned_desc = source_desc;
  owned_desc.Usage = D3D11_USAGE_DEFAULT;
  owned_desc.BindFlags = 0;
  owned_desc.CPUAccessFlags = 0;
  owned_desc.MiscFlags = 0;
  const HRESULT hr =
      d3d_device_->CreateTexture2D(&owned_desc, nullptr, slot.texture.put());
  if (FAILED(hr)) {
    *error = HResultText("Create WGC handoff texture", hr);
    return false;
  }
  return true;
}
void DisplayCapture::Stop() {
  stop_requested_ = true;
  if (frame_event_ != nullptr) {
    SetEvent(frame_event_);
  }
  if (frame_pool_ && frame_arrived_token_.value != 0) {
    frame_pool_.FrameArrived(frame_arrived_token_);
    frame_arrived_token_ = {};
  }
  work_available_.notify_all();
  ready_available_.notify_all();

  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
  if (conversion_thread_.joinable()) {
    conversion_thread_.join();
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
  d3d_multithread_protection_enabled_ = false;

  {
    std::scoped_lock lock(handoff_mutex_);
    handoff_pool_.Reset();
    ready_frames_.Clear();
    worker_error_.clear();
    latest_frame_capture_us_ = 0;
    for (auto& slot : handoff_slots_) {
      slot.texture = nullptr;
      slot.frame = Nv12Frame{};

    }
  }
  {
    std::scoped_lock lock(admission_mutex_);
    admission_callback_ = nullptr;
  }
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
  std::scoped_lock timing_lock(timing_mutex_);
  const auto now_us = NowUs();
  CapturePipelineTimingSnapshot snapshot;
  snapshot.frame_pool_api = "CreateFreeThreaded";
  snapshot.frame_pool_buffer_count = static_cast<int>(kHandoffSlotCount);
  snapshot.frame_arrived_callback_fps =
      RollingFps(&frame_arrived_events_us_, now_us);
  snapshot.frame_arrived_callback_enter_count = callback_enter_count_;
  snapshot.frame_arrived_callback_exit_count = callback_exit_count_;
  snapshot.frame_arrived_callback_average_ms =
      Average(frame_arrived_callback_samples_);
  snapshot.frame_arrived_callback_p95_ms =
      Percentile95(frame_arrived_callback_samples_);
  for (const auto& sample : frame_arrived_callback_samples_) {
    snapshot.frame_arrived_callback_max_ms =
        std::max(snapshot.frame_arrived_callback_max_ms, sample.second);
  }
  snapshot.try_get_next_frame_success_fps =
      RollingFps(&try_get_next_frame_success_events_us_, now_us);
  TrimEvents(&try_get_next_frame_null_events_us_, now_us);
  snapshot.try_get_next_frame_null_count =
      try_get_next_frame_null_events_us_.size();
  auto intervals = IntervalsMs(&frame_arrived_events_us_, now_us);
  if (!intervals.empty()) {
    std::sort(intervals.begin(), intervals.end());
    snapshot.raw_wgc_interval_p50_ms = intervals[(intervals.size() - 1) / 2];
    snapshot.raw_wgc_interval_p95_ms =
        intervals[((intervals.size() - 1) * 95) / 100];
  }
  TrimSamples(&frame_acquire_samples_, now_us);
  TrimSamples(&frame_held_samples_, now_us);
  TrimSamples(&copy_resource_samples_, now_us);
  TrimEvents(&owned_texture_copy_events_us_, now_us);
  TrimSamples(&owned_texture_copy_samples_, now_us);
  TrimSamples(&map_readback_samples_, now_us);
  TrimSamples(&scale_samples_, now_us);
  TrimSamples(&bgra_to_nv12_samples_, now_us);
  TrimSamples(&worker_d3d_lock_wait_samples_, now_us);
  TrimSamples(&worker_copy_resource_samples_, now_us);
  TrimSamples(&worker_map_samples_, now_us);
  TrimSamples(&worker_cpu_bgra_copy_samples_, now_us);
  TrimSamples(&worker_bgra_to_nv12_samples_, now_us);
  TrimSamples(&worker_total_samples_, now_us);
  TrimSamples(&worker_processing_samples_, now_us);
  snapshot.frame_acquire_average_ms = Average(frame_acquire_samples_);
  snapshot.frame_acquire_p95_ms = Percentile95(frame_acquire_samples_);
  snapshot.frame_held_average_ms = Average(frame_held_samples_);
  snapshot.frame_held_p95_ms = Percentile95(frame_held_samples_);
  for (const auto& sample : frame_held_samples_) {
    snapshot.frame_held_max_ms =
        std::max(snapshot.frame_held_max_ms, sample.second);
  }
  snapshot.copy_resource_average_ms = Average(copy_resource_samples_);
  snapshot.copy_resource_p95_ms = Percentile95(copy_resource_samples_);
  snapshot.owned_texture_copy_fps =
      RollingFps(&owned_texture_copy_events_us_, now_us);
  snapshot.owned_texture_copy_average_ms =
      Average(owned_texture_copy_samples_);
  snapshot.owned_texture_copy_p95_ms =
      Percentile95(owned_texture_copy_samples_);
  snapshot.map_readback_average_ms = Average(map_readback_samples_);
  snapshot.map_readback_p95_ms = Percentile95(map_readback_samples_);
  snapshot.scale_average_ms = Average(scale_samples_);
  snapshot.scale_p95_ms = Percentile95(scale_samples_);
  snapshot.bgra_to_nv12_average_ms = Average(bgra_to_nv12_samples_);
  snapshot.bgra_to_nv12_p95_ms = Percentile95(bgra_to_nv12_samples_);
  snapshot.worker_d3d_lock_wait_average_ms =
      Average(worker_d3d_lock_wait_samples_);
  snapshot.worker_d3d_lock_wait_p95_ms =
      Percentile95(worker_d3d_lock_wait_samples_);
  snapshot.worker_copy_resource_average_ms =
      Average(worker_copy_resource_samples_);
  snapshot.worker_copy_resource_p95_ms =
      Percentile95(worker_copy_resource_samples_);
  snapshot.worker_map_average_ms = Average(worker_map_samples_);
  snapshot.worker_map_p95_ms = Percentile95(worker_map_samples_);
  snapshot.worker_cpu_bgra_copy_average_ms =
      Average(worker_cpu_bgra_copy_samples_);
  snapshot.worker_cpu_bgra_copy_p95_ms =
      Percentile95(worker_cpu_bgra_copy_samples_);
  snapshot.worker_bgra_to_nv12_average_ms =
      Average(worker_bgra_to_nv12_samples_);
  snapshot.worker_bgra_to_nv12_p95_ms =
      Percentile95(worker_bgra_to_nv12_samples_);
  snapshot.worker_total_average_ms = Average(worker_total_samples_);
  snapshot.worker_total_p95_ms = Percentile95(worker_total_samples_);
  snapshot.worker_processing_average_ms =
      Average(worker_processing_samples_);
  snapshot.worker_processing_p95_ms =
      Percentile95(worker_processing_samples_);
  snapshot.capture_thread_id = capture_thread_id_;
  snapshot.conversion_thread_id = conversion_thread_id_;
  snapshot.callback_overlap_count = callback_overlap_count_;
  snapshot.callback_reentrant_count = callback_reentrant_count_;
  snapshot.d3d_multithread_protection_enabled =
      d3d_multithread_protection_enabled_;

  {
    std::scoped_lock handoff_lock(handoff_mutex_);
    snapshot.handoff_slots = static_cast<int>(handoff_slots_.size());
    snapshot.worker_queue_depth =
        static_cast<int>(handoff_pool_.queue_depth());
    snapshot.handoff_in_use =
        static_cast<int>(handoff_pool_.in_use());
    snapshot.worker_frames_accepted = worker_frames_accepted_;
    snapshot.worker_frames_processed = worker_frames_processed_;
    snapshot.worker_frame_replacement_count =
        handoff_pool_.replacement_count();
    snapshot.worker_frame_drop_count = worker_frame_drop_count_;
    if (latest_frame_capture_us_ > 0 && now_us >= latest_frame_capture_us_) {
      snapshot.latest_frame_age_ms =
          static_cast<double>(now_us - latest_frame_capture_us_) / 1000.0;
    }
  }

  if (snapshot.frame_arrived_callback_p95_ms > 5.0) {
    snapshot.measured_delivery_bottleneck = "callback_holding_frame";
  } else if (snapshot.worker_frame_drop_count > 0) {
    snapshot.measured_delivery_bottleneck = "frame_pool_exhaustion";
  } else if (snapshot.worker_processing_p95_ms > 16.67) {
    snapshot.measured_delivery_bottleneck = "worker_conversion";
  } else if (snapshot.frame_arrived_callback_fps > 0.0 &&
             snapshot.frame_arrived_callback_fps < 55.0) {
    snapshot.measured_delivery_bottleneck = "wgc_frame_delivery";
  } else if (snapshot.frame_arrived_callback_fps > 0.0) {
    snapshot.measured_delivery_bottleneck = "none";
  }

  return snapshot;
}
}  // namespace pctv
