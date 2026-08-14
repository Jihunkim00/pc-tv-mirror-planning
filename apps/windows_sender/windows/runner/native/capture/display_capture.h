#ifndef RUNNER_NATIVE_CAPTURE_DISPLAY_CAPTURE_H_
#define RUNNER_NATIVE_CAPTURE_DISPLAY_CAPTURE_H_

#include "native/capture/latest_frame_handoff.h"
#include "native/video/video_types.h"

#include <d3d11.h>
#include <d3d11_4.h>
#include <windows.h>

#include <array>
#include <atomic>
#include <condition_variable>
#include <functional>
#include <deque>
#include <mutex>
#include <string>
#include <thread>

#include <cstdint>
#include <optional>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/base.h>

namespace pctv {

struct CapturePipelineTimingSnapshot {
  std::string frame_pool_api = "CreateFreeThreaded";
  int frame_pool_buffer_count = 3;
  double frame_arrived_callback_fps = 0.0;
  std::uint64_t frame_arrived_callback_enter_count = 0;
  std::uint64_t frame_arrived_callback_exit_count = 0;
  double frame_arrived_callback_average_ms = 0.0;
  double frame_arrived_callback_p95_ms = 0.0;
  double frame_arrived_callback_max_ms = 0.0;
  double try_get_next_frame_success_fps = 0.0;
  std::uint64_t try_get_next_frame_null_count = 0;
  double raw_wgc_interval_p50_ms = 0.0;
  double raw_wgc_interval_p95_ms = 0.0;
  double frame_acquire_average_ms = 0.0;
  double frame_acquire_p95_ms = 0.0;
  double frame_held_average_ms = 0.0;
  double frame_held_p95_ms = 0.0;
  double frame_held_max_ms = 0.0;
  double copy_resource_average_ms = 0.0;
  double copy_resource_p95_ms = 0.0;
  double owned_texture_copy_fps = 0.0;
  double owned_texture_copy_average_ms = 0.0;
  double owned_texture_copy_p95_ms = 0.0;
  double map_readback_average_ms = 0.0;
  double map_readback_p95_ms = 0.0;
  double scale_average_ms = 0.0;
  double scale_p95_ms = 0.0;
  double bgra_to_nv12_average_ms = 0.0;
  double bgra_to_nv12_p95_ms = 0.0;
  double worker_processing_average_ms = 0.0;
  double worker_processing_p95_ms = 0.0;
  int handoff_slots = 3;
  int handoff_in_use = 0;
  int worker_queue_depth = 0;
  std::uint64_t worker_frames_accepted = 0;
  std::uint64_t worker_frames_processed = 0;
  std::uint64_t worker_frame_replacement_count = 0;
  std::uint64_t worker_frame_drop_count = 0;
  double latest_frame_age_ms = 0.0;
  std::uint64_t capture_thread_id = 0;
  std::uint64_t conversion_thread_id = 0;
  std::uint64_t callback_overlap_count = 0;
  std::uint64_t callback_reentrant_count = 0;
  bool d3d_multithread_protection_enabled = false;
  std::string measured_delivery_bottleneck = "unknown";
};

class DisplayCapture {
 public:
  using FrameAdmissionCallback =
      std::function<bool(std::uint64_t capture_callback_us,
                         std::uint64_t source_pts_us,
                         bool source_pts_valid)>;

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
      const FrameAdmissionCallback& should_convert,
      std::string* error);
  CapturePipelineTimingSnapshot timing_snapshot() const;
  void Stop();

 private:
  static constexpr std::size_t kHandoffSlotCount = 3;
  static constexpr std::size_t kReadyFrameCapacity = 2;

  struct OwnedTextureSlot {
    winrt::com_ptr<ID3D11Texture2D> texture{nullptr};
    Nv12Frame frame;
  };

  bool EnsureStagingTexture(UINT width, UINT height, std::string* error);
  bool EnsureOwnedTexture(std::size_t slot_index,
                          const D3D11_TEXTURE2D_DESC& source_desc,
                          std::string* error);
  void StartWorkers();
  void CaptureLoop();
  void ConversionLoop();
  void HandleFrameArrived();
  void PopulateFrameMetadata(
      const winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame& frame,
      std::uint64_t capture_callback_us,
      int dropped_frames,
      Nv12Frame* output);
  void SetWorkerError(const std::string& error);
  void ConvertMappedBgraToNv12(const D3D11_MAPPED_SUBRESOURCE& mapped,
                               UINT source_width,
                               UINT source_height,
                               Nv12Frame* frame);
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
  std::mutex d3d_mutex_;
  bool d3d_multithread_protection_enabled_ = false;
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

  std::atomic_bool stop_requested_{false};
  std::atomic_int callback_active_{0};
  std::thread capture_thread_;
  std::thread conversion_thread_;
  std::mutex admission_mutex_;
  FrameAdmissionCallback admission_callback_;
  mutable std::mutex handoff_mutex_;
  std::condition_variable work_available_;
  std::condition_variable ready_available_;
  std::array<OwnedTextureSlot, kHandoffSlotCount> handoff_slots_;
  CaptureFrameSlotPool handoff_pool_{kHandoffSlotCount};
  LatestFrameHandoff<Nv12Frame> ready_frames_{kReadyFrameCapacity};
  std::string worker_error_;
  std::uint64_t latest_frame_capture_us_ = 0;

  mutable std::deque<std::uint64_t> owned_texture_copy_events_us_;
  mutable std::deque<std::pair<std::uint64_t, double>>
      frame_arrived_callback_samples_;
  mutable std::deque<std::pair<std::uint64_t, double>> frame_held_samples_;
  mutable std::deque<std::pair<std::uint64_t, double>>
      owned_texture_copy_samples_;
  mutable std::deque<std::pair<std::uint64_t, double>> worker_processing_samples_;
  std::uint64_t worker_frames_accepted_ = 0;
  std::uint64_t worker_frames_processed_ = 0;
  std::uint64_t worker_frame_replacement_count_ = 0;
  std::uint64_t worker_frame_drop_count_ = 0;
  std::uint64_t capture_thread_id_ = 0;
  std::uint64_t conversion_thread_id_ = 0;
  std::uint64_t callback_enter_count_ = 0;
  std::uint64_t callback_exit_count_ = 0;
  std::uint64_t callback_thread_id_ = 0;
  std::uint64_t callback_overlap_count_ = 0;
  std::uint64_t callback_reentrant_count_ = 0;

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
