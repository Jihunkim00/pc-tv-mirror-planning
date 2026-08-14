#ifndef RUNNER_NATIVE_CAPTURE_DISPLAY_CAPTURE_H_
#define RUNNER_NATIVE_CAPTURE_DISPLAY_CAPTURE_H_

#include "native/video/video_types.h"

#include <d3d11.h>
#include <windows.h>

#include <functional>
#include <deque>
#include <mutex>
#include <string>

#include <cstdint>
#include <optional>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/base.h>

namespace pctv {

struct CapturePipelineTimingSnapshot {
  double frame_arrived_callback_fps = 0.0;
  double try_get_next_frame_success_fps = 0.0;
  std::uint64_t try_get_next_frame_null_count = 0;
  double raw_wgc_interval_p50_ms = 0.0;
  double raw_wgc_interval_p95_ms = 0.0;
  double frame_acquire_average_ms = 0.0;
  double frame_acquire_p95_ms = 0.0;
  double copy_resource_average_ms = 0.0;
  double copy_resource_p95_ms = 0.0;
  double map_readback_average_ms = 0.0;
  double map_readback_p95_ms = 0.0;
  double scale_average_ms = 0.0;
  double scale_p95_ms = 0.0;
  double bgra_to_nv12_average_ms = 0.0;
  double bgra_to_nv12_p95_ms = 0.0;
};

class DisplayCapture {
 public:
  DisplayCapture();
  ~DisplayCapture();

  DisplayCapture(const DisplayCapture&) = delete;
  DisplayCapture& operator=(const DisplayCapture&) = delete;

  bool Start(const std::string& source_id,
             int target_width,
             int target_height,
             std::string* error);
  bool CaptureNext(Nv12Frame* frame, int timeout_ms, std::string* error);
  bool CaptureNext(
      Nv12Frame* frame,
      int timeout_ms,
      const std::function<bool(std::uint64_t capture_callback_us,
                               std::uint64_t source_pts_us,
                               bool source_pts_valid)>&
          should_convert,
      std::string* error);
  CapturePipelineTimingSnapshot timing_snapshot() const;
  void Stop();

 private:
  bool EnsureStagingTexture(UINT width, UINT height, std::string* error);
  void ConvertMappedBgraToNv12(const D3D11_MAPPED_SUBRESOURCE& mapped,
                               UINT source_width,
                               UINT source_height,
                               Nv12Frame* frame);
  void RecordFrameArrived(std::uint64_t now_us);
  void RecordTryGetNextFrameSuccess(std::uint64_t now_us);
  void RecordTryGetNextFrameNull(std::uint64_t now_us);
  void RecordDuration(std::deque<std::pair<std::uint64_t, double>>* samples,
                      std::uint64_t now_us,
                      double duration_ms);

  HANDLE frame_event_ = nullptr;
  std::optional<std::uint64_t> first_system_relative_time_ns_;
  bool wgc_pts_valid_ = true;
  std::uint64_t fallback_stream_start_us_ = 0;
  winrt::com_ptr<ID3D11Device> d3d_device_;
  winrt::com_ptr<ID3D11DeviceContext> d3d_context_;
  winrt::com_ptr<ID3D11Texture2D> staging_texture_;
  UINT staging_width_ = 0;
  UINT staging_height_ = 0;
  int target_width_ = 1280;
  int target_height_ = 720;
  mutable std::mutex timing_mutex_;
  mutable std::deque<std::uint64_t> frame_arrived_events_us_;
  mutable std::deque<std::uint64_t> try_get_next_frame_success_events_us_;
  mutable std::deque<std::uint64_t> try_get_next_frame_null_events_us_;
  mutable std::deque<std::pair<std::uint64_t, double>> frame_acquire_samples_;
  mutable std::deque<std::pair<std::uint64_t, double>> copy_resource_samples_;
  mutable std::deque<std::pair<std::uint64_t, double>> map_readback_samples_;
  mutable std::deque<std::pair<std::uint64_t, double>> scale_samples_;
  mutable std::deque<std::pair<std::uint64_t, double>> bgra_to_nv12_samples_;
  std::vector<std::uint32_t> source_x_offsets_;
  std::vector<std::uint32_t> source_y_indices_;
  UINT sampling_source_width_ = 0;
  UINT sampling_source_height_ = 0;

  winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice
      interop_device_{nullptr};
  winrt::Windows::Graphics::Capture::GraphicsCaptureItem item_{nullptr};
  winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool frame_pool_{
      nullptr};
  winrt::Windows::Graphics::Capture::GraphicsCaptureSession session_{nullptr};
  winrt::event_token frame_arrived_token_{};
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_CAPTURE_DISPLAY_CAPTURE_H_
