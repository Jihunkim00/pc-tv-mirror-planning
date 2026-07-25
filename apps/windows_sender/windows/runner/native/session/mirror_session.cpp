#include "native/session/mirror_session.h"

#include "native/display/display_enumerator.h"

#include <algorithm>
#include <chrono>
#include <deque>
#include <string>
#include <utility>

#include <winrt/base.h>

namespace pctv {
namespace {

constexpr double kTargetFps = 30.0;
constexpr std::uint64_t kTargetFrameIntervalUs = 33'333;
constexpr std::uint64_t kRollingWindowUs = 2'000'000;

std::uint64_t NowUs() {
  const auto now = std::chrono::steady_clock::now().time_since_epoch();
  return static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

double UsToMs(std::uint64_t value_us) {
  return static_cast<double>(value_us) / 1000.0;
}

void TrimEvents(std::deque<std::uint64_t>* events, std::uint64_t now_us) {
  const std::uint64_t cutoff =
      now_us > kRollingWindowUs ? now_us - kRollingWindowUs : 0;
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
  if (span_us == 0) {
    return 0.0;
  }
  return static_cast<double>(events->size() - 1) * 1'000'000.0 /
         static_cast<double>(span_us);
}

std::vector<double> RecentIntervalsMs(std::deque<std::uint64_t>* events,
                                      std::uint64_t now_us) {
  TrimEvents(events, now_us);
  std::vector<double> intervals;
  if (events->size() < 2) {
    return intervals;
  }
  intervals.reserve(events->size() - 1);
  for (std::size_t index = 1; index < events->size(); ++index) {
    intervals.push_back(UsToMs((*events)[index] - (*events)[index - 1]));
  }
  return intervals;
}

double Average(const std::vector<double>& values) {
  if (values.empty()) {
    return 0.0;
  }
  double total = 0.0;
  for (const auto value : values) {
    total += value;
  }
  return total / static_cast<double>(values.size());
}

double P95(std::vector<double> values) {
  if (values.empty()) {
    return 0.0;
  }
  std::sort(values.begin(), values.end());
  return values[((values.size() - 1) * 95) / 100];
}

double AverageIntervalMs(std::deque<std::uint64_t>* events,
                         std::uint64_t now_us) {
  return Average(RecentIntervalsMs(events, now_us));
}

double P95IntervalMs(std::deque<std::uint64_t>* events, std::uint64_t now_us) {
  return P95(RecentIntervalsMs(events, now_us));
}

void TrimSamples(std::deque<std::pair<std::uint64_t, double>>* samples,
                 std::uint64_t now_us) {
  const std::uint64_t cutoff =
      now_us > kRollingWindowUs ? now_us - kRollingWindowUs : 0;
  while (!samples->empty() && samples->front().first < cutoff) {
    samples->pop_front();
  }
}

void RecordSample(std::deque<std::pair<std::uint64_t, double>>* samples,
                  std::uint64_t now_us,
                  double value_ms) {
  samples->push_back({now_us, value_ms});
  TrimSamples(samples, now_us);
}

std::vector<double> RecentSampleValues(
    std::deque<std::pair<std::uint64_t, double>>* samples,
    std::uint64_t now_us) {
  TrimSamples(samples, now_us);
  std::vector<double> values;
  values.reserve(samples->size());
  for (const auto& sample : *samples) {
    values.push_back(sample.second);
  }
  return values;
}

double AverageSampleMs(std::deque<std::pair<std::uint64_t, double>>* samples,
                       std::uint64_t now_us) {
  return Average(RecentSampleValues(samples, now_us));
}

double P95SampleMs(std::deque<std::pair<std::uint64_t, double>>* samples,
                   std::uint64_t now_us) {
  return P95(RecentSampleValues(samples, now_us));
}

std::string SenderBottleneckSummary(double captured_fps,
                                    double converted_fps,
                                    double encoded_fps,
                                    double sent_fps,
                                    double send_interval_p95_ms) {
  if (captured_fps > 0.0 && captured_fps < 27.0) {
    return "capture_bottleneck";
  }
  if (captured_fps >= 27.0 && converted_fps < 27.0) {
    return "conversion_bottleneck";
  }
  if (converted_fps >= 27.0 && encoded_fps < 27.0) {
    return "encoder_bottleneck";
  }
  if (encoded_fps >= 27.0 && sent_fps < 27.0) {
    return "transport_bottleneck";
  }
  if (sent_fps >= 27.0 && send_interval_p95_ms > 50.0) {
    return "transport_jitter";
  }
  if (captured_fps >= 27.0 && sent_fps >= 27.0) {
    return "healthy";
  }
  return "warming_up";
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

  Nv12Frame frame;
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
    {
      std::scoped_lock status_lock(status_mutex_);
      RecordEvent(&capture_callback_events_us_, frame.capture_callback_us);
      RecordEvent(&captured_events_us_, frame.capture_callback_us);
      RecordEvent(&converted_events_us_, frame.converted_us);
      RecordSample(&capture_to_convert_samples_, frame.converted_us,
                   frame.converted_us >= frame.capture_callback_us
                       ? UsToMs(frame.converted_us - frame.capture_callback_us)
                       : 0.0);
    }
    if (frame.dropped_frames > 0) {
      capture_dropped_frames_.fetch_add(
          static_cast<std::uint64_t>(frame.dropped_frames));
    }

    bool should_encode = true;
    {
      std::scoped_lock status_lock(status_mutex_);
      if (last_selected_capture_pts_us_ != 0 &&
          frame.pts_us > last_selected_capture_pts_us_ &&
          frame.pts_us - last_selected_capture_pts_us_ <
              kTargetFrameIntervalUs) {
        should_encode = false;
      } else {
        last_selected_capture_pts_us_ = frame.pts_us;
      }
    }
    if (!should_encode) {
      encoder_input_dropped_frames_.fetch_add(1);
      continue;
    }

    const auto encode_start_us = NowUs();
    {
      std::scoped_lock status_lock(status_mutex_);
      RecordEvent(&encoder_input_events_us_, encode_start_us);
      RecordSample(&convert_to_encode_samples_, encode_start_us,
                   frame.converted_us <= encode_start_us
                       ? UsToMs(encode_start_us - frame.converted_us)
                       : 0.0);
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
    {
      std::scoped_lock status_lock(status_mutex_);
      RecordSample(&encode_duration_samples_, encode_done_us,
                   encode_done_us >= encode_start_us
                       ? UsToMs(encode_done_us - encode_start_us)
                       : 0.0);
    }
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
      last_processed_frame_sequence_.store(sequence);
      {
        std::scoped_lock status_lock(status_mutex_);
        RecordEvent(&encoded_events_us_, encode_done_us);
      }
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
        if (!SendFirstAccessUnit(std::move(packet), access_unit.key_frame,
                                 encode_done_us)) {
          running_ = false;
          break;
        }
        continue;
      }
      bool pushed = false;
      const auto dropped = packet_queue_.PushDropOldestWhere(
          {std::move(packet), true, access_unit.key_frame, sequence,
           encode_done_us},
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
    const auto send_done_us = NowUs();
    packets_sent_.fetch_add(1);
    bytes_sent_.fetch_add(static_cast<std::uint64_t>(packet.bytes.size()));
    send_completed_bytes_.fetch_add(
        static_cast<std::uint64_t>(packet.bytes.size()));
    {
      std::scoped_lock status_lock(status_mutex_);
      for (std::uint32_t index = 0; index < result.send_calls; ++index) {
        RecordEvent(&socket_send_call_events_us_, send_done_us);
      }
      RecordSample(&packet_send_duration_samples_, send_done_us,
                   UsToMs(result.duration_us));
      if (packet.access_unit) {
        RecordEvent(&sent_access_unit_events_us_, send_done_us);
        RecordSample(&access_unit_send_duration_samples_, send_done_us,
                     UsToMs(result.duration_us));
        RecordSample(&encode_to_send_samples_, send_done_us,
                     send_done_us >= packet.encoded_done_us
                         ? UsToMs(send_done_us - packet.encoded_done_us)
                         : 0.0);
      }
    }
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
  send_completed_bytes_.fetch_add(
      static_cast<std::uint64_t>(config_packet.size()));
  const auto send_done_us = NowUs();
  {
    std::scoped_lock status_lock(status_mutex_);
    for (std::uint32_t index = 0; index < result.send_calls; ++index) {
      RecordEvent(&socket_send_call_events_us_, send_done_us);
    }
    RecordSample(&packet_send_duration_samples_, send_done_us,
                 UsToMs(result.duration_us));
  }
  return true;
}

bool MirrorSession::SendFirstAccessUnit(std::vector<std::uint8_t> packet,
                                        bool key_frame,
                                        std::uint64_t encoded_done_us) {
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
  const auto send_done_us = NowUs();
  {
    std::scoped_lock status_lock(status_mutex_);
    RecordEvent(&sent_access_unit_events_us_, send_done_us);
    for (std::uint32_t index = 0; index < result.send_calls; ++index) {
      RecordEvent(&socket_send_call_events_us_, send_done_us);
    }
    RecordSample(&packet_send_duration_samples_, send_done_us,
                 UsToMs(result.duration_us));
    RecordSample(&access_unit_send_duration_samples_, send_done_us,
                 UsToMs(result.duration_us));
    RecordSample(&encode_to_send_samples_, send_done_us,
                 send_done_us >= encoded_done_us
                     ? UsToMs(send_done_us - encoded_done_us)
                     : 0.0);
  }
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
  const auto now_us = NowUs();
  snapshot.target_fps = kTargetFps;
  snapshot.capture_callback_fps =
      RollingFps(&capture_callback_events_us_, now_us);
  snapshot.captured_fps = RollingFps(&captured_events_us_, now_us);
  snapshot.converted_fps = RollingFps(&converted_events_us_, now_us);
  snapshot.encoder_input_fps = RollingFps(&encoder_input_events_us_, now_us);
  snapshot.encoded_fps = RollingFps(&encoded_events_us_, now_us);
  snapshot.sent_access_unit_fps =
      RollingFps(&sent_access_unit_events_us_, now_us);
  snapshot.capture_frame_interval_average_ms =
      AverageIntervalMs(&captured_events_us_, now_us);
  snapshot.capture_frame_interval_p95_ms =
      P95IntervalMs(&captured_events_us_, now_us);
  snapshot.encode_frame_interval_average_ms =
      AverageIntervalMs(&encoder_input_events_us_, now_us);
  snapshot.send_frame_interval_average_ms =
      AverageIntervalMs(&sent_access_unit_events_us_, now_us);
  snapshot.capture_to_convert_average_ms =
      AverageSampleMs(&capture_to_convert_samples_, now_us);
  snapshot.convert_to_encode_average_ms =
      AverageSampleMs(&convert_to_encode_samples_, now_us);
  snapshot.encode_duration_average_ms =
      AverageSampleMs(&encode_duration_samples_, now_us);
  snapshot.encode_duration_p95_ms =
      P95SampleMs(&encode_duration_samples_, now_us);
  snapshot.encode_to_send_average_ms =
      AverageSampleMs(&encode_to_send_samples_, now_us);
  snapshot.captured_frames = captured_frames_.load();
  snapshot.capture_dropped_frames = capture_dropped_frames_.load();
  snapshot.conversion_dropped_frames = conversion_dropped_frames_.load();
  snapshot.encoder_input_dropped_frames = encoder_input_dropped_frames_.load();
  snapshot.encoded_frames = encoded_frames_.load();
  snapshot.transport_dropped_frames = transport_dropped_frames_.load();
  snapshot.duplicated_frames = duplicated_frames_.load();
  snapshot.last_processed_frame_sequence =
      last_processed_frame_sequence_.load();
  snapshot.codec_config_sent = codec_config_sent_.load();
  snapshot.key_frames_sent = key_frames_sent_.load();
  snapshot.packets_sent = packets_sent_.load();
  snapshot.bytes_sent = bytes_sent_.load();
  snapshot.send_completed_bytes = send_completed_bytes_.load();
  snapshot.socket_send_calls_per_second =
      RollingFps(&socket_send_call_events_us_, now_us);
  snapshot.average_packet_send_duration_ms =
      AverageSampleMs(&packet_send_duration_samples_, now_us);
  snapshot.access_unit_send_duration_average_ms =
      AverageSampleMs(&access_unit_send_duration_samples_, now_us);
  snapshot.access_unit_send_duration_p95_ms =
      P95SampleMs(&access_unit_send_duration_samples_, now_us);
  snapshot.pending_send_bytes = packet_queue_.Sum(
      [](const QueuedVideoPacket& packet) { return packet.bytes.size(); });
  snapshot.last_socket_error = last_send_error_;
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
  const auto encoder_diagnostics = encoder_.diagnostics();
  snapshot.selected_encoder_name = encoder_diagnostics.selected_encoder_name;
  snapshot.selected_encoder_hardware =
      encoder_diagnostics.selected_encoder_hardware;
  snapshot.selected_encoder_async =
      encoder_diagnostics.selected_encoder_async;
  snapshot.encoder_d3d11_aware = encoder_diagnostics.encoder_d3d11_aware;
  snapshot.encoder_input_format = encoder_diagnostics.encoder_input_format;
  snapshot.encoder_output_format = encoder_diagnostics.encoder_output_format;
  snapshot.average_encode_duration_ms = snapshot.encode_duration_average_ms;
  snapshot.encoder_backpressure_count =
      encoder_diagnostics.encoder_backpressure_count;
  snapshot.low_latency_options_applied =
      encoder_diagnostics.low_latency_options_applied;
  snapshot.unsupported_encoder_options =
      encoder_diagnostics.unsupported_encoder_options;
  snapshot.bottleneck_summary = SenderBottleneckSummary(
      snapshot.captured_fps, snapshot.converted_fps, snapshot.encoded_fps,
      snapshot.sent_access_unit_fps,
      P95IntervalMs(&sent_access_unit_events_us_, now_us));
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
  conversion_dropped_frames_ = 0;
  encoder_input_dropped_frames_ = 0;
  encoded_frames_ = 0;
  transport_dropped_frames_ = 0;
  duplicated_frames_ = 0;
  last_processed_frame_sequence_ = 0;
  codec_config_sent_ = 0;
  key_frames_sent_ = 0;
  packets_sent_ = 0;
  bytes_sent_ = 0;
  send_completed_bytes_ = 0;
  std::scoped_lock status_lock(status_mutex_);
  last_selected_capture_pts_us_ = 0;
  capture_callback_events_us_.clear();
  captured_events_us_.clear();
  converted_events_us_.clear();
  encoder_input_events_us_.clear();
  encoded_events_us_.clear();
  sent_access_unit_events_us_.clear();
  socket_send_call_events_us_.clear();
  capture_to_convert_samples_.clear();
  convert_to_encode_samples_.clear();
  encode_duration_samples_.clear();
  encode_to_send_samples_.clear();
  packet_send_duration_samples_.clear();
  access_unit_send_duration_samples_.clear();
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
