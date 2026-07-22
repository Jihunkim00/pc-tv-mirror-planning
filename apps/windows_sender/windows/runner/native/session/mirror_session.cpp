#include "native/session/mirror_session.h"

#include "native/display/display_enumerator.h"

#include <winrt/base.h>

namespace pctv {

NativeSnapshot MirrorSession::Start(const StartSessionOptions& options) {
  Stop();

  if (options.request_json.empty()) {
    return {"failed",
            "Could not start the native sender.",
            false,
            false,
            false,
            false,
            "INVALID_MESSAGE",
            "requestJson is required"};
  }

  if (!FindMonitorById(options.source_id).has_value()) {
    return {"failed",
            "The selected monitor is no longer available.",
            false,
            false,
            false,
            false,
            "CAPTURE_SOURCE_GONE",
            "No HMONITOR matched sourceId " + options.source_id};
  }

  const auto signal =
      transport_.Connect(options.receiver_host, options.receiver_port,
                         options.request_json);
  if (!signal.ok) {
    return {"failed",
            "Could not reach the TV receiver.",
            false,
            false,
            false,
            false,
            "SIGNALING_FAILED",
            signal.detail};
  }

  const auto config_packet = BuildH264CodecConfigPacket(0);
  const auto config_result = transport_.SendPacket(config_packet);
  if (!config_result.ok) {
    transport_.Close();
    return {"failed",
            "Could not send the H.264 stream configuration.",
            false,
            false,
            true,
            false,
            "SIGNALING_FAILED",
            config_result.detail};
  }

  std::string error;
  auto capture = std::make_unique<DisplayCapture>();
  if (!capture->Start(options.source_id, &error)) {
    transport_.Close();
    return {"failed",
            "Could not start Windows screen capture.",
            false,
            false,
            true,
            false,
            "CAPTURE_PERMISSION_DENIED",
            error};
  }

  if (!encoder_.Start(&error)) {
    capture->Stop();
    transport_.Close();
    return {"failed",
            "Could not start the H.264 encoder.",
            true,
            false,
            true,
            false,
            "ENCODER_NOT_AVAILABLE",
            error};
  }

  packet_queue_.Reset();
  next_sequence_ = 1;
  running_ = true;
  {
    std::scoped_lock lock(mutex_);
    last_source_id_ = options.source_id;
    capture_ = std::move(capture);
  }

  encode_thread_ = std::thread([this]() { EncodeLoop(); });
  send_thread_ = std::thread([this]() { SendLoop(); });

  return {"streaming",
          "Native 1280x720 H.264 video path is running.",
          true,
          true,
          true,
          true,
          {},
          "Receiver response: " + signal.detail};
}

NativeSnapshot MirrorSession::Stop() {
  running_ = false;
  packet_queue_.Close();
  if (encode_thread_.joinable()) {
    encode_thread_.join();
  }
  if (send_thread_.joinable()) {
    send_thread_.join();
  }

  {
    std::scoped_lock lock(mutex_);
    last_source_id_.clear();
    if (capture_) {
      capture_->Stop();
      capture_.reset();
    }
  }
  encoder_.Stop();
  transport_.Close();

  return {"idle",
          "Native sender resources were released.",
          false,
          false,
          false,
          false,
          {},
          {}};
}

void MirrorSession::EncodeLoop() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }

  while (running_) {
    DisplayCapture* capture = nullptr;
    {
      std::scoped_lock lock(mutex_);
      capture = capture_.get();
    }
    if (capture == nullptr) {
      break;
    }

    std::string error;
    Nv12Frame frame;
    if (!capture->CaptureNext(&frame, 500, &error)) {
      if (!error.empty()) {
        running_ = false;
      }
      continue;
    }

    std::vector<EncodedAccessUnit> access_units;
    if (!encoder_.Encode(frame, &access_units, &error)) {
      running_ = false;
      break;
    }

    for (const auto& access_unit : access_units) {
      if (access_unit.annex_b.empty()) {
        continue;
      }
      const auto sequence = next_sequence_.fetch_add(1);
      packet_queue_.PushDropOldest(BuildAccessUnitPacket(
          sequence, access_unit.pts_us, access_unit.key_frame,
          access_unit.annex_b.data(),
          static_cast<std::uint32_t>(access_unit.annex_b.size())));
    }
  }
  packet_queue_.Close();
}

void MirrorSession::SendLoop() {
  std::vector<std::uint8_t> packet;
  while (running_ && packet_queue_.Pop(&packet)) {
    const auto result = transport_.SendPacket(packet);
    if (!result.ok) {
      running_ = false;
      packet_queue_.Close();
      break;
    }
  }
}

}  // namespace pctv
