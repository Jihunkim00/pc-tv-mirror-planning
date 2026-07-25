#ifndef RUNNER_NATIVE_CAPTURE_DISPLAY_CAPTURE_H_
#define RUNNER_NATIVE_CAPTURE_DISPLAY_CAPTURE_H_

#include "native/video/video_types.h"

#include <d3d11.h>
#include <windows.h>

#include <functional>
#include <string>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/base.h>

namespace pctv {

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
      const std::function<bool(std::uint64_t capture_callback_us)>&
          should_convert,
      std::string* error);
  void Stop();

 private:
  bool EnsureStagingTexture(UINT width, UINT height, std::string* error);
  void ConvertMappedBgraToNv12(const D3D11_MAPPED_SUBRESOURCE& mapped,
                               UINT source_width,
                               UINT source_height,
                               Nv12Frame* frame);

  HANDLE frame_event_ = nullptr;
  winrt::com_ptr<ID3D11Device> d3d_device_;
  winrt::com_ptr<ID3D11DeviceContext> d3d_context_;
  winrt::com_ptr<ID3D11Texture2D> staging_texture_;
  UINT staging_width_ = 0;
  UINT staging_height_ = 0;
  int target_width_ = 1280;
  int target_height_ = 720;

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
