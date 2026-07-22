#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include "native/transport/video_transport.h"

#include <ws2tcpip.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <sstream>

namespace pctv {
namespace {

constexpr std::uint32_t kPacketMagic = 0x5054564D;  // PTVM
constexpr std::uint32_t kConfigMagic = 0x48323634;  // H264
constexpr std::uint8_t kProtocolVersion = 1;
constexpr std::uint8_t kPacketTypeCodecConfig = 1;
constexpr std::uint8_t kPacketTypeAccessUnit = 2;
constexpr std::uint16_t kFlagKeyFrame = 1 << 0;
constexpr std::uint16_t kFlagCodecConfig = 1 << 1;
constexpr std::uint32_t kPacketHeaderLength = 24;
constexpr std::uint32_t kConfigHeaderLength = 24;
constexpr std::uint32_t kStageOneWidth = 1280;
constexpr std::uint32_t kStageOneHeight = 720;
constexpr std::uint32_t kStageOneFps = 30;
constexpr std::uint32_t kStageOneBitrateKbps = 4000;
constexpr std::uintptr_t kInvalidSocketValue = UINTPTR_MAX;

std::string LastWsaError(const char* operation) {
  std::ostringstream stream;
  stream << operation << " failed with WSA error " << WSAGetLastError();
  return stream.str();
}

void WriteU16(std::vector<std::uint8_t>& bytes,
              std::size_t offset,
              std::uint16_t value) {
  bytes[offset] = static_cast<std::uint8_t>((value >> 8) & 0xFF);
  bytes[offset + 1] = static_cast<std::uint8_t>(value & 0xFF);
}

void WriteU32(std::vector<std::uint8_t>& bytes,
              std::size_t offset,
              std::uint32_t value) {
  bytes[offset] = static_cast<std::uint8_t>((value >> 24) & 0xFF);
  bytes[offset + 1] = static_cast<std::uint8_t>((value >> 16) & 0xFF);
  bytes[offset + 2] = static_cast<std::uint8_t>((value >> 8) & 0xFF);
  bytes[offset + 3] = static_cast<std::uint8_t>(value & 0xFF);
}

void WriteU64(std::vector<std::uint8_t>& bytes,
              std::size_t offset,
              std::uint64_t value) {
  for (int index = 7; index >= 0; --index) {
    bytes[offset + (7 - index)] =
        static_cast<std::uint8_t>((value >> (index * 8)) & 0xFF);
  }
}

void WritePacketHeader(std::vector<std::uint8_t>& bytes,
                       std::uint8_t packet_type,
                       std::uint16_t flags,
                       std::uint64_t pts_us,
                       std::uint32_t sequence,
                       std::uint32_t payload_size) {
  const std::uint32_t packet_length = kPacketHeaderLength + payload_size;
  WriteU32(bytes, 0, packet_length);
  WriteU32(bytes, 4, kPacketMagic);
  bytes[8] = kProtocolVersion;
  bytes[9] = packet_type;
  WriteU16(bytes, 10, flags);
  WriteU64(bytes, 12, pts_us);
  WriteU32(bytes, 20, sequence);
  WriteU32(bytes, 24, payload_size);
}

}  // namespace

VideoTransportClient::VideoTransportClient() = default;

VideoTransportClient::~VideoTransportClient() {
  Close();
}

TransportResult VideoTransportClient::Connect(const std::string& host,
                                              int port,
                                              const std::string& control_json) {
  Close();

  WSADATA wsa_data;
  if (WSAStartup(MAKEWORD(2, 2), &wsa_data) != 0) {
    return {false, LastWsaError("WSAStartup")};
  }

  addrinfo hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;

  addrinfo* address_list = nullptr;
  const std::string port_text = std::to_string(port);
  const int lookup_result =
      getaddrinfo(host.c_str(), port_text.c_str(), &hints, &address_list);
  if (lookup_result != 0) {
    WSACleanup();
    return {false, "getaddrinfo failed for receiver host"};
  }

  for (addrinfo* candidate = address_list; candidate != nullptr;
       candidate = candidate->ai_next) {
    const SOCKET candidate_socket =
        socket(candidate->ai_family, candidate->ai_socktype,
               candidate->ai_protocol);
    if (candidate_socket == INVALID_SOCKET) {
      continue;
    }
    socket_ = static_cast<std::uintptr_t>(candidate_socket);

    DWORD timeout_ms = 3000;
    setsockopt(candidate_socket, SOL_SOCKET, SO_RCVTIMEO,
               reinterpret_cast<const char*>(&timeout_ms), sizeof(timeout_ms));
    setsockopt(candidate_socket, SOL_SOCKET, SO_SNDTIMEO,
               reinterpret_cast<const char*>(&timeout_ms), sizeof(timeout_ms));

    if (connect(candidate_socket, candidate->ai_addr,
                static_cast<int>(candidate->ai_addrlen)) == 0) {
      break;
    }

    closesocket(candidate_socket);
    socket_ = kInvalidSocketValue;
  }

  freeaddrinfo(address_list);

  if (socket_ == kInvalidSocketValue) {
    const auto detail = LastWsaError("connect");
    WSACleanup();
    return {false, detail};
  }

  const std::string payload = control_json + "\n";
  const auto send_result =
      SendAll(payload.data(), static_cast<int>(payload.size()));
  if (!send_result.ok) {
    Close();
    return send_result;
  }

  std::string response;
  std::array<char, 1> byte{};
  while (response.size() < 4096) {
    const int received =
        recv(static_cast<SOCKET>(socket_), byte.data(), 1, 0);
    if (received <= 0) {
      Close();
      return {false, LastWsaError("recv")};
    }
    if (byte[0] == '\n') {
      break;
    }
    response.push_back(byte[0]);
  }

  return {true, response};
}

TransportResult VideoTransportClient::SendPacket(
    const std::vector<std::uint8_t>& packet) {
  if (socket_ == kInvalidSocketValue) {
    return {false, "video transport is not connected"};
  }
  return SendAll(reinterpret_cast<const char*>(packet.data()),
                 static_cast<int>(packet.size()));
}

void VideoTransportClient::Close() {
  if (socket_ != kInvalidSocketValue) {
    const SOCKET socket_handle = static_cast<SOCKET>(socket_);
    shutdown(socket_handle, SD_BOTH);
    closesocket(socket_handle);
    socket_ = kInvalidSocketValue;
  }
  WSACleanup();
}

TransportResult VideoTransportClient::SendAll(const char* data, int length) {
  int offset = 0;
  while (offset < length) {
    const int sent =
        send(static_cast<SOCKET>(socket_), data + offset, length - offset, 0);
    if (sent == SOCKET_ERROR || sent == 0) {
      return {false, LastWsaError("send")};
    }
    offset += sent;
  }
  return {true, {}};
}

std::vector<std::uint8_t> BuildH264CodecConfigPacket(
    std::uint32_t sequence,
    const H264ParameterSets& parameter_sets) {
  if (!parameter_sets.complete() || parameter_sets.sps.size() > 0xFFFF ||
      parameter_sets.pps.size() > 0xFFFF) {
    return {};
  }

  const std::uint32_t payload_size =
      kConfigHeaderLength +
      static_cast<std::uint32_t>(parameter_sets.sps.size() +
                                 parameter_sets.pps.size());
  std::vector<std::uint8_t> bytes(4 + kPacketHeaderLength + payload_size);
  WritePacketHeader(bytes, kPacketTypeCodecConfig, kFlagCodecConfig, 0,
                    sequence, payload_size);

  const std::size_t payload = 4 + kPacketHeaderLength;
  WriteU32(bytes, payload, kConfigMagic);
  bytes[payload + 4] = kProtocolVersion;
  bytes[payload + 5] = 0x03;
  WriteU16(bytes, payload + 6, 0);
  WriteU16(bytes, payload + 8, static_cast<std::uint16_t>(kStageOneWidth));
  WriteU16(bytes, payload + 10, static_cast<std::uint16_t>(kStageOneHeight));
  WriteU16(bytes, payload + 12, static_cast<std::uint16_t>(kStageOneFps));
  WriteU16(bytes, payload + 14, 0);
  WriteU32(bytes, payload + 16, kStageOneBitrateKbps);
  WriteU16(bytes, payload + 20,
           static_cast<std::uint16_t>(parameter_sets.sps.size()));
  WriteU16(bytes, payload + 22,
           static_cast<std::uint16_t>(parameter_sets.pps.size()));
  const auto sps_begin =
      bytes.begin() + static_cast<std::ptrdiff_t>(payload + kConfigHeaderLength);
  std::copy(parameter_sets.sps.begin(), parameter_sets.sps.end(), sps_begin);
  std::copy(parameter_sets.pps.begin(), parameter_sets.pps.end(),
            sps_begin + static_cast<std::ptrdiff_t>(parameter_sets.sps.size()));
  return bytes;
}

std::vector<std::uint8_t> BuildAccessUnitPacket(std::uint32_t sequence,
                                                std::uint64_t pts_us,
                                                bool key_frame,
                                                const std::uint8_t* data,
                                                std::uint32_t size) {
  std::vector<std::uint8_t> bytes(4 + kPacketHeaderLength + size);
  WritePacketHeader(bytes, kPacketTypeAccessUnit,
                    key_frame ? kFlagKeyFrame : 0, pts_us, sequence, size);
  std::copy(data, data + size, bytes.begin() + 4 + kPacketHeaderLength);
  return bytes;
}

}  // namespace pctv
