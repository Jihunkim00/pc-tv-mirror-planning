#include "native/session/mirror_session.h"

#include "native/display/display_enumerator.h"

#include <chrono>
#include <utility>

#include <winrt/base.h>

namespace pctv {
namespace {

std::uint64_t NowUs() {
  const auto now = std::chrono::steady_clock::now().time_since_epoch();
  return static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

double UsToMs(std::uint64_t value_us) {
  return static_cast<double>(value_us) / 1000.0;
}

}  // namespace

NativeSnapshot MirrorSession::Start(const StartSessionOptions& options) {
  Stop();
  ResetCounters();

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
    std::scoped_lock status_lock(status_mutex_);
    first_access_unit_sent_ = false;
    codec_config_sent_for_stream_ = false;
    session_error_code_.clear();
    session_user_message_.clear();
    session_developer_message_ = "Receiver response: " + signal.detail;
  }
  {
    std::scoped_lock lock(mutex_);
    last_source_id_ = options.source_id;
    capture_ = std::move(capture);
  }

  encode_thread_ = std::thread([this]() { EncodeLoop(); });
  send_thread_ = std::thread([this]() { SendLoop(); });

  {
    std::unique_lock status_lock(status_mutex_);
    status_changed_.wait_for(status_lock, std::chrono::seconds(5), [this]() {
      return first_access_unit_sent_ || !session_error_code_.empty();
    });
  }

  return Snapshot();
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

  {
    std::scoped_lock status_lock(status_mutex_);
    first_access_unit_sent_ = false;
    codec_config_sent_for_stream_ = false;
    session_error_code_.clear();
    session_user_message_.clear();
    session_developer_message_.clear();
  }
  status_changed_.notify_all();

  return Snapshot();
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
        SetLastEncodeError(error);
        SetSessionError("CAPTURE_SOURCE_GONE",
                        "Windows screen capture stopped.",
                        error);
        running_ = false;
      }
      continue;
    }
    captured_frames_.fetch_add(1);
    if (frame.dropped_frames > 0) {
      capture_dropped_frames_.fetch_add(
          static_cast<std::uint64_t>(frame.dropped_frames));
    }

    std::vector<EncodedAccessUnit> access_units;
    if (!encoder_.Encode(frame, &access_units, &error)) {
      SetLastEncodeError(error);
      SetSessionError("ENCODER_NOT_AVAILABLE",
                      "The H.264 encoder stopped producing video.",
                      error);
      running_ = false;
      break;
    }
    const auto encode_done_us = NowUs();
    const auto capture_to_encode_ms =
        frame.pts_us <= encode_done_us ? UsToMs(encode_done_us - frame.pts_us)
                                       : 0.0;
    {
      std::scoped_lock status_lock(status_mutex_);
      last_capture_to_encode_ms_ = capture_to_encode_ms;
      total_capture_to_encode_ms_ += capture_to_encode_ms;
      if (capture_to_encode_ms > max_capture_to_encode_ms_) {
        max_capture_to_encode_ms_ = capture_to_encode_ms;
      }
    }

    for (const auto& access_unit : access_units) {
      if (access_unit.annex_b.empty()) {
        continue;
      }
      if (!codec_config_sent_for_stream_) {
        if (!access_unit.key_frame) {
          continue;
        }
        const auto parameter_sets = encoder_.parameter_sets();
        if (!parameter_sets.complete()) {
          const std::string config_error =
              "H.264 SPS/PPS were unavailable before the first IDR frame";
          SetLastEncodeError(config_error);
          SetSessionError("ENCODER_NOT_AVAILABLE",
                          "The H.264 encoder did not provide SPS/PPS.",
                          config_error);
          running_ = false;
          break;
        }
        if (!SendCodecConfig(parameter_sets)) {
          running_ = false;
          break;
        }
        codec_config_sent_for_stream_ = true;
      }

      const auto sequence = next_sequence_.fetch_add(1);
      encoded_frames_.fetch_add(1);
      auto packet = BuildAccessUnitPacket(
          sequence, access_unit.pts_us, access_unit.key_frame,
          access_unit.annex_b.data(),
          static_cast<std::uint32_t>(access_unit.annex_b.size()));
      bool first_access_unit_sent = false;
      {
        std::scoped_lock status_lock(status_mutex_);
        first_access_unit_sent = first_access_unit_sent_;
      }
      if (!first_access_unit_sent) {
        if (!SendFirstAccessUnit(std::move(packet), access_unit.key_frame)) {
          running_ = false;
          break;
        }
        continue;
      }
      bool pushed = false;
      const auto dropped = packet_queue_.PushDropOldestWhere(
          {std::move(packet), true, access_unit.key_frame},
          [](const QueuedVideoPacket& queued) {
            return queued.access_unit && !queued.key_frame;
          },
          [](const QueuedVideoPacket& incoming) {
            return incoming.access_unit && !incoming.key_frame;
          },
          &pushed);
      if (dropped > 0) {
        transport_dropped_frames_.fetch_add(dropped);
      }
      if (!pushed) {
        transport_dropped_frames_.fetch_add(1);
      }
    }
  }
  packet_queue_.Close();
}

void MirrorSession::SendLoop() {
  QueuedVideoPacket packet;
  while (running_ && packet_queue_.Pop(&packet)) {
    const auto result = transport_.SendPacket(packet.bytes);
    if (!result.ok) {
      SetLastSendError(result.detail);
      SetSessionError("NETWORK_DISCONNECTED",
                      "Could not send video packets to the TV.",
                      result.detail);
      running_ = false;
      packet_queue_.Close();
      break;
    }
    packets_sent_.fetch_add(1);
    bytes_sent_.fetch_add(static_cast<std::uint64_t>(packet.bytes.size()));
    send_completed_bytes_.fetch_add(static_cast<std::uint64_t>(packet.bytes.size()));
    if (packet.key_frame) {
      key_frames_sent_.fetch_add(1);
    }
    if (packet.access_unit) {
      MarkFirstAccessUnitSent();
    }
  }
}

bool MirrorSession::SendCodecConfig(const H264ParameterSets& parameter_sets) {
  const auto config_packet = BuildH264CodecConfigPacket(0, parameter_sets);
  if (config_packet.empty()) {
    const std::string error =
        "H.264 codec config packet could not be built from SPS/PPS";
    SetLastSendError(error);
    SetSessionError("ENCODER_NOT_AVAILABLE",
                    "Could not build the H.264 stream configuration.",
                    error);
    packet_queue_.Close();
    return false;
  }

  const auto result = transport_.SendPacket(config_packet);
  if (!result.ok) {
    SetLastSendError(result.detail);
    SetSessionError("SIGNALING_FAILED",
                    "Could not send the H.264 stream configuration.",
                    result.detail);
    packet_queue_.Close();
    return false;
  }

  codec_config_sent_.fetch_add(1);
  packets_sent_.fetch_add(1);
  bytes_sent_.fetch_add(static_cast<std::uint64_t>(config_packet.size()));
  send_completed_bytes_.fetch_add(static_cast<std::uint64_t>(config_packet.size()));
  return true;
}

bool MirrorSession::SendFirstAccessUnit(std::vector<std::uint8_t> packet,
                                        bool key_frame) {
  const auto result = transport_.SendPacket(packet);
  if (!result.ok) {
    SetLastSendError(result.detail);
    SetSessionError("NETWORK_DISCONNECTED",
                    "Could not send the first video frame to the TV.",
                    result.detail);
    packet_queue_.Close();
    return false;
  }

  packets_sent_.fetch_add(1);
  bytes_sent_.fetch_add(static_cast<std::uint64_t>(packet.size()));
  send_completed_bytes_.fetch_add(static_cast<std::uint64_t>(packet.size()));
  if (key_frame) {
    key_frames_sent_.fetch_add(1);
  }
  MarkFirstAccessUnitSent();
  return true;
}

NativeSnapshot MirrorSession::Snapshot() {
  std::scoped_lock status_lock(status_mutex_);
  return CurrentSnapshotLocked();
}

NativeSnapshot MirrorSession::BuildSnapshot(const std::string& state,
                                            const std::string& user_message) {
  bool capture_ready = false;
  {
    std::scoped_lock lock(mutex_);
    capture_ready = capture_ != nullptr;
  }

  NativeSnapshot snapshot;
  snapshot.state = state;
  snapshot.user_message = user_message;
  snapshot.capture_ready = capture_ready;
  snapshot.encoder_ready = running_;
  snapshot.signaling_ready =
      state != "idle" && session_error_code_ != "SIGNALING_FAILED" &&
      session_error_code_ != "NETWORK_DISCONNECTED";
  snapshot.native_video_path_ready = first_access_unit_sent_;
  snapshot.error_code = session_error_code_;
  snapshot.developer_message = session_developer_message_;
  snapshot.captured_frames = captured_frames_.load();
  snapshot.capture_dropped_frames = capture_dropped_frames_.load();
  snapshot.encoder_input_dropped_frames = encoder_input_dropped_frames_.load();
  snapshot.encoded_frames = encoded_frames_.load();
  snapshot.transport_dropped_frames = transport_dropped_frames_.load();
  snapshot.codec_config_sent = codec_config_sent_.load();
  snapshot.key_frames_sent = key_frames_sent_.load();
  snapshot.packets_sent = packets_sent_.load();
  snapshot.bytes_sent = bytes_sent_.load();
  snapshot.send_completed_bytes = send_completed_bytes_.load();
  snapshot.queue_depth_capture = 0;
  snapshot.queue_depth_encoder = 0;
  snapshot.queue_depth_transport =
      static_cast<int>(packet_queue_.Size());
  snapshot.last_capture_to_encode_ms = last_capture_to_encode_ms_;
  snapshot.average_capture_to_encode_ms =
      captured_frames_.load() == 0
          ? 0.0
          : total_capture_to_encode_ms_ /
                static_cast<double>(captured_frames_.load());
  snapshot.max_capture_to_encode_ms = max_capture_to_encode_ms_;
  snapshot.last_encode_error = last_encode_error_;
  snapshot.last_send_error = last_send_error_;
  return snapshot;
}

NativeSnapshot MirrorSession::CurrentSnapshotLocked() {
  if (!session_error_code_.empty()) {
    return BuildSnapshot("failed", session_user_message_);
  }
  if (!running_) {
    return BuildSnapshot("idle", "Native sender resources were released.");
  }
  if (first_access_unit_sent_) {
    return BuildSnapshot("streaming",
                         "Native 1280x720 H.264 video path is running.");
  }
  return BuildSnapshot("negotiating",
                       "Waiting for the first encoded video frame.");
}

void MirrorSession::ResetCounters() {
  captured_frames_ = 0;
  capture_dropped_frames_ = 0;
  encoder_input_dropped_frames_ = 0;
  encoded_frames_ = 0;
  transport_dropped_frames_ = 0;
  codec_config_sent_ = 0;
  key_frames_sent_ = 0;
  packets_sent_ = 0;
  bytes_sent_ = 0;
  send_completed_bytes_ = 0;
  std::scoped_lock status_lock(status_mutex_);
  first_access_unit_sent_ = false;
  codec_config_sent_for_stream_ = false;
  session_error_code_.clear();
  session_user_message_.clear();
  session_developer_message_.clear();
  last_encode_error_.clear();
  last_send_error_.clear();
  last_capture_to_encode_ms_ = 0.0;
  total_capture_to_encode_ms_ = 0.0;
  max_capture_to_encode_ms_ = 0.0;
}

void MirrorSession::SetSessionError(const std::string& error_code,
                                    const std::string& user_message,
                                    const std::string& developer_message) {
  {
    std::scoped_lock status_lock(status_mutex_);
    session_error_code_ = error_code;
    session_user_message_ = user_message;
    session_developer_message_ = developer_message;
  }
  status_changed_.notify_all();
}

void MirrorSession::SetLastEncodeError(const std::string& error) {
  std::scoped_lock status_lock(status_mutex_);
  last_encode_error_ = error;
}

void MirrorSession::SetLastSendError(const std::string& error) {
  std::scoped_lock status_lock(status_mutex_);
  last_send_error_ = error;
}

void MirrorSession::MarkFirstAccessUnitSent() {
  {
    std::scoped_lock status_lock(status_mutex_);
    first_access_unit_sent_ = true;
  }
  status_changed_.notify_all();
}

}  // namespace pctv
