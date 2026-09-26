#include "native/audio/audio_endpoint_mute_controller.h"

#include <windows.h>

#include <iomanip>
#include <new>
#include <sstream>

namespace pctv {
namespace {

const GUID kPcTvMuteEventContext = {
    0x2f39550b,
    0x44b1,
    0x4dd8,
    {0x91, 0xd2, 0x35, 0x50, 0x89, 0xfa, 0x62, 0x14}};

std::string HResultDetail(const char* operation, HRESULT result) {
  std::ostringstream stream;
  stream << operation << " failed (HRESULT=0x" << std::hex << std::uppercase
         << static_cast<unsigned long>(result) << ')';
  return stream.str();
}

}  // namespace

class AudioEndpointMuteController::NotificationCallback final
    : public IAudioEndpointVolumeCallback {
 public:
  NotificationCallback(const GUID& own_context,
                       std::atomic_bool* external_change_pending,
                       std::atomic_bool* actual_muted)
      : own_context_(own_context),
        external_change_pending_(external_change_pending),
        actual_muted_(actual_muted) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID interface_id,
                                           void** object) override {
    if (object == nullptr) {
      return E_POINTER;
    }
    *object = nullptr;
    if (IsEqualIID(interface_id, __uuidof(IUnknown)) ||
        IsEqualIID(interface_id, __uuidof(IAudioEndpointVolumeCallback))) {
      *object = static_cast<IAudioEndpointVolumeCallback*>(this);
      AddRef();
      return S_OK;
    }
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return static_cast<ULONG>(InterlockedIncrement(&references_));
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG remaining = InterlockedDecrement(&references_);
    if (remaining == 0) {
      delete this;
    }
    return static_cast<ULONG>(remaining);
  }

  HRESULT STDMETHODCALLTYPE OnNotify(
      PAUDIO_VOLUME_NOTIFICATION_DATA notification) override {
    if (notification == nullptr) {
      return E_POINTER;
    }
    if (!IsEqualGUID(notification->guidEventContext, own_context_) &&
        (notification->bMuted != FALSE) != actual_muted_->load()) {
      external_change_pending_->store(true);
    }
    return S_OK;
  }

 private:
  volatile LONG references_ = 1;
  const GUID own_context_;
  std::atomic_bool* const external_change_pending_;
  std::atomic_bool* const actual_muted_;
};

AudioEndpointMuteController::~AudioEndpointMuteController() {
  std::string error_code;
  std::string error;
  Stop(&error_code, &error);
}

bool AudioEndpointMuteController::Start(IMMDevice* endpoint,
                                        std::string* error_code,
                                        std::string* error) {
  ResetError(error_code, error);
  if (started()) {
    return true;
  }
  if (endpoint == nullptr) {
    *error_code = "endpoint_unavailable";
    *error = "Audio capture endpoint is unavailable";
    return false;
  }

  HRESULT result = endpoint->Activate(__uuidof(IAudioEndpointVolume),
                                      CLSCTX_ALL, nullptr,
                                      endpoint_volume_.put_void());
  if (FAILED(result)) {
    *error_code = "endpoint_volume_unavailable";
    *error = HResultDetail("IMMDevice::Activate(IAudioEndpointVolume)",
                           result);
    endpoint_volume_ = nullptr;
    return false;
  }

  callback_ = new (std::nothrow) NotificationCallback(
      kPcTvMuteEventContext, &external_change_pending_, &actual_muted_);
  if (callback_ == nullptr) {
    *error_code = "callback_unavailable";
    *error = "Could not allocate the endpoint volume notification callback";
    endpoint_volume_ = nullptr;
    return false;
  }
  result = endpoint_volume_->RegisterControlChangeNotify(callback_);
  if (FAILED(result)) {
    *error_code = "callback_registration_failed";
    *error = HResultDetail(
        "IAudioEndpointVolume::RegisterControlChangeNotify", result);
    callback_->Release();
    callback_ = nullptr;
    endpoint_volume_ = nullptr;
    return false;
  }

  bool muted = false;
  if (!ReadMuteState(&muted, error_code, error)) {
    Stop(nullptr, nullptr);
    return false;
  }
  actual_muted_.store(muted);
  external_change_pending_.store(false);
  return true;
}

bool AudioEndpointMuteController::ApplyRequestedState(
    bool requested,
    std::string* error_code,
    std::string* error) {
  ResetError(error_code, error);
  if (!started()) {
    *error_code = "endpoint_volume_unavailable";
    *error = "Audio endpoint volume control is not initialized";
    return false;
  }

  bool current = false;
  if (!ReadMuteState(&current, error_code, error)) {
    return false;
  }
  actual_muted_.store(current);
  if (external_change_pending_.exchange(false) && policy_.active()) {
    policy_.RecordExternalChange();
  }
  if (policy_.active() && current != policy_.expected_mute_state()) {
    policy_.RecordExternalChange();
  }

  if (requested) {
    if (!policy_.active()) {
      external_change_pending_.store(false);
      policy_.Begin(current);
      if (!current) {
        if (!WriteMuteState(true, error_code, error)) {
          policy_.End();
          return false;
        }
        policy_.RecordAppChange(true);
        actual_muted_.store(true);
      }
    }
    return true;
  }

  if (!policy_.active()) {
    return true;
  }
  if (policy_.ShouldRestore(current)) {
    if (!WriteMuteState(policy_.original_mute_state(), error_code, error)) {
      return false;
    }
    actual_muted_.store(policy_.original_mute_state());
  }
  policy_.End();
  return true;
}

bool AudioEndpointMuteController::Stop(std::string* error_code,
                                        std::string* error) {
  ResetError(error_code, error);
  bool restored = true;
  if (started() && policy_.active()) {
    restored = ApplyRequestedState(false, error_code, error);
    if (!restored) {
      std::string retry_error_code;
      std::string retry_error;
      restored = ApplyRequestedState(false, &retry_error_code, &retry_error);
      if (restored) {
        ResetError(error_code, error);
      } else {
        if (error_code != nullptr) {
          *error_code = retry_error_code;
        }
        if (error != nullptr) {
          *error = retry_error;
        }
      }
    }
  }
  if (endpoint_volume_ && callback_ != nullptr) {
    const HRESULT result =
        endpoint_volume_->UnregisterControlChangeNotify(callback_);
    if (FAILED(result) && restored) {
      if (error_code != nullptr) {
        *error_code = "callback_unregistration_failed";
      }
      if (error != nullptr) {
        *error = HResultDetail(
            "IAudioEndpointVolume::UnregisterControlChangeNotify", result);
      }
      restored = false;
    }
    callback_->Release();
    callback_ = nullptr;
  }
  endpoint_volume_ = nullptr;
  policy_.End();
  return restored;
}

bool AudioEndpointMuteController::ReadMuteState(
    bool* muted,
    std::string* error_code,
    std::string* error) {
  BOOL value = FALSE;
  const HRESULT result = endpoint_volume_->GetMute(&value);
  if (FAILED(result)) {
    *error_code = "get_mute_failed";
    *error = HResultDetail("IAudioEndpointVolume::GetMute", result);
    return false;
  }
  *muted = value != FALSE;
  return true;
}

bool AudioEndpointMuteController::WriteMuteState(
    bool muted,
    std::string* error_code,
    std::string* error) {
  const HRESULT result = endpoint_volume_->SetMute(
      muted ? TRUE : FALSE, &kPcTvMuteEventContext);
  if (FAILED(result)) {
    *error_code = muted ? "set_mute_failed" : "restore_failed";
    *error = HResultDetail("IAudioEndpointVolume::SetMute", result);
    return false;
  }
  return true;
}

void AudioEndpointMuteController::ResetError(std::string* error_code,
                                             std::string* error) {
  if (error_code != nullptr) {
    error_code->clear();
  }
  if (error != nullptr) {
    error->clear();
  }
}

}  // namespace pctv
