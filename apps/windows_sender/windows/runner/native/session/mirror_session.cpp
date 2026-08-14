#include "native/session/mirror_session.h"

#include "native/audio/audio_device_enumerator.h"
#include "native/display/display_enumerator.h"

#include <algorithm>
#include <optional>
#include <tuple>
#include <cctype>
#include <chrono>
#include <deque>
#include <cstdlib>
#include <sstream>
#include <string>
#include <utility>

#include <winrt/base.h>

namespace pctv {
namespace {

constexpr std::uint64_t kRollingWindowUs = 5'000'000;
constexpr std::uint64_t kMinimumStaleVideoAgeUs = 80'000;

std::uint64_t NowUs() {
  const auto now = std::chrono::steady_clock::now().time_since_epoch();
  return static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

double UsToMs(std::uint64_t value_us) {
  return static_cast<double>(value_us) / 1000.0;
}

std::string JsonEscape(const std::string& value) {
  std::string escaped;
  escaped.reserve(value.size());
  for (const char ch : value) {
    if (ch == '\\' || ch == '"') {
      escaped.push_back('\\');
    }
    escaped.push_back(ch);
  }
  return escaped;
}

std::string ExtractJsonString(const std::string& json,
                              const std::string& key) {
  const auto key_pos = json.find("\"" + key + "\"");
  if (key_pos == std::string::npos) {
    return {};
  }
  const auto colon = json.find(':', key_pos);
  if (colon == std::string::npos) {
    return {};
  }
  const auto first_quote = json.find('"', colon + 1);
  if (first_quote == std::string::npos) {
    return {};
  }
  const auto second_quote = json.find('"', first_quote + 1);
  if (second_quote == std::string::npos) {
    return {};
  }
  return json.substr(first_quote + 1, second_quote - first_quote - 1);
}

std::uint64_t ExtractJsonUint64(const std::string& json,
                                const std::string& key) {
  const auto key_pos = json.find("\"" + key + "\"");
  if (key_pos == std::string::npos) {
    return 0;
  }
  const auto colon = json.find(':', key_pos);
  if (colon == std::string::npos) {
    return 0;
  }
  auto index = colon + 1;
  while (index < json.size() &&
         std::isspace(static_cast<unsigned char>(json[index])) != 0) {
    ++index;
  }
  std::uint64_t value = 0;
  while (index < json.size() &&
         std::isdigit(static_cast<unsigned char>(json[index])) != 0) {
    value = value * 10 + static_cast<std::uint64_t>(json[index] - '0');
    ++index;
  }
  return value;
}

int ExtractJsonInt(const std::string& json,
                   const std::string& key,
                   int fallback = 0) {
  const auto key_pos = json.find("\"" + key + "\"");
  if (key_pos == std::string::npos) {
    return fallback;
  }
  const auto colon = json.find(':', key_pos);
  if (colon == std::string::npos) {
    return fallback;
  }
  auto index = colon + 1;
  while (index < json.size() &&
         std::isspace(static_cast<unsigned char>(json[index])) != 0) {
    ++index;
  }
  bool negative = false;
  if (index < json.size() && json[index] == '-') {
    negative = true;
    ++index;
  }
  int value = 0;
  bool found = false;
  while (index < json.size() &&
         std::isdigit(static_cast<unsigned char>(json[index])) != 0) {
    found = true;
    value = value * 10 + (json[index] - '0');
    ++index;
  }
  return found ? (negative ? -value : value) : fallback;
}

double ExtractJsonDouble(const std::string& json,
                         const std::string& key,
                         double fallback = 0.0) {
  const auto key_pos = json.find(std::string(1, '"' ) + key + std::string(1, '"'));
  if (key_pos == std::string::npos) {
    return fallback;
  }
  const auto colon = json.find(':', key_pos);
  if (colon == std::string::npos) {
    return fallback;
  }
  auto index = colon + 1;
  while (index < json.size() &&
         std::isspace(static_cast<unsigned char>(json[index])) != 0) {
    ++index;
  }
  char* end = nullptr;
  const auto value = std::strtod(json.c_str() + index, &end);
  return end == json.c_str() + index ? fallback : value;
}
bool ExtractJsonBool(const std::string& json,
                     const std::string& key,
                     bool fallback = false) {
  const auto key_pos = json.find("\"" + key + "\"");
  if (key_pos == std::string::npos) {
    return fallback;
  }
  const auto colon = json.find(':', key_pos);
  if (colon == std::string::npos) {
    return fallback;
  }
  auto index = colon + 1;
  while (index < json.size() &&
         std::isspace(static_cast<unsigned char>(json[index])) != 0) {
    ++index;
  }
  if (json.compare(index, 4, "true") == 0) {
    return true;
  }
  if (json.compare(index, 5, "false") == 0) {
    return false;
  }
  return fallback;
}

void ReplaceJsonNumber(std::string* json, const std::string& key, int value) {
  const auto key_pos = json->find("\"" + key + "\"");
  if (key_pos == std::string::npos) {
    return;
  }
  const auto colon = json->find(':', key_pos);
  if (colon == std::string::npos) {
    return;
  }
  auto begin = colon + 1;
  while (begin < json->size() &&
         std::isspace(static_cast<unsigned char>((*json)[begin])) != 0) {
    ++begin;
  }
  auto end = begin;
  while (end < json->size() &&
         (std::isdigit(static_cast<unsigned char>((*json)[end])) != 0 ||
          (*json)[end] == '-')) {
    ++end;
  }
  json->replace(begin, end - begin, std::to_string(value));
}

void ReplaceJsonString(std::string* json,
                       const std::string& key,
                       const std::string& value) {
  const auto key_pos = json->find("\"" + key + "\"");
  if (key_pos == std::string::npos) {
    return;
  }
  const auto colon = json->find(':', key_pos);
  if (colon == std::string::npos) {
    return;
  }
  const auto begin = json->find('"', colon + 1);
  if (begin == std::string::npos) {
    return;
  }
  const auto end = json->find('"', begin + 1);
  if (end == std::string::npos) {
    return;
  }
  json->replace(begin + 1, end - begin - 1, value);
}

bool IsExperimental4k30(const VideoStreamConfig& config) {
  return config.performance_profile == "experimental4k30";
}

VideoStreamConfig HighQuality1080p30Fallback(const VideoStreamConfig& from) {
  VideoStreamConfig fallback = from;
  fallback.width = 1920;
  fallback.height = 1080;
  fallback.fps = 30;
  fallback.bitrate_kbps = 7500;
  fallback.keyframe_interval_frames = 30;
  fallback.performance_profile = "highQuality1080p30";
  fallback.require_hardware_encoder = false;
  return fallback;
}

bool IsHighQuality1080p60(const VideoStreamConfig& config) {
  return config.performance_profile == "highQuality1080p60";
}

std::optional<std::tuple<int, int, double>> SourceDisplayMetrics(
    const std::string& source_id) {
  const auto monitor = FindMonitorById(source_id);
  if (!monitor.has_value()) {
    return std::nullopt;
  }
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(*monitor, &info)) {
    return std::nullopt;
  }
  DEVMODEW mode{};
  mode.dmSize = sizeof(mode);
  const double refresh_hz =
      EnumDisplaySettingsW(info.szDevice, ENUM_CURRENT_SETTINGS, &mode) &&
              mode.dmDisplayFrequency > 1
          ? static_cast<double>(mode.dmDisplayFrequency)
          : 0.0;
  return std::make_tuple(info.rcMonitor.right - info.rcMonitor.left,
                         info.rcMonitor.bottom - info.rcMonitor.top,
                         refresh_hz);
}

VideoStreamConfig HighQuality1080p60Fallback(const VideoStreamConfig& from) {
  VideoStreamConfig fallback = HighQuality1080p30Fallback(from);
  fallback.performance_profile = "highQuality1080p30";
  return fallback;
}
std::string RequestJsonForVideoConfig(std::string request_json,
                                      const VideoStreamConfig& config) {
  ReplaceJsonNumber(&request_json, "width", config.width);
  ReplaceJsonNumber(&request_json, "height", config.height);
  ReplaceJsonNumber(&request_json, "fps", config.fps);
  ReplaceJsonNumber(&request_json, "bitrateKbps", config.bitrate_kbps);
  ReplaceJsonString(&request_json, "performanceProfile",
                    config.performance_profile);
  return request_json;
}

bool CaptureSourceSupportsResolution(const std::string& source_id,
                                     int width,
                                     int height) {
  const auto monitor = FindMonitorById(source_id);
  if (!monitor.has_value()) {
    return false;
  }
  MONITORINFOEXW info;
  info.cbSize = sizeof(MONITORINFOEXW);
  if (!GetMonitorInfoW(*monitor, &info)) {
    return false;
  }
  const int monitor_width = info.rcMonitor.right - info.rcMonitor.left;
  const int monitor_height = info.rcMonitor.bottom - info.rcMonitor.top;
  return monitor_width >= width && monitor_height >= height;
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

double P50(std::vector<double> values) {
  if (values.empty()) {
    return 0.0;
  }
  std::sort(values.begin(), values.end());
  return values[(values.size() - 1) / 2];
}

double Maximum(std::vector<double> values) {
  if (values.empty()) {
    return 0.0;
  }
  return *std::max_element(values.begin(), values.end());
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

std::string CaptureBottleneckStage(
    const CapturePipelineTimingSnapshot& capture,
    const H264EncoderDiagnostics& encoder) {
  std::string stage = "unknown";
  double highest_ms = 0.0;
  const auto consider = [&stage, &highest_ms](const char* name,
                                               double value_ms) {
    if (value_ms > highest_ms) {
      highest_ms = value_ms;
      stage = name;
    }
  };
  consider("frame_acquire", capture.frame_acquire_p95_ms);
  consider("copy_resource", capture.copy_resource_p95_ms);
  consider("map_readback", capture.map_readback_p95_ms);
  consider("scale", capture.scale_p95_ms);
  consider("bgra_to_nv12", capture.bgra_to_nv12_p95_ms);
  consider("nv12_copy", encoder.nv12_copy_duration_p95_ms);
  consider("sample_prepare", encoder.sample_prepare_duration_p95_ms);
  consider("process_input", encoder.process_input_duration_p95_ms);
  return highest_ms > 0.0 ? stage : "unknown";
}

std::string SenderBottleneckSummary(double capture_callback_fps,
                                    double admitted_fps,
                                    double converted_fps,
                                    double encoder_accepted_fps,
                                    double encoded_fps,
                                    double sent_fps,
                                    double send_interval_p95_ms) {
  constexpr double kMinimumHealthyFps = 23.0;
  constexpr double kRecommendedHealthyFps = 27.0;
  if (capture_callback_fps > 0.0 &&
      capture_callback_fps < kMinimumHealthyFps) {
    return "capture_bottleneck";
  }
  if (capture_callback_fps >= kMinimumHealthyFps &&
      admitted_fps < kMinimumHealthyFps) {
    return "cadence_bottleneck";
  }
  if (admitted_fps >= kMinimumHealthyFps &&
      converted_fps < kMinimumHealthyFps) {
    return "conversion_bottleneck";
  }
  if (converted_fps >= kMinimumHealthyFps &&
      encoder_accepted_fps < kMinimumHealthyFps) {
    return "encoder_bottleneck";
  }
  if (encoder_accepted_fps >= kMinimumHealthyFps &&
      encoded_fps < kMinimumHealthyFps) {
    return "encoder_bottleneck";
  }
  if (encoded_fps >= kMinimumHealthyFps && sent_fps < kMinimumHealthyFps) {
    return "transport_bottleneck";
  }
  if (sent_fps >= kMinimumHealthyFps && send_interval_p95_ms > 60.0) {
    return "transport_jitter";
  }
  if (capture_callback_fps >= kRecommendedHealthyFps &&
      admitted_fps >= kRecommendedHealthyFps &&
      encoder_accepted_fps >= kRecommendedHealthyFps &&
      encoded_fps >= kRecommendedHealthyFps &&
      sent_fps >= kRecommendedHealthyFps) {
    return "healthy_27_plus";
  }
  if (capture_callback_fps >= kMinimumHealthyFps &&
      admitted_fps >= kMinimumHealthyFps &&
      encoder_accepted_fps >= kMinimumHealthyFps &&
      encoded_fps >= kMinimumHealthyFps &&
      sent_fps >= kMinimumHealthyFps) {
    return "healthy_23_plus";
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

  requested_video_config_ = options.video;
  if (const auto display = SourceDisplayMetrics(options.source_id);
      display.has_value()) {
    source_display_width_ = std::get<0>(*display);
    source_display_height_ = std::get<1>(*display);
    source_display_refresh_hz_ = std::get<2>(*display);
    source_display_device_name_ = options.source_id;
  }
  VideoStreamConfig applied_video = options.video;
  std::string request_json = options.request_json;
  std::string fallback_reason;
  const bool requested_4k = IsExperimental4k30(options.video);
  if (requested_4k &&
      !CaptureSourceSupportsResolution(options.source_id, 3840, 2160)) {
    applied_video = HighQuality1080p30Fallback(options.video);
    request_json = RequestJsonForVideoConfig(options.request_json,
                                             applied_video);
    fallback_reason = "4K unavailable: capture source is below 3840x2160";
  }

  const bool requested_fhd60 = IsHighQuality1080p60(options.video);
  if (requested_fhd60 && source_display_refresh_hz_ > 0.0 &&
      source_display_refresh_hz_ < 59.5) {
    applied_video = HighQuality1080p60Fallback(options.video);
    request_json = RequestJsonForVideoConfig(options.request_json,
                                             applied_video);
    std::ostringstream reason;
    reason << "FHD60 unavailable: source display reports "
           << source_display_refresh_hz_ << " Hz";
    fallback_reason = reason.str();
  }
  auto connect_receiver = [&](const std::string& json) {
    auto signal =
        transport_.Connect(options.receiver_host, options.receiver_port, json);
    if (signal.ok) {
      receiver_max_width_ =
          ExtractJsonInt(signal.detail, "receiverMaxVideoWidth");
      receiver_max_height_ =
          ExtractJsonInt(signal.detail, "receiverMaxVideoHeight");
      receiver_max_fps_ = ExtractJsonInt(signal.detail, "receiverMaxVideoFps");
      receiver_supports_4k30_ =
          ExtractJsonBool(signal.detail, "receiverSupports4k30");
      receiver_presented_fps_recent_ = static_cast<double>(
          ExtractJsonInt(signal.detail, "receiverPresentedFpsRecent"));
    }
    return signal;
  };

  auto signal = connect_receiver(request_json);
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
  if (requested_fhd60 && fallback_reason.empty() && receiver_max_fps_ < 60) {
    transport_.Close();
    applied_video = HighQuality1080p60Fallback(options.video);
    request_json = RequestJsonForVideoConfig(options.request_json,
                                             applied_video);
    std::ostringstream reason;
    if (receiver_max_fps_ > 0) {
      reason << "FHD60 unavailable: receiver decoder reports max "
             << receiver_max_fps_ << " fps";
    } else {
      reason << "FHD60 unavailable: receiver FPS capability not confirmed";
    }
    fallback_reason = reason.str();
    signal = connect_receiver(request_json);
    if (!signal.ok) {
      return {"failed", "Could not reach the TV receiver.", false, false,
              false, false, "SIGNALING_FAILED", signal.detail};
    }
  }

  if (requested_4k && fallback_reason.empty() && !receiver_supports_4k30_) {
    transport_.Close();
    applied_video = HighQuality1080p30Fallback(options.video);
    request_json = RequestJsonForVideoConfig(options.request_json,
                                             applied_video);
    if (receiver_max_width_ > 0 && receiver_max_height_ > 0) {
      std::ostringstream reason;
      reason << "4K unavailable: receiver decoder supports up to "
             << receiver_max_width_ << "x" << receiver_max_height_;
      fallback_reason = reason.str();
    } else {
      fallback_reason = "4K unavailable: receiver capability not confirmed";
    }
    signal = connect_receiver(request_json);
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
  }

  auto apply_video_config = [&]() {
    video_config_ = applied_video;
    requested_profile_ = options.video.performance_profile;
    applied_profile_ = applied_video.performance_profile;
    profile_fallback_reason_ = fallback_reason;
    target_fps_ = static_cast<double>(std::max(1, applied_video.fps));
    target_frame_interval_us_ =
        static_cast<std::uint64_t>(1'000'000.0 / target_fps_);
    cadence_limiter_.SetTargetIntervalUs(target_frame_interval_us_);
  };
  apply_video_config();

  std::string error;
  auto capture = std::make_unique<DisplayCapture>();
  if (!capture->Start(options.source_id, applied_video.width,
                      applied_video.height, &error)) {
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

  if (!encoder_.Start(applied_video, &error)) {
    if ((requested_4k && IsExperimental4k30(applied_video)) ||
        (requested_fhd60 && IsHighQuality1080p60(applied_video))) {
      capture->Stop();
      transport_.Close();
      applied_video = requested_fhd60 ? HighQuality1080p60Fallback(options.video)
                                      : HighQuality1080p30Fallback(options.video);
      request_json = RequestJsonForVideoConfig(options.request_json,
                                               applied_video);
      fallback_reason = requested_fhd60
          ? "FHD60 unavailable: encoder could not accept 1080p60"
          : "4K unavailable: hardware encoder capability check failed";
      signal = connect_receiver(request_json);
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
      apply_video_config();
      capture = std::make_unique<DisplayCapture>();
      if (!capture->Start(options.source_id, applied_video.width,
                          applied_video.height, &error)) {
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
      if (!encoder_.Start(applied_video, &error)) {
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
    } else {
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
  }

  packet_queue_.Reset();
  audio_queue_.Reset();
  next_sequence_ = 1;
  next_audio_sequence_ = 1;
  audio_enabled_ = options.audio_enabled;
  pc_local_audio_mute_requested_ = options.pc_local_audio_mute_requested;
  tv_audio_source_device_id_ = options.tv_audio_source_device_id;
  pc_monitor_device_id_ = options.pc_monitor_device_id;
  paused_ = false;
  audio_config_requested_ = false;
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
  control_thread_ = std::thread([this]() { ControlLoop(); });
  if (options.audio_enabled) {
    audio_thread_ = std::thread([this]() { AudioLoop(); });
  }

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
  audio_queue_.Close();
  if (encode_thread_.joinable()) {
    encode_thread_.join();
  }
  if (audio_thread_.joinable()) {
    audio_thread_.join();
  }
  if (send_thread_.joinable()) {
    send_thread_.join();
  }
  if (control_thread_.joinable()) {
    control_thread_.join();
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
    audio_capture_state_ = "disabled";
  }
  status_changed_.notify_all();

  return Snapshot();
}

NativeSnapshot MirrorSession::SetPcLocalAudioMuteRequested(bool requested) {
  pc_local_audio_mute_requested_.store(requested);
  ApplyLocalMonitorMute(requested);
  return Snapshot();
}

void MirrorSession::ApplyLocalMonitorMute(bool requested) {
  std::scoped_lock route_lock(audio_route_mutex_);
  if (local_monitor_renderer_ != nullptr &&
      pc_local_audio_mute_supported_.load()) {
    local_monitor_renderer_->SetMuted(requested);
    local_monitor_muted_.store(requested);
    pc_local_audio_mute_applied_.store(requested);
    local_monitor_queue_depth_.store(local_monitor_renderer_->queue_depth());
    local_monitor_dropped_buffers_.store(
        local_monitor_renderer_->dropped_buffers());
    return;
  }
  pc_local_audio_mute_applied_.store(false);
  local_monitor_muted_.store(false);
}

void MirrorSession::EncodeLoop() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }

  Nv12Frame frame;
  while (running_) {
    if (IsPaused()) {
      {
        std::scoped_lock status_lock(status_mutex_);
        cadence_limiter_.Reset();
        cadence_skip_reason_ = "unavailable";
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }

    DisplayCapture* capture = nullptr;
    {
      std::scoped_lock lock(mutex_);
      capture = capture_.get();
    }
    if (capture == nullptr) {
      break;
    }

    auto should_convert = [this](std::uint64_t capture_us,
                                 std::uint64_t source_pts_us,
                                 bool source_pts_valid) {
      std::scoped_lock status_lock(status_mutex_);
      const auto decision = cadence_limiter_.Admit(
          capture_us, source_pts_us, source_pts_valid);
      cadence_skip_reason_ = CadenceSkipReasonText(decision.reason);
      if (!decision.admitted) {
        cadence_skipped_frames_.fetch_add(1);
        RecordEvent(&cadence_dropped_events_us_, capture_us);
        return false;
      }
      RecordEvent(&target_admission_events_us_, capture_us);
      RecordEvent(&admitted_frame_events_us_, capture_us);
      return true;
    };

    std::string error;
    if (!capture->CaptureNext(&frame, 500, should_convert, &error)) {
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
    }
    {
      std::scoped_lock status_lock(status_mutex_);
      latest_capture_system_relative_time_ns_ =
          frame.capture_system_relative_time_ns;
      latest_sender_generated_pts_us_ = frame.pts_us;
      latest_source_timestamp_delta_us_ = frame.source_timestamp_delta_us;
      latest_video_pts_source_ = frame.video_pts_source;
      latest_source_texture_width_ = frame.source_texture_width;
      latest_source_texture_height_ = frame.source_texture_height;
      latest_source_texture_format_ = frame.source_texture_format;
      latest_source_row_pitch_ = frame.source_row_pitch;
      latest_source_bgra_stride_ = frame.source_bgra_stride;
      latest_nv12_y_offset_ = frame.nv12_y_offset;
      latest_nv12_uv_offset_ = frame.nv12_uv_offset;
      latest_nv12_y_stride_ = frame.nv12_y_stride;
      latest_nv12_uv_stride_ = frame.nv12_uv_stride;
      latest_nv12_expected_bytes_ = frame.nv12_expected_bytes;
      latest_nv12_allocated_bytes_ = frame.nv12_allocated_bytes;
      latest_nv12_used_bytes_ = frame.nv12_used_bytes;
      latest_encoder_input_stride_ = frame.encoder_input_stride;
      if (frame.source_timestamp_delta_us > last_source_timestamp_us_) {
        if (last_source_timestamp_us_ > 0) {
          RecordSample(&source_frame_interval_samples_, NowUs(),
                       UsToMs(frame.source_timestamp_delta_us -
                              last_source_timestamp_us_));
        }
        last_source_timestamp_us_ = frame.source_timestamp_delta_us;
      }
      if (frame.dropped_frames > 0) {
        const auto replaced = static_cast<std::uint64_t>(frame.dropped_frames);
        capture_replaced_frames_.fetch_add(replaced);
        capture_dropped_frames_.fetch_add(replaced);
      }
    }
    if (frame.data.empty()) {
      encoder_input_dropped_frames_.fetch_add(1);
      continue;
    }

    {
      std::scoped_lock status_lock(status_mutex_);
      RecordEvent(&converted_events_us_, frame.converted_us);
      RecordSample(&capture_to_convert_samples_, frame.converted_us,
                   frame.converted_us >= frame.capture_callback_us
                       ? UsToMs(frame.converted_us - frame.capture_callback_us)
                       : 0.0);
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
    bool encoder_input_accepted = false;
    bool encoder_backpressure_dropped = false;
    if (!encoder_.Encode(frame, &access_units, &encoder_input_accepted,
                         &encoder_backpressure_dropped, &error)) {
      SetLastEncodeError(error);
      SetSessionError("ENCODER_NOT_AVAILABLE",
                      "The H.264 encoder stopped producing video.",
                      error);
      running_ = false;
      break;
    }
    if (encoder_backpressure_dropped) {
      encoder_backpressure_dropped_frames_.fetch_add(1);
      encoder_input_dropped_frames_.fetch_add(1);
      {
        std::scoped_lock status_lock(status_mutex_);
        RecordEvent(&encoder_busy_dropped_events_us_, NowUs());
      }
      continue;
    }
    if (encoder_input_accepted) {
      std::scoped_lock status_lock(status_mutex_);
      RecordEvent(&encoder_accepted_events_us_, NowUs());
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
        frame.capture_callback_us <= encode_done_us ? UsToMs(encode_done_us - frame.capture_callback_us)
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
      if (!codec_config_sent_for_stream_.load()) {
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
        codec_config_sent_for_stream_.store(true);
      }

      const auto sequence = next_sequence_.fetch_add(1);
      encoded_frames_.fetch_add(1);
      last_processed_frame_sequence_.store(sequence);
      {
        std::scoped_lock status_lock(status_mutex_);
        RecordEvent(&encoded_events_us_, encode_done_us);
      }
      encoded_access_unit_bytes_ += access_unit.annex_b.size();
      auto packet = BuildAccessUnitPacket(
          sequence, access_unit.pts_us, access_unit.key_frame,
          access_unit.annex_b.data(),
          static_cast<std::uint32_t>(access_unit.annex_b.size()));      {
        std::scoped_lock status_lock(status_mutex_);
        if (packet.size() < 4 + 28 ||
            packet.size() - 4 - 28 != access_unit.annex_b.size()) {
          ++video_au_size_mismatch_count_;
        } else {
          transported_access_unit_bytes_ += packet.size() - 4 - 28;
        }
      }
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
        transport_backpressure_dropped_frames_.fetch_add(dropped);
      }
      if (!pushed) {
        transport_dropped_frames_.fetch_add(1);
        transport_backpressure_dropped_frames_.fetch_add(1);
      }
    }
  }
  packet_queue_.Close();
}

void MirrorSession::AudioLoop() {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
  }

  {
    std::scoped_lock status_lock(status_mutex_);
    audio_capture_state_ = "starting";
    audio_last_error_.clear();
  }

  std::string error;
  SystemAudioLoopback capture;
  if (!capture.Start(tv_audio_source_device_id_, &error)) {
    std::scoped_lock status_lock(status_mutex_);
    audio_capture_state_ = "failed";
    audio_last_error_ = error;
    return;
  }

  WasapiLocalMonitorRenderer local_monitor;
  bool local_monitor_started = false;
  {
    std::string routing_error;
    const auto source_info = FindAudioRenderDeviceById(capture.device_id());
    const auto monitor_info = FindAudioRenderDeviceById(pc_monitor_device_id_);
    const bool source_is_virtual =
        source_info.has_value()
            ? source_info->is_likely_virtual
            : IsLikelyVirtualAudioDeviceName(capture.device_name());
    if (capture.device_id().empty()) {
      routing_error = "Selected audio device is unavailable";
    } else if (!source_is_virtual) {
      routing_error = "No separate virtual audio endpoint found";
    } else if (!monitor_info.has_value()) {
      routing_error = "Selected PC speaker output is unavailable";
    } else if (monitor_info->id == capture.device_id()) {
      routing_error =
          "TV source and PC speaker output are the same endpoint";
    } else if (!local_monitor.Start(monitor_info->id, &routing_error)) {
      if (routing_error.empty()) {
        routing_error = "Local monitor renderer is not initialized";
      }
    } else {
      local_monitor_started = true;
      local_monitor.SetMuted(pc_local_audio_mute_requested_.load());
    }

    std::scoped_lock status_lock(status_mutex_);
    tv_audio_source_device_id_ = capture.device_id();
    tv_audio_source_device_name_ = capture.device_name();
    pc_monitor_device_id_ = monitor_info.has_value() ? monitor_info->id : "";
    pc_monitor_device_name_ =
        monitor_info.has_value() ? monitor_info->name : "";
    audio_capture_format_ = capture.capture_format();
    audio_monitor_format_ =
        local_monitor_started ? local_monitor.format_description() : "";
    audio_routing_mode_ =
        local_monitor_started ? "virtual_endpoint_monitor" : "unsupported";
    audio_routing_unsupported_reason_ =
        local_monitor_started ? std::string() : routing_error;
  }
  {
    std::scoped_lock route_lock(audio_route_mutex_);
    local_monitor_renderer_ = local_monitor_started ? &local_monitor : nullptr;
  }
  pc_local_audio_mute_supported_.store(local_monitor_started);
  pc_local_audio_mute_applied_.store(
      local_monitor_started && pc_local_audio_mute_requested_.load());
  local_monitor_active_.store(local_monitor_started);
  local_monitor_muted_.store(
      local_monitor_started && pc_local_audio_mute_requested_.load());

  AacEncoder encoder;
  if (!encoder.Start(&error)) {
    {
      std::scoped_lock route_lock(audio_route_mutex_);
      if (local_monitor_renderer_ == &local_monitor) {
        local_monitor_renderer_ = nullptr;
      }
    }
    local_monitor.Stop();
    local_monitor_active_.store(false);
    local_monitor_muted_.store(false);
    pc_local_audio_mute_applied_.store(false);
    capture.Stop();
    std::scoped_lock status_lock(status_mutex_);
    audio_capture_state_ = "failed";
    audio_last_error_ = error;
    return;
  }

  {
    std::scoped_lock status_lock(status_mutex_);
    audio_capture_state_ = "capturing";
    audio_device_name_ = capture.device_name();
    audio_input_sample_rate_ = capture.input_sample_rate();
    audio_input_channels_ = capture.input_channels();
  }

  auto queue_config_packet = [&]() {
    const auto config_sequence = next_audio_sequence_.fetch_add(1);
    auto config_packet = BuildAacCodecConfigPacket(
        config_sequence, capture.stream_start_pts_us(),
        encoder.codec_specific_data());
    if (config_packet.empty()) {
      audio_dropped_packets_.fetch_add(1);
      return;
    }
    bool pushed = false;
    const auto dropped = audio_queue_.PushDropOldestWhere(
        {std::move(config_packet), true, false, config_sequence, NowUs()},
        [](const QueuedAudioPacket& queued) { return queued.access_unit; },
        [](const QueuedAudioPacket&) { return false; }, &pushed);
    if (dropped > 0 || !pushed) {
      audio_dropped_packets_.fetch_add(dropped + (pushed ? 0 : 1));
    }
  };
  queue_config_packet();

  PcmAudioFrame pcm_frame;
  while (running_) {
    error.clear();
    if (IsPaused()) {
      if (!capture.CaptureNext(&pcm_frame, 50, &error) && !error.empty()) {
        std::scoped_lock status_lock(status_mutex_);
        audio_capture_state_ = "failed";
        audio_last_error_ = error;
        break;
      }
      continue;
    }
    if (audio_config_requested_.exchange(false)) {
      queue_config_packet();
    }
    if (!capture.CaptureNext(&pcm_frame, 200, &error)) {
      if (!error.empty()) {
        std::scoped_lock status_lock(status_mutex_);
        audio_capture_state_ = "failed";
        audio_last_error_ = error;
        break;
      }
      continue;
    }
    captured_audio_packets_.fetch_add(1);
    const auto capture_done_us = NowUs();
    if (local_monitor_started) {
      local_monitor.Enqueue(pcm_frame);
      local_monitor_queue_depth_.store(local_monitor.queue_depth());
      local_monitor_dropped_buffers_.store(local_monitor.dropped_buffers());
      local_monitor_muted_.store(local_monitor.muted());
    }
    {
      std::scoped_lock status_lock(status_mutex_);
      RecordEvent(&audio_capture_events_us_, capture_done_us);
    }

    std::vector<EncodedAudioAccessUnit> access_units;
    const auto encode_start_us = NowUs();
    if (!encoder.Encode(pcm_frame, &access_units, &error)) {
      std::scoped_lock status_lock(status_mutex_);
      audio_capture_state_ = "failed";
      audio_last_error_ = error;
      break;
    }
    const auto encode_done_us = NowUs();
    {
      std::scoped_lock status_lock(status_mutex_);
      RecordSample(&audio_encode_duration_samples_, encode_done_us,
                   UsToMs(encode_done_us - encode_start_us));
    }

    for (const auto& access_unit : access_units) {
      if (access_unit.bytes.empty()) {
        continue;
      }
      const auto sequence = next_audio_sequence_.fetch_add(1);
      auto packet = BuildAudioAccessUnitPacket(
          sequence, access_unit.pts_us, access_unit.bytes.data(),
          static_cast<std::uint32_t>(access_unit.bytes.size()));
      if (packet.empty()) {
        audio_dropped_packets_.fetch_add(1);
        continue;
      }
      encoded_audio_packets_.fetch_add(1);
      const auto dropped = audio_queue_.PushDropOldest(
          {std::move(packet), false, true, sequence, encode_done_us});
      if (dropped > 0) {
        audio_dropped_packets_.fetch_add(dropped);
      }
    }
  }
  encoder.Stop();
  {
    std::scoped_lock route_lock(audio_route_mutex_);
    if (local_monitor_renderer_ == &local_monitor) {
      local_monitor_renderer_ = nullptr;
    }
  }
  local_monitor.Stop();
  local_monitor_active_.store(false);
  local_monitor_muted_.store(false);
  pc_local_audio_mute_applied_.store(false);
  capture.Stop();
}

void MirrorSession::SendLoop() {
  bool prefer_audio = false;
  while (running_) {
    QueuedVideoPacket video_packet;
    QueuedAudioPacket audio_packet;
    bool have_video = false;
    bool have_audio = false;
    if (prefer_audio) {
      have_audio = audio_queue_.TryPop(&audio_packet);
      if (!have_audio) {
        have_video = packet_queue_.TryPop(&video_packet);
      }
    } else {
      have_video = packet_queue_.TryPop(&video_packet);
      if (!have_video) {
        have_audio = audio_queue_.TryPop(&audio_packet);
      }
    }
    if (!have_video && !have_audio) {
      std::this_thread::sleep_for(std::chrono::milliseconds(2));
      continue;
    }

    const auto queued_us =
        have_video ? video_packet.encoded_done_us : audio_packet.encoded_done_us;
    const auto send_start_us = NowUs();
    const auto stale_video_age_us =
        std::max(kMinimumStaleVideoAgeUs, target_frame_interval_us_ * 3);
    if (have_video && video_packet.access_unit && !video_packet.key_frame &&
        video_packet.encoded_done_us + stale_video_age_us < send_start_us) {
      transport_dropped_frames_.fetch_add(1);
      transport_backpressure_dropped_frames_.fetch_add(1);
      stale_video_dropped_frames_.fetch_add(1);
      {
        std::scoped_lock status_lock(status_mutex_);
        RecordEvent(&stale_video_dropped_events_us_, send_start_us);
        RecordSample(&packet_writer_video_wait_samples_, send_start_us,
                     UsToMs(send_start_us - video_packet.encoded_done_us));
      }
      prefer_audio = true;
      continue;
    }
    TransportResult result;
    {
      std::scoped_lock send_lock(transport_send_mutex_);
      result = transport_.SendPacket(
          have_video ? video_packet.bytes : audio_packet.bytes);
    }
    if (!result.ok) {
      SetLastSendError(result.detail);
      SetSessionError("NETWORK_DISCONNECTED",
                      "Could not send video packets to the TV.",
                      result.detail);
      running_ = false;
      packet_queue_.Close();
      audio_queue_.Close();
      break;
    }
    const auto send_done_us = NowUs();
    packets_sent_.fetch_add(1);
    const auto packet_size =
        have_video ? video_packet.bytes.size() : audio_packet.bytes.size();
    bytes_sent_.fetch_add(static_cast<std::uint64_t>(packet_size));
    send_completed_bytes_.fetch_add(
        static_cast<std::uint64_t>(packet_size));
    {
      std::scoped_lock status_lock(status_mutex_);
      for (std::uint32_t index = 0; index < result.send_calls; ++index) {
        RecordEvent(&socket_send_call_events_us_, send_done_us);
      }
      RecordSample(&packet_send_duration_samples_, send_done_us,
                   UsToMs(result.duration_us));
      if (have_video && video_packet.access_unit) {
        RecordEvent(&sent_access_unit_events_us_, send_done_us);
        RecordSample(&access_unit_send_duration_samples_, send_done_us,
                     UsToMs(result.duration_us));
        RecordSample(&encode_to_send_samples_, send_done_us,
                     send_done_us >= video_packet.encoded_done_us
                         ? UsToMs(send_done_us - video_packet.encoded_done_us)
                         : 0.0);
      }
      if (have_video && queued_us <= send_start_us) {
        RecordSample(&packet_writer_video_wait_samples_, send_done_us,
                     UsToMs(send_start_us - queued_us));
      }
      if (have_audio && queued_us <= send_start_us) {
        RecordSample(&packet_writer_audio_wait_samples_, send_done_us,
                     UsToMs(send_start_us - queued_us));
      }
    }
    if (have_video && video_packet.key_frame) {
      key_frames_sent_.fetch_add(1);
    }
    if (have_video && video_packet.access_unit) {
      MarkFirstAccessUnitSent();
    }
    if (have_audio && audio_packet.access_unit) {
      sent_audio_packets_.fetch_add(1);
    }
    prefer_audio = have_video;
  }
}

void MirrorSession::ControlLoop() {
  while (running_) {
    std::string line;
    std::string error;
    if (!transport_.ReceiveControlLine(&line, &error)) {
      if (!error.empty() && running_) {
        SetLastSendError(error);
      }
      continue;
    }
    HandlePlaybackCommandLine(line);
  }
}

void MirrorSession::HandlePlaybackCommandLine(const std::string& line) {
  if (line.find("VIDEO_STATS") != std::string::npos) {
    receiver_presented_fps_recent_ =
        ExtractJsonDouble(line, "codecRenderedFpsRecent");
    receiver_received_fps_recent_ =
        ExtractJsonDouble(line, "receivedVideoFps");
    receiver_decoder_input_fps_recent_ =
        ExtractJsonDouble(line, "decoderInputFps");
    receiver_decoder_output_fps_recent_ =
        ExtractJsonDouble(line, "decoderOutputFps");
    receiver_decoder_output_released_ =
        ExtractJsonUint64(line, "decoderOutputReleased");
    receiver_decoder_output_released_immediate_ =
        ExtractJsonUint64(line, "decoderOutputReleasedImmediate");
    receiver_decoder_output_released_scheduled_ =
        ExtractJsonUint64(line, "decoderOutputReleasedScheduled");
    receiver_on_frame_rendered_callbacks_ =
        ExtractJsonUint64(line, "onFrameRenderedCallbackCount");
    receiver_video_render_mode_ =
        ExtractJsonString(line, "receiverVideoRenderMode");
    receiver_pts_interval_p50_ms_ =
        ExtractJsonDouble(line, "videoPtsIntervalP50Ms");
    receiver_pts_regression_count_ =
        ExtractJsonUint64(line, "videoPtsRegressionCount");
    receiver_access_unit_bytes_ = ExtractJsonUint64(line, "receiverAccessUnitBytes");
    receiver_codec_configs_received_ =
        ExtractJsonUint64(line, "receiverCodecConfigsReceived");
    receiver_key_frames_received_ = ExtractJsonUint64(line, "keyFramesReceived");
    receiver_decoder_configured_width_ =
        ExtractJsonUint64(line, "decoderConfiguredWidth");
    receiver_decoder_configured_height_ =
        ExtractJsonUint64(line, "decoderConfiguredHeight");
    receiver_decoder_output_width_ =
        ExtractJsonUint64(line, "decoderOutputWidth");
    receiver_decoder_output_height_ =
        ExtractJsonUint64(line, "decoderOutputHeight");
    receiver_decoder_crop_left_ = ExtractJsonInt(line, "decoderCropLeft");
    receiver_decoder_crop_top_ = ExtractJsonInt(line, "decoderCropTop");
    receiver_decoder_crop_right_ = ExtractJsonInt(line, "decoderCropRight");
    receiver_decoder_crop_bottom_ = ExtractJsonInt(line, "decoderCropBottom");
    receiver_decoder_format_change_count_ =
        ExtractJsonUint64(line, "decoderOutputFormatChangeCount");
    receiver_surface_width_ = ExtractJsonUint64(line, "decoderSurfaceWidth");
    receiver_surface_height_ = ExtractJsonUint64(line, "decoderSurfaceHeight");
    return;
  }
  if (line.find("\"type\":\"PLAYBACK_COMMAND\"") == std::string::npos &&
      line.find("\"type\": \"PLAYBACK_COMMAND\"") == std::string::npos) {
    return;
  }
  const auto command = ExtractJsonString(line, "command");
  const auto command_id = ExtractJsonUint64(line, "commandId");
  if (command_id == 0 || (command != "pause" && command != "resume")) {
    SendPlaybackError(command_id, command, "INVALID_MESSAGE",
                      "Unsupported playback command.");
    return;
  }

  const auto previous_id = last_playback_command_id_.load();
  if (command_id <= previous_id) {
    SendPlaybackAck(command_id, command, IsPaused() ? "paused" : "streaming");
    return;
  }
  last_playback_command_id_.store(command_id);

  if (command == "pause") {
    ApplyPause(command_id, command);
  } else {
    ApplyResume(command_id, command);
  }
}

void MirrorSession::ApplyPause(std::uint64_t command_id,
                               const std::string& command) {
  pause_requests_received_.fetch_add(1);
  paused_.store(true);
  packet_queue_.Clear();
  audio_queue_.Clear();
  {
    std::scoped_lock status_lock(status_mutex_);
    session_user_message_ = "Playback is paused by the TV remote.";
  }
  SendPlaybackAck(command_id, command, "paused");
}

void MirrorSession::ApplyResume(std::uint64_t command_id,
                                const std::string& command) {
  resume_requests_received_.fetch_add(1);
  packet_queue_.Clear();
  audio_queue_.Clear();
  {
    std::scoped_lock status_lock(status_mutex_);
    codec_config_sent_for_stream_.store(false);
    session_user_message_ = "Playback is resuming from a fresh IDR frame.";
  }
  resume_codec_config_resends_.fetch_add(1);
  audio_config_requested_.store(true);
  encoder_.RequestKeyFrame();
  paused_.store(false);
  SendPlaybackAck(command_id, command, "resuming");
}

void MirrorSession::SendPlaybackAck(std::uint64_t command_id,
                                    const std::string& command,
                                    const std::string& sender_state) {
  std::ostringstream stream;
  stream << "{\"type\":\"PLAYBACK_COMMAND_ACK\",\"protocolVersion\":1"
         << ",\"command\":\"" << JsonEscape(command) << "\""
         << ",\"commandId\":" << command_id << ",\"senderState\":\""
         << JsonEscape(sender_state) << "\"}";
  TransportResult result;
  {
    std::scoped_lock send_lock(transport_send_mutex_);
    result = transport_.SendControlLine(stream.str());
  }
  if (result.ok) {
    playback_command_acks_sent_.fetch_add(1);
  } else {
    playback_command_errors_sent_.fetch_add(1);
    SetLastSendError(result.detail);
  }
}

void MirrorSession::SendPlaybackError(std::uint64_t command_id,
                                      const std::string& command,
                                      const std::string& error_code,
                                      const std::string& message) {
  std::ostringstream stream;
  stream << "{\"type\":\"PLAYBACK_COMMAND_ERROR\",\"protocolVersion\":1"
         << ",\"command\":\"" << JsonEscape(command) << "\""
         << ",\"commandId\":" << command_id << ",\"errorCode\":\""
         << JsonEscape(error_code) << "\",\"message\":\""
         << JsonEscape(message) << "\"}";
  TransportResult result;
  {
    std::scoped_lock send_lock(transport_send_mutex_);
    result = transport_.SendControlLine(stream.str());
  }
  playback_command_errors_sent_.fetch_add(1);
  if (!result.ok) {
    SetLastSendError(result.detail);
  }
}

bool MirrorSession::SendCodecConfig(const H264ParameterSets& parameter_sets) {
  const auto config_packet =
      BuildH264CodecConfigPacket(0, parameter_sets, video_config_);
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

  TransportResult result;
  {
    std::scoped_lock send_lock(transport_send_mutex_);
    result = transport_.SendPacket(config_packet);
  }
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
  TransportResult result;
  {
    std::scoped_lock send_lock(transport_send_mutex_);
    result = transport_.SendPacket(packet);
  }
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
  CapturePipelineTimingSnapshot capture_timing;
  {
    std::scoped_lock lock(mutex_);
    capture_ready = capture_ != nullptr;
    if (capture_ != nullptr) {
      capture_timing = capture_->timing_snapshot();
    }
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
  snapshot.target_fps = target_fps_;
  snapshot.frame_pool_api = capture_timing.frame_pool_api;
  snapshot.frame_pool_buffer_count = capture_timing.frame_pool_buffer_count;
  snapshot.frame_arrived_callback_enter_count =
      capture_timing.frame_arrived_callback_enter_count;
  snapshot.frame_arrived_callback_exit_count =
      capture_timing.frame_arrived_callback_exit_count;
  snapshot.frame_arrived_callback_average_ms =
      capture_timing.frame_arrived_callback_average_ms;
  snapshot.frame_arrived_callback_p95_ms =
      capture_timing.frame_arrived_callback_p95_ms;
  snapshot.frame_arrived_callback_max_ms =
      capture_timing.frame_arrived_callback_max_ms;
  snapshot.frame_held_average_ms = capture_timing.frame_held_average_ms;
  snapshot.frame_held_p95_ms = capture_timing.frame_held_p95_ms;
  snapshot.frame_held_max_ms = capture_timing.frame_held_max_ms;
  snapshot.owned_texture_copy_fps = capture_timing.owned_texture_copy_fps;
  snapshot.owned_texture_copy_average_ms =
      capture_timing.owned_texture_copy_average_ms;
  snapshot.owned_texture_copy_p95_ms =
      capture_timing.owned_texture_copy_p95_ms;
  snapshot.worker_processing_average_ms =
      capture_timing.worker_processing_average_ms;
  snapshot.worker_processing_p95_ms =
      capture_timing.worker_processing_p95_ms;
  snapshot.handoff_slots = capture_timing.handoff_slots;
  snapshot.handoff_in_use = capture_timing.handoff_in_use;
  snapshot.worker_queue_depth = capture_timing.worker_queue_depth;
  snapshot.worker_frames_accepted = capture_timing.worker_frames_accepted;
  snapshot.worker_frames_processed = capture_timing.worker_frames_processed;
  snapshot.worker_frame_replacement_count =
      capture_timing.worker_frame_replacement_count;
  snapshot.worker_frame_drop_count = capture_timing.worker_frame_drop_count;
  snapshot.latest_frame_age_ms = capture_timing.latest_frame_age_ms;
  snapshot.capture_thread_id = capture_timing.capture_thread_id;
  snapshot.conversion_thread_id = capture_timing.conversion_thread_id;
  snapshot.callback_overlap_count = capture_timing.callback_overlap_count;
  snapshot.callback_reentrant_count = capture_timing.callback_reentrant_count;
  snapshot.d3d_multithread_protection_enabled =
      capture_timing.d3d_multithread_protection_enabled;
  snapshot.measured_delivery_bottleneck =
      capture_timing.measured_delivery_bottleneck;
  snapshot.capture_callback_fps =
      RollingFps(&capture_callback_events_us_, now_us);
  snapshot.captured_fps = RollingFps(&captured_events_us_, now_us);
  snapshot.target_admission_fps =
      RollingFps(&target_admission_events_us_, now_us);
  snapshot.admitted_frame_fps =
      RollingFps(&admitted_frame_events_us_, now_us);
  snapshot.converted_fps = RollingFps(&converted_events_us_, now_us);
  snapshot.encoder_accepted_fps =
      RollingFps(&encoder_accepted_events_us_, now_us);
  snapshot.encoder_input_fps = RollingFps(&encoder_input_events_us_, now_us);
  snapshot.encoded_fps = RollingFps(&encoded_events_us_, now_us);
  snapshot.sent_access_unit_fps =
      RollingFps(&sent_access_unit_events_us_, now_us);
  snapshot.sent_video_fps = snapshot.sent_access_unit_fps;
  snapshot.cadence_dropped_fps =
      RollingFps(&cadence_dropped_events_us_, now_us);
  snapshot.cadence_skipped_recent =
      static_cast<int>(cadence_dropped_events_us_.size());
  snapshot.cadence_skip_reason = cadence_skip_reason_;
  snapshot.encoder_busy_dropped_fps =
      RollingFps(&encoder_busy_dropped_events_us_, now_us);
  snapshot.conversion_busy_dropped_fps =
      RollingFps(&conversion_busy_dropped_events_us_, now_us);
  snapshot.capture_frame_interval_average_ms =
      AverageIntervalMs(&captured_events_us_, now_us);
  snapshot.capture_frame_interval_p95_ms =
      P95IntervalMs(&captured_events_us_, now_us);
  snapshot.encode_frame_interval_average_ms =
      AverageIntervalMs(&encoder_input_events_us_, now_us);
  snapshot.send_frame_interval_average_ms =
      AverageIntervalMs(&sent_access_unit_events_us_, now_us);
  snapshot.send_frame_interval_p95_ms =
      P95IntervalMs(&sent_access_unit_events_us_, now_us);
  snapshot.capture_to_convert_average_ms =
      AverageSampleMs(&capture_to_convert_samples_, now_us);
  snapshot.convert_to_encode_average_ms =
      AverageSampleMs(&convert_to_encode_samples_, now_us);
  snapshot.encode_duration_average_ms =
      AverageSampleMs(&encode_duration_samples_, now_us);
  snapshot.encode_duration_p95_ms =
      P95SampleMs(&encode_duration_samples_, now_us);
  snapshot.frame_arrived_callback_fps =
      capture_timing.frame_arrived_callback_fps;
  snapshot.try_get_next_frame_success_fps =
      capture_timing.try_get_next_frame_success_fps;
  snapshot.try_get_next_frame_null_count =
      capture_timing.try_get_next_frame_null_count;
  snapshot.raw_wgc_interval_p50_ms = capture_timing.raw_wgc_interval_p50_ms;
  snapshot.raw_wgc_interval_p95_ms = capture_timing.raw_wgc_interval_p95_ms;
  snapshot.frame_acquire_average_ms = capture_timing.frame_acquire_average_ms;
  snapshot.frame_acquire_p95_ms = capture_timing.frame_acquire_p95_ms;
  snapshot.copy_resource_average_ms =
      capture_timing.copy_resource_average_ms;
  snapshot.copy_resource_p95_ms = capture_timing.copy_resource_p95_ms;
  snapshot.map_readback_average_ms = capture_timing.map_readback_average_ms;
  snapshot.map_readback_p95_ms = capture_timing.map_readback_p95_ms;
  snapshot.scale_average_ms = capture_timing.scale_average_ms;
  snapshot.scale_p95_ms = capture_timing.scale_p95_ms;
  snapshot.bgra_to_nv12_average_ms =
      capture_timing.bgra_to_nv12_average_ms;
  snapshot.bgra_to_nv12_p95_ms = capture_timing.bgra_to_nv12_p95_ms;
  snapshot.worker_d3d_lock_wait_average_ms =
      capture_timing.worker_d3d_lock_wait_average_ms;
  snapshot.worker_d3d_lock_wait_p95_ms =
      capture_timing.worker_d3d_lock_wait_p95_ms;
  snapshot.worker_copy_resource_average_ms =
      capture_timing.worker_copy_resource_average_ms;
  snapshot.worker_copy_resource_p95_ms =
      capture_timing.worker_copy_resource_p95_ms;
  snapshot.worker_map_average_ms = capture_timing.worker_map_average_ms;
  snapshot.worker_map_p95_ms = capture_timing.worker_map_p95_ms;
  snapshot.worker_cpu_bgra_copy_average_ms =
      capture_timing.worker_cpu_bgra_copy_average_ms;
  snapshot.worker_cpu_bgra_copy_p95_ms =
      capture_timing.worker_cpu_bgra_copy_p95_ms;
  snapshot.worker_bgra_to_nv12_average_ms =
      capture_timing.worker_bgra_to_nv12_average_ms;
  snapshot.worker_bgra_to_nv12_p95_ms =
      capture_timing.worker_bgra_to_nv12_p95_ms;
  snapshot.worker_total_average_ms = capture_timing.worker_total_average_ms;
  snapshot.worker_total_p95_ms = capture_timing.worker_total_p95_ms;
  snapshot.encode_to_send_average_ms =
      AverageSampleMs(&encode_to_send_samples_, now_us);
  snapshot.video_queue_wait_average_ms =
      AverageSampleMs(&packet_writer_video_wait_samples_, now_us);
  snapshot.video_queue_wait_p95_ms =
      P95SampleMs(&packet_writer_video_wait_samples_, now_us);
  snapshot.captured_frames = captured_frames_.load();
  snapshot.capture_replaced_frames = capture_replaced_frames_.load();
  snapshot.cadence_skipped_frames = cadence_skipped_frames_.load();
  snapshot.conversion_backpressure_dropped_frames =
      conversion_backpressure_dropped_frames_.load();
  snapshot.encoder_backpressure_dropped_frames =
      encoder_backpressure_dropped_frames_.load();
  snapshot.transport_backpressure_dropped_frames =
      transport_backpressure_dropped_frames_.load();
  snapshot.stale_video_dropped_frames = stale_video_dropped_frames_.load();
  snapshot.receiver_max_fps = receiver_max_fps_;
  snapshot.shutdown_dropped_frames = shutdown_dropped_frames_.load();
  snapshot.total_dropped_frames =
      snapshot.capture_replaced_frames + snapshot.cadence_skipped_frames +
      snapshot.conversion_backpressure_dropped_frames +
      snapshot.encoder_backpressure_dropped_frames +
      snapshot.transport_backpressure_dropped_frames +
      snapshot.shutdown_dropped_frames;
  snapshot.capture_dropped_frames = capture_dropped_frames_.load();
  snapshot.conversion_dropped_frames = conversion_dropped_frames_.load();
  snapshot.encoder_input_dropped_frames =
      snapshot.cadence_skipped_frames +
      snapshot.conversion_backpressure_dropped_frames +
      snapshot.encoder_backpressure_dropped_frames +
      snapshot.shutdown_dropped_frames;
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
  snapshot.pending_send_bytes += audio_queue_.Sum(
      [](const QueuedAudioPacket& packet) { return packet.bytes.size(); });
  snapshot.last_socket_error = last_send_error_;
  snapshot.queue_depth_capture = 0;
  snapshot.queue_depth_encoder = 0;
  snapshot.queue_depth_transport =
      static_cast<int>(packet_queue_.Size());
  snapshot.audio_queue_depth = static_cast<int>(audio_queue_.Size());
  snapshot.last_capture_to_encode_ms = last_capture_to_encode_ms_;
  snapshot.average_capture_to_encode_ms =
      captured_frames_.load() == 0
          ? 0.0
          : total_capture_to_encode_ms_ /
                static_cast<double>(captured_frames_.load());
  snapshot.max_capture_to_encode_ms = max_capture_to_encode_ms_;
  snapshot.admitted_to_encoded_ratio =
      snapshot.admitted_frame_fps <= 0.0
          ? 0.0
          : snapshot.encoded_fps / snapshot.admitted_frame_fps;
  snapshot.selected_profile = video_config_.performance_profile;
  {
    std::ostringstream resolution;
    resolution << video_config_.width << "x" << video_config_.height;
    snapshot.output_resolution = resolution.str();
  }
  snapshot.current_bitrate_kbps = video_config_.bitrate_kbps;
  snapshot.requested_profile = requested_profile_;
  snapshot.applied_profile = applied_profile_;
  snapshot.profile_fallback_reason = profile_fallback_reason_;
  snapshot.output_width = video_config_.width;
  snapshot.output_height = video_config_.height;
  snapshot.target_bitrate_kbps = video_config_.bitrate_kbps;
  snapshot.target_frame_interval_ms = UsToMs(target_frame_interval_us_);
  snapshot.source_display_width = source_display_width_;
  snapshot.source_display_height = source_display_height_;
  snapshot.source_display_refresh_hz = source_display_refresh_hz_;
  snapshot.source_display_device_name = source_display_device_name_;
  snapshot.capture_system_relative_time_ns = latest_capture_system_relative_time_ns_;
  snapshot.sender_generated_pts_us = latest_sender_generated_pts_us_;
  snapshot.source_timestamp_delta_us = latest_source_timestamp_delta_us_;
  snapshot.video_pts_source = latest_video_pts_source_;
  snapshot.source_texture_width = latest_source_texture_width_;
snapshot.source_texture_height = latest_source_texture_height_;
snapshot.source_texture_format = latest_source_texture_format_;
snapshot.source_row_pitch = latest_source_row_pitch_;
snapshot.source_bgra_stride = latest_source_bgra_stride_;
snapshot.nv12_y_offset = latest_nv12_y_offset_;
snapshot.nv12_uv_offset = latest_nv12_uv_offset_;
snapshot.nv12_y_stride = latest_nv12_y_stride_;
snapshot.nv12_uv_stride = latest_nv12_uv_stride_;
snapshot.nv12_expected_bytes = latest_nv12_expected_bytes_;
snapshot.nv12_allocated_bytes = latest_nv12_allocated_bytes_;
snapshot.nv12_used_bytes = latest_nv12_used_bytes_;
snapshot.encoder_input_stride = latest_encoder_input_stride_;
  const auto source_intervals =
      RecentSampleValues(&source_frame_interval_samples_, now_us);
  snapshot.capture_interval_from_source_p50_ms = P50(source_intervals);
  snapshot.capture_interval_from_source_p95_ms = P95(source_intervals);
  snapshot.capture_interval_from_source_max_ms = Maximum(source_intervals);
  snapshot.stale_video_dropped_fps =
      RollingFps(&stale_video_dropped_events_us_, now_us);
  const auto encoder_diagnostics = encoder_.diagnostics();
  snapshot.selected_encoder_name = encoder_diagnostics.selected_encoder_name;
  snapshot.selected_encoder_hardware =
      encoder_diagnostics.selected_encoder_hardware;
  snapshot.encoder_name = encoder_diagnostics.selected_encoder_name;
  snapshot.hardware_encoder_active =
      encoder_diagnostics.selected_encoder_hardware;
  snapshot.encoder_supports_requested_resolution =
      video_config_.width == requested_video_config_.width &&
      video_config_.height == requested_video_config_.height &&
      (!IsExperimental4k30(requested_video_config_) ||
       encoder_diagnostics.selected_encoder_hardware);
  snapshot.receiver_max_width = receiver_max_width_;
  snapshot.receiver_max_height = receiver_max_height_;
  snapshot.receiver_supports_4k30 = receiver_supports_4k30_;
  snapshot.capture_fps_recent = snapshot.capture_callback_fps;
  snapshot.conversion_fps_recent = snapshot.converted_fps;
  snapshot.encoder_input_fps_recent = snapshot.encoder_input_fps;
  snapshot.encoder_output_fps_recent = snapshot.encoded_fps;
  snapshot.transport_video_fps_recent = snapshot.sent_video_fps;
  snapshot.receiver_presented_fps_recent = receiver_presented_fps_recent_;
  snapshot.receiver_received_fps_recent = receiver_received_fps_recent_;
  snapshot.receiver_decoder_input_fps_recent = receiver_decoder_input_fps_recent_;
  snapshot.receiver_decoder_output_fps_recent = receiver_decoder_output_fps_recent_;
  snapshot.receiver_decoder_output_released = receiver_decoder_output_released_;
  snapshot.receiver_decoder_output_released_immediate = receiver_decoder_output_released_immediate_;
  snapshot.receiver_decoder_output_released_scheduled = receiver_decoder_output_released_scheduled_;
  snapshot.receiver_on_frame_rendered_callbacks = receiver_on_frame_rendered_callbacks_;
  snapshot.receiver_video_render_mode = receiver_video_render_mode_;
  snapshot.receiver_pts_interval_p50_ms = receiver_pts_interval_p50_ms_;
  snapshot.receiver_pts_regression_count = receiver_pts_regression_count_;
  snapshot.receiver_access_unit_bytes = receiver_access_unit_bytes_;
  snapshot.receiver_codec_configs_received = receiver_codec_configs_received_;
  snapshot.receiver_key_frames_received = receiver_key_frames_received_;
  snapshot.receiver_decoder_configured_width = receiver_decoder_configured_width_;
  snapshot.receiver_decoder_configured_height = receiver_decoder_configured_height_;
  snapshot.receiver_decoder_output_width = receiver_decoder_output_width_;
  snapshot.receiver_decoder_output_height = receiver_decoder_output_height_;
  snapshot.receiver_decoder_crop_left = receiver_decoder_crop_left_;
  snapshot.receiver_decoder_crop_top = receiver_decoder_crop_top_;
  snapshot.receiver_decoder_crop_right = receiver_decoder_crop_right_;
  snapshot.receiver_decoder_crop_bottom = receiver_decoder_crop_bottom_;
  snapshot.receiver_decoder_format_change_count = receiver_decoder_format_change_count_;
  snapshot.receiver_surface_width = receiver_surface_width_;
  snapshot.receiver_surface_height = receiver_surface_height_;
  snapshot.conversion_duration_p95_ms =
      P95SampleMs(&capture_to_convert_samples_, now_us);
  snapshot.encoder_queue_wait_p95_ms = snapshot.video_queue_wait_p95_ms;
  snapshot.transport_send_p95_ms = snapshot.access_unit_send_duration_p95_ms;
  snapshot.mft_input_stream_flags = encoder_diagnostics.mft_input_stream_flags;
snapshot.mft_does_not_addref = encoder_diagnostics.mft_does_not_addref;
snapshot.mft_holds_buffers = encoder_diagnostics.mft_holds_buffers;
snapshot.mft_input_buffer_size = encoder_diagnostics.mft_input_buffer_size;
snapshot.mft_input_buffer_alignment = encoder_diagnostics.mft_input_buffer_alignment;
snapshot.encoder_input_sample_id = encoder_diagnostics.encoder_input_sample_id;
snapshot.encoder_input_buffer_id = encoder_diagnostics.encoder_input_buffer_id;
snapshot.input_sample_create_count = encoder_diagnostics.input_sample_create_count;
snapshot.input_buffer_create_count = encoder_diagnostics.input_buffer_create_count;
snapshot.input_buffer_pool_size = encoder_diagnostics.input_buffer_pool_size;
snapshot.input_buffers_in_flight = encoder_diagnostics.input_buffers_in_flight;
snapshot.input_buffer_reuse_count = encoder_diagnostics.input_buffer_reuse_count;
snapshot.unsafe_input_buffer_reuse_detected =
    encoder_diagnostics.unsafe_input_buffer_reuse_detected;
snapshot.nv12_guard_corruption_count =
    encoder_diagnostics.nv12_guard_corruption_count;
snapshot.key_frame_count = encoder_diagnostics.key_frame_count;
snapshot.frames_since_last_key_frame =
    encoder_diagnostics.frames_since_last_key_frame;
snapshot.last_key_frame_pts_us = encoder_diagnostics.last_key_frame_pts_us;
snapshot.last_key_frame_size_bytes =
    encoder_diagnostics.last_key_frame_size_bytes;
snapshot.last_key_frame_interval_frames =
    encoder_diagnostics.last_key_frame_interval_frames;
snapshot.last_key_frame_interval_ms =
    encoder_diagnostics.last_key_frame_interval_ms;
snapshot.keyframe_interval_frames = encoder_diagnostics.keyframe_interval_frames;
snapshot.encoded_access_unit_bytes = encoded_access_unit_bytes_;
snapshot.transported_access_unit_bytes = transported_access_unit_bytes_;
snapshot.video_au_size_mismatch_count = video_au_size_mismatch_count_;
snapshot.video_fragment_missing_count = 0;
snapshot.video_au_reassembly_error_count = 0;
snapshot.receiver_access_unit_bytes = receiver_access_unit_bytes_;
snapshot.receiver_key_frames_received = receiver_key_frames_received_;
snapshot.receiver_codec_configs_received = receiver_codec_configs_received_;
  snapshot.selected_encoder_async =
      encoder_diagnostics.selected_encoder_async;
  snapshot.encoder_d3d11_aware = encoder_diagnostics.encoder_d3d11_aware;
  snapshot.encoder_input_format = encoder_diagnostics.encoder_input_format;
  snapshot.encoder_output_format = encoder_diagnostics.encoder_output_format;
  snapshot.average_encode_duration_ms = snapshot.encode_duration_average_ms;
  snapshot.encoder_backpressure_count =
      encoder_diagnostics.encoder_backpressure_count;
  snapshot.encoder_not_accepting_count =
      encoder_diagnostics.process_input_not_accepting;
  snapshot.process_input_calls = encoder_diagnostics.process_input_calls;
  snapshot.process_input_accepted =
      encoder_diagnostics.process_input_accepted;
  snapshot.process_input_not_accepting =
      encoder_diagnostics.process_input_not_accepting;
  snapshot.process_input_retries = encoder_diagnostics.process_input_retries;
  snapshot.process_output_calls = encoder_diagnostics.process_output_calls;
  snapshot.process_output_frames = encoder_diagnostics.process_output_frames;
  snapshot.process_input_duration_average_ms =
      encoder_diagnostics.process_input_duration_average_ms;
  snapshot.process_input_duration_p95_ms =
      encoder_diagnostics.process_input_duration_p95_ms;
  snapshot.process_input_average_ms =
      encoder_diagnostics.process_input_duration_average_ms;
  snapshot.process_input_p95_ms =
      encoder_diagnostics.process_input_duration_p95_ms;
  snapshot.nv12_copy_average_ms =
      encoder_diagnostics.nv12_copy_duration_average_ms;
  snapshot.nv12_copy_p95_ms = encoder_diagnostics.nv12_copy_duration_p95_ms;
  snapshot.sample_prepare_average_ms =
      encoder_diagnostics.sample_prepare_duration_average_ms;
  snapshot.sample_prepare_p95_ms =
      encoder_diagnostics.sample_prepare_duration_p95_ms;
  snapshot.capture_to_encoder_ready_average_ms =
      encoder_diagnostics.capture_to_encoder_ready_average_ms;
  snapshot.capture_to_encoder_ready_p95_ms =
      encoder_diagnostics.capture_to_encoder_ready_p95_ms;
  snapshot.capture_bottleneck_stage_name =
      CaptureBottleneckStage(capture_timing, encoder_diagnostics);
  snapshot.process_output_duration_average_ms =
      encoder_diagnostics.process_output_duration_average_ms;
  snapshot.process_output_duration_p95_ms =
      encoder_diagnostics.process_output_duration_p95_ms;
  snapshot.bgra_to_nv12_mode = "cpuBgraToNv12";
  snapshot.gpu_readback_per_frame = true;
  snapshot.texture_reuse_enabled = true;
  snapshot.low_latency_options_applied =
      encoder_diagnostics.low_latency_options_applied;
  snapshot.unsupported_encoder_options =
      encoder_diagnostics.unsupported_encoder_options;
  snapshot.bottleneck_summary = SenderBottleneckSummary(
      snapshot.capture_callback_fps, snapshot.admitted_frame_fps,
      snapshot.converted_fps, snapshot.encoder_accepted_fps,
      snapshot.encoded_fps, snapshot.sent_access_unit_fps,
      P95IntervalMs(&sent_access_unit_events_us_, now_us));
  snapshot.last_encode_error = last_encode_error_;
  snapshot.last_send_error = last_send_error_;
  snapshot.audio_enabled = audio_enabled_.load();
  snapshot.audio_capture_state =
      snapshot.audio_enabled ? audio_capture_state_ : "disabled";
  snapshot.audio_device_name = audio_device_name_;
  snapshot.audio_input_sample_rate = audio_input_sample_rate_;
  snapshot.audio_input_channels = audio_input_channels_;
  snapshot.audio_encoded_sample_rate = kAudioSampleRate;
  snapshot.audio_encoded_channels = kAudioChannels;
  snapshot.captured_audio_packets = captured_audio_packets_.load();
  snapshot.encoded_audio_packets = encoded_audio_packets_.load();
  snapshot.sent_audio_packets = sent_audio_packets_.load();
  snapshot.audio_capture_fps = RollingFps(&audio_capture_events_us_, now_us);
  snapshot.audio_encode_average_ms =
      AverageSampleMs(&audio_encode_duration_samples_, now_us);
  snapshot.audio_dropped_packets = audio_dropped_packets_.load();
  snapshot.audio_last_error = audio_last_error_;
  if (snapshot.audio_enabled) {
    snapshot.video_fps_audio_enabled = snapshot.sent_access_unit_fps;
  } else {
    snapshot.video_fps_audio_disabled = snapshot.sent_access_unit_fps;
  }
  snapshot.audio_cpu_time_ms = snapshot.audio_encode_average_ms;
  snapshot.packet_writer_video_wait_ms = snapshot.video_queue_wait_average_ms;
  snapshot.packet_writer_audio_wait_ms =
      AverageSampleMs(&packet_writer_audio_wait_samples_, now_us);
  snapshot.playback_state = IsPaused() ? "paused" : state;
  snapshot.pause_requests_received = pause_requests_received_.load();
  snapshot.resume_requests_received = resume_requests_received_.load();
  snapshot.playback_command_acks_sent = playback_command_acks_sent_.load();
  snapshot.playback_command_errors_sent =
      playback_command_errors_sent_.load();
  snapshot.resume_codec_config_resends =
      resume_codec_config_resends_.load();
  snapshot.pc_local_audio_mute_requested =
      pc_local_audio_mute_requested_.load();
  snapshot.pc_local_audio_mute_supported =
      pc_local_audio_mute_supported_.load();
  snapshot.pc_local_audio_mute_applied = pc_local_audio_mute_applied_.load();
  snapshot.pc_local_audio_original_mute_state = false;
  snapshot.audio_capture_active =
      snapshot.audio_enabled && snapshot.audio_capture_state == "capturing";
  snapshot.audio_encoder_active =
      snapshot.audio_capture_active && snapshot.audio_last_error.empty();
  snapshot.audio_transport_active =
      snapshot.audio_enabled && snapshot.signaling_ready &&
      session_error_code_ != "NETWORK_DISCONNECTED";
  snapshot.tv_audio_streaming =
      snapshot.audio_capture_active && snapshot.audio_encoder_active &&
      snapshot.audio_transport_active;
  snapshot.audio_routing_mode =
      snapshot.audio_enabled ? audio_routing_mode_ : "disabled";
  snapshot.tv_audio_source_device_id = tv_audio_source_device_id_;
  snapshot.tv_audio_source_device_name = tv_audio_source_device_name_;
  snapshot.pc_monitor_device_id = pc_monitor_device_id_;
  snapshot.pc_monitor_device_name = pc_monitor_device_name_;
  snapshot.local_monitor_active = local_monitor_active_.load();
  snapshot.local_monitor_muted = local_monitor_muted_.load();
  snapshot.local_monitor_queue_depth = local_monitor_queue_depth_.load();
  snapshot.local_monitor_dropped_buffers =
      local_monitor_dropped_buffers_.load();
  snapshot.audio_capture_format = audio_capture_format_;
  snapshot.audio_monitor_format = audio_monitor_format_;
  snapshot.audio_routing_unsupported_reason =
      audio_routing_unsupported_reason_;
  snapshot.audio_mute_unsupported_reason =
      snapshot.pc_local_audio_mute_supported
          ? std::string()
          : audio_routing_unsupported_reason_;
  snapshot.local_speaker_mute_mode =
      snapshot.pc_local_audio_mute_requested ? "pcLocalMuteRequested"
                                             : "pcAndTv";
  snapshot.local_speaker_mute_state =
      snapshot.pc_local_audio_mute_applied
          ? "muted"
          : (snapshot.pc_local_audio_mute_requested ? "unsupported"
                                                    : "disabled");
  snapshot.local_speaker_mute_last_error =
      snapshot.audio_mute_unsupported_reason;
  return snapshot;
}

NativeSnapshot MirrorSession::CurrentSnapshotLocked() {
  if (!session_error_code_.empty()) {
    return BuildSnapshot("failed", session_user_message_);
  }
  if (!running_) {
    return BuildSnapshot("idle", "Native sender resources were released.");
  }
  if (IsPaused()) {
    return BuildSnapshot("paused", "Playback is paused by the TV remote.");
  }
  if (!codec_config_sent_for_stream_.load() && first_access_unit_sent_) {
    return BuildSnapshot("resuming",
                         "Waiting to send SPS/PPS and a fresh IDR frame.");
  }
  if (first_access_unit_sent_) {
    std::ostringstream message;
    message << "Native " << video_config_.width << "x" << video_config_.height
            << " H.264 video path is running.";
    return BuildSnapshot("streaming", message.str());
  }
  return BuildSnapshot("negotiating",
                       "Waiting for the first encoded video frame.");
}

void MirrorSession::ResetCounters() {
  captured_frames_ = 0;
  capture_replaced_frames_ = 0;
  cadence_skipped_frames_ = 0;
  conversion_backpressure_dropped_frames_ = 0;
  encoder_backpressure_dropped_frames_ = 0;
  transport_backpressure_dropped_frames_ = 0;
  stale_video_dropped_frames_ = 0;
  shutdown_dropped_frames_ = 0;
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
  audio_enabled_ = false;
  pc_local_audio_mute_requested_ = false;
  pc_local_audio_mute_supported_ = false;
  pc_local_audio_mute_applied_ = false;
  local_monitor_active_ = false;
  local_monitor_muted_ = false;
  local_monitor_queue_depth_ = 0;
  local_monitor_dropped_buffers_ = 0;
  paused_ = false;
  audio_config_requested_ = false;
  captured_audio_packets_ = 0;
  encoded_audio_packets_ = 0;
  sent_audio_packets_ = 0;
  audio_dropped_packets_ = 0;
  pause_requests_received_ = 0;
  resume_requests_received_ = 0;
  playback_command_acks_sent_ = 0;
  playback_command_errors_sent_ = 0;
  resume_codec_config_resends_ = 0;
  last_playback_command_id_ = 0;
  std::scoped_lock status_lock(status_mutex_);
  capture_callback_events_us_.clear();
  captured_events_us_.clear();
  target_admission_events_us_.clear();
  admitted_frame_events_us_.clear();
  converted_events_us_.clear();
  encoder_accepted_events_us_.clear();
  encoder_input_events_us_.clear();
  encoded_events_us_.clear();
  sent_access_unit_events_us_.clear();
  cadence_dropped_events_us_.clear();
  encoder_busy_dropped_events_us_.clear();
  conversion_busy_dropped_events_us_.clear();
  stale_video_dropped_events_us_.clear();
  socket_send_call_events_us_.clear();
  audio_capture_events_us_.clear();
  capture_to_convert_samples_.clear();
  convert_to_encode_samples_.clear();
  encode_duration_samples_.clear();
  encode_to_send_samples_.clear();
  source_frame_interval_samples_.clear();
  last_source_timestamp_us_ = 0;
  packet_send_duration_samples_.clear();
  access_unit_send_duration_samples_.clear();
  audio_encode_duration_samples_.clear();
  packet_writer_video_wait_samples_.clear();
  packet_writer_audio_wait_samples_.clear();
  first_access_unit_sent_ = false;
  codec_config_sent_for_stream_ = false;
  cadence_limiter_.Reset();
  cadence_skip_reason_ = "unavailable";
  session_error_code_.clear();
  session_user_message_.clear();
  session_developer_message_.clear();
  last_encode_error_.clear();
  last_send_error_.clear();
  audio_capture_state_ = "disabled";
  audio_device_name_.clear();
  tv_audio_source_device_id_.clear();
  tv_audio_source_device_name_.clear();
  pc_monitor_device_id_.clear();
  pc_monitor_device_name_.clear();
  audio_routing_mode_ = "defaultRenderEndpointLoopback";
  audio_routing_unsupported_reason_.clear();
  audio_capture_format_.clear();
  audio_monitor_format_.clear();
  requested_profile_ = "lowLatency720p30";
  applied_profile_ = "lowLatency720p30";
  profile_fallback_reason_.clear();
  receiver_max_width_ = 0;
  receiver_max_fps_ = 0;
  source_display_width_ = 0;
  source_display_height_ = 0;
  source_display_refresh_hz_ = 0.0;
  source_display_device_name_.clear();
  latest_capture_system_relative_time_ns_ = 0;
  latest_sender_generated_pts_us_ = 0;
  latest_source_timestamp_delta_us_ = 0;
  latest_video_pts_source_ = "unavailable";
  latest_source_texture_width_ = 0;
  latest_source_texture_height_ = 0;
  latest_source_texture_format_ = "unavailable";
  latest_source_row_pitch_ = 0;
  latest_source_bgra_stride_ = 0;
  latest_nv12_y_offset_ = 0;
  latest_nv12_uv_offset_ = 0;
  latest_nv12_y_stride_ = 0;
  latest_nv12_uv_stride_ = 0;
  latest_nv12_expected_bytes_ = 0;
  latest_nv12_allocated_bytes_ = 0;
  latest_nv12_used_bytes_ = 0;
  latest_encoder_input_stride_ = 0;
  receiver_max_height_ = 0;
  receiver_supports_4k30_ = false;
  receiver_presented_fps_recent_ = 0.0;
  receiver_received_fps_recent_ = 0.0;
  receiver_decoder_input_fps_recent_ = 0.0;
  receiver_decoder_output_fps_recent_ = 0.0;
  receiver_decoder_output_released_ = 0;
  receiver_decoder_output_released_immediate_ = 0;
  receiver_decoder_output_released_scheduled_ = 0;
  receiver_on_frame_rendered_callbacks_ = 0;
  receiver_video_render_mode_ = "unavailable";
  receiver_pts_interval_p50_ms_ = 0.0;
  receiver_pts_regression_count_ = 0;
  receiver_access_unit_bytes_ = 0;
  receiver_key_frames_received_ = 0;
  receiver_codec_configs_received_ = 0;
  receiver_decoder_configured_width_ = 0;
  receiver_decoder_configured_height_ = 0;
  receiver_decoder_output_width_ = 0;
  receiver_decoder_output_height_ = 0;
  receiver_decoder_crop_left_ = 0;
  receiver_decoder_crop_top_ = 0;
  receiver_decoder_crop_right_ = 0;
  receiver_decoder_crop_bottom_ = 0;
  receiver_decoder_format_change_count_ = 0;
  receiver_surface_width_ = 0;
  receiver_surface_height_ = 0;
  receiver_access_unit_bytes_ = 0;
  receiver_key_frames_received_ = 0;
  receiver_codec_configs_received_ = 0;
  encoded_access_unit_bytes_ = 0;
  transported_access_unit_bytes_ = 0;
  video_au_size_mismatch_count_ = 0;
  audio_input_sample_rate_ = 0;
  audio_input_channels_ = 0;
  audio_last_error_.clear();
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
