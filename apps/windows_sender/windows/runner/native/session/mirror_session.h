#ifndef RUNNER_NATIVE_SESSION_MIRROR_SESSION_H_
#define RUNNER_NATIVE_SESSION_MIRROR_SESSION_H_

#include "native/capture/display_capture.h"
#include "native/session/session_types.h"
#include "native/transport/bounded_queue.h"
#include "native/transport/video_transport.h"
#include "native/video/h264_encoder.h"

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace pctv {

class MirrorSession {
 public:
  NativeSnapshot Start(const StartSessionOptions& options);
  NativeSnapshot Stop();

 private:
  void EncodeLoop();
  void SendLoop();

  std::mutex mutex_;
  std::atomic_bool running_{false};
  std::string last_source_id_;
  BoundedQueue<std::vector<std::uint8_t>> packet_queue_{4};
  std::unique_ptr<DisplayCapture> capture_;
  H264Encoder encoder_;
  VideoTransportClient transport_;
  std::thread encode_thread_;
  std::thread send_thread_;
  std::atomic_uint32_t next_sequence_{1};
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_SESSION_MIRROR_SESSION_H_
