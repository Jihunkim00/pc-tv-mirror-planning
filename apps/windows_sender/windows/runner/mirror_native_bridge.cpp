#include "mirror_native_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <mutex>
#include <string>

#include "native/display/display_enumerator.h"
#include "native/session/mirror_session.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

constexpr char kChannelName[] = "pc_tv_mirror/windows_sender";

std::string ReadString(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return {};
  }
  const auto* value = std::get_if<std::string>(&it->second);
  return value == nullptr ? std::string() : *value;
}

int ReadInt(const EncodableMap& map, const char* key, int fallback) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<int32_t>(&it->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

EncodableValue ToEncodable(const pctv::NativeSnapshot& snapshot) {
  EncodableMap map;
  map[EncodableValue("state")] = EncodableValue(snapshot.state);
  map[EncodableValue("userMessage")] = EncodableValue(snapshot.user_message);
  map[EncodableValue("captureReady")] = EncodableValue(snapshot.capture_ready);
  map[EncodableValue("encoderReady")] = EncodableValue(snapshot.encoder_ready);
  map[EncodableValue("signalingReady")] =
      EncodableValue(snapshot.signaling_ready);
  map[EncodableValue("nativeVideoPathReady")] =
      EncodableValue(snapshot.native_video_path_ready);
  if (!snapshot.error_code.empty()) {
    map[EncodableValue("errorCode")] = EncodableValue(snapshot.error_code);
  }
  if (!snapshot.developer_message.empty()) {
    map[EncodableValue("developerMessage")] =
        EncodableValue(snapshot.developer_message);
  }
  return EncodableValue(map);
}

class MirrorNativeBridge {
 public:
  void Handle(const MethodCall<EncodableValue>& call,
              std::unique_ptr<MethodResult<EncodableValue>> result) {
    if (call.method_name() == "listDisplays") {
      result->Success(pctv::ListDisplays());
      return;
    }

    if (call.method_name() == "startSession") {
      StartSession(call, std::move(result));
      return;
    }

    if (call.method_name() == "stopSession") {
      result->Success(ToEncodable(session_.Stop()));
      return;
    }

    result->NotImplemented();
  }

 private:
  void StartSession(const MethodCall<EncodableValue>& call,
                    std::unique_ptr<MethodResult<EncodableValue>> result) {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("INVALID_ARGUMENTS", "startSession expects an object");
      return;
    }

    pctv::StartSessionOptions options;
    options.receiver_host = ReadString(*args, "receiverHost");
    options.receiver_port = ReadInt(*args, "receiverPort", 50720);
    options.request_json = ReadString(*args, "requestJson");
    options.source_id = ReadString(*args, "sourceId");
    result->Success(ToEncodable(session_.Start(options)));
  }

  pctv::MirrorSession session_;
};

}  // namespace

void RegisterMirrorNativeBridge(flutter::FlutterEngine* engine) {
  static std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  auto bridge = std::make_shared<MirrorNativeBridge>();
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [bridge](const MethodCall<EncodableValue>& call,
               std::unique_ptr<MethodResult<EncodableValue>> result) {
        bridge->Handle(call, std::move(result));
      });
}
