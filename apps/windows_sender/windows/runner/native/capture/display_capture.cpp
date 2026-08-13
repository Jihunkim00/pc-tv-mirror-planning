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

namespace pctv {
namespace {

std::string HResultText(const char* operation, HRESULT hr) {
  std::ostringstream stream;
  stream << operation << " failed with HRESULT 0x" << std::hex << hr;
  return stream.str();
}

std::uint8_t ClampByte(int value) {
  return static_cast<std::uint8_t>(std::clamp(value, 0, 255));
}

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
  if (target_width < 16 || target_height < 16) {
    *error = "Invalid capture output size";
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
    const std::function<bool(std::uint64_t capture_callback_us)>&
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
    auto capture_frame = frame_pool_.TryGetNextFrame();
    if (!capture_frame) {
      return false;
    }
    int dropped_frames = 0;
    while (true) {
      auto newer_frame = frame_pool_.TryGetNextFrame();
      if (!newer_frame) {
        break;
      }
      capture_frame.Close();
      capture_frame = std::move(newer_frame);
      ++dropped_frames;
    }

    frame->width = target_width_;
    const auto source_time_ns = SystemRelativeTimeNs(capture_frame);
    const auto fallback_pts_us =
        capture_callback_us >= fallback_stream_start_us_
            ? capture_callback_us - fallback_stream_start_us_
            : 0;
    frame->capture_system_relative_time_ns = source_time_ns.value_or(0);
    frame->source_timestamp_delta_us = 0;
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
      frame->video_pts_source = "wgc_system_relative_time";
    }
    frame->height = target_height_;
    frame->capture_callback_us = capture_callback_us;
    frame->convert_started_us = capture_callback_us;
    frame->converted_us = capture_callback_us;
    frame->convert_duration_us = 0;
    frame->dropped_frames = dropped_frames;
    frame->data.clear();

    if (should_convert && !should_convert(capture_callback_us)) {
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
    if (!EnsureStagingTexture(desc.Width, desc.Height, error)) {
      return false;
    }

    d3d_context_->CopyResource(staging_texture_.get(), texture.get());

    D3D11_MAPPED_SUBRESOURCE mapped{};
    const HRESULT hr =
        d3d_context_->Map(staging_texture_.get(), 0, D3D11_MAP_READ, 0,
                          &mapped);
    if (FAILED(hr)) {
      *error = HResultText("ID3D11DeviceContext::Map", hr);
      return false;
    }

    const auto convert_started_us = NowUs();
    ConvertMappedBgraToNv12(mapped, desc.Width, desc.Height, frame);
    const auto converted_us = NowUs();
    d3d_context_->Unmap(staging_texture_.get(), 0);
    frame->convert_started_us = convert_started_us;
    frame->converted_us = converted_us;
    frame->convert_duration_us =
        converted_us >= convert_started_us ? converted_us - convert_started_us
                                           : 0;
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
  frame->data.resize(target_width_ * target_height_ * 3 / 2);

  auto* y_plane = frame->data.data();
  auto* uv_plane = y_plane + target_width_ * target_height_;
  const auto* source = static_cast<const std::uint8_t*>(mapped.pData);

  for (int y = 0; y < target_height_; ++y) {
    const UINT source_y =
        static_cast<UINT>((static_cast<std::uint64_t>(y) * source_height) /
                          target_height_);
    const auto* source_row = source + source_y * mapped.RowPitch;
    for (int x = 0; x < target_width_; ++x) {
      const UINT source_x =
          static_cast<UINT>((static_cast<std::uint64_t>(x) * source_width) /
                            target_width_);
      y_plane[y * target_width_ + x] = BgraToY(source_row + source_x * 4);
    }
  }

  for (int y = 0; y < target_height_; y += 2) {
    for (int x = 0; x < target_width_; x += 2) {
      int u_sum = 0;
      int v_sum = 0;
      for (int oy = 0; oy < 2; ++oy) {
        const UINT source_y = static_cast<UINT>(
            (static_cast<std::uint64_t>(y + oy) * source_height) /
            target_height_);
        const auto* source_row = source + source_y * mapped.RowPitch;
        for (int ox = 0; ox < 2; ++ox) {
          const UINT source_x = static_cast<UINT>(
              (static_cast<std::uint64_t>(x + ox) * source_width) /
              target_width_);
          const auto* bgra = source_row + source_x * 4;
          u_sum += BgraToU(bgra);
          v_sum += BgraToV(bgra);
        }
      }
      const int uv_index = (y / 2) * target_width_ + x;
      uv_plane[uv_index] = static_cast<std::uint8_t>(u_sum / 4);
      uv_plane[uv_index + 1] = static_cast<std::uint8_t>(v_sum / 4);
    }
  }
}

}  // namespace pctv
