#ifndef RUNNER_NATIVE_TRANSPORT_VIDEO_TRANSPORT_H_
#define RUNNER_NATIVE_TRANSPORT_VIDEO_TRANSPORT_H_

#include <cstdint>
#include <string>
#include <vector>

#include "native/video/video_types.h"

namespace pctv {

struct TransportResult {
  bool ok = false;
  std::string detail;
  std::uint32_t send_calls = 0;
  std::uint64_t duration_us = 0;
  std::uint32_t bytes_sent = 0;
};

class VideoTransportClient {
 public:
  VideoTransportClient();
  ~VideoTransportClient();

  VideoTransportClient(const VideoTransportClient&) = delete;
  VideoTransportClient& operator=(const VideoTransportClient&) = delete;

  TransportResult Connect(const std::string& host,
                          int port,
                          const std::string& control_json);
  TransportResult SendPacket(const std::vector<std::uint8_t>& packet);
  TransportResult SendControlLine(const std::string& json_line);
  bool ReceiveControlLine(std::string* json_line, std::string* error);
  void Close();
  bool connected() const { return socket_ != UINTPTR_MAX; }

 private:
  TransportResult SendAll(const char* data, int length);

  std::uintptr_t socket_ = UINTPTR_MAX;
};

std::vector<std::uint8_t> BuildH264CodecConfigPacket(
    std::uint64_t sequence,
    const H264ParameterSets& parameter_sets,
    const VideoStreamConfig& config);
std::vector<std::uint8_t> BuildAccessUnitPacket(std::uint64_t sequence,
                                                std::uint64_t pts_us,
                                                bool key_frame,
                                                const std::uint8_t* data,
                                                std::uint32_t size);
std::vector<std::uint8_t> BuildAacCodecConfigPacket(
    std::uint64_t sequence,
    std::uint64_t stream_start_pts_us,
    const std::vector<std::uint8_t>& codec_specific_data);
std::vector<std::uint8_t> BuildAudioAccessUnitPacket(std::uint64_t sequence,
                                                     std::uint64_t pts_us,
                                                     const std::uint8_t* data,
                                                     std::uint32_t size);
std::vector<std::uint8_t> BuildAudioEndOfStreamPacket(std::uint64_t sequence,
                                                      std::uint64_t pts_us);

}  // namespace pctv

#endif  // RUNNER_NATIVE_TRANSPORT_VIDEO_TRANSPORT_H_
