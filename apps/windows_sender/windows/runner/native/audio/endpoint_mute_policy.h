#ifndef RUNNER_NATIVE_AUDIO_ENDPOINT_MUTE_POLICY_H_
#define RUNNER_NATIVE_AUDIO_ENDPOINT_MUTE_POLICY_H_

namespace pctv {

// Tracks whether the application still owns the mute state it changed.
// This class has no Windows dependencies so its restore decisions can be
// tested independently from the Core Audio callback implementation.
class EndpointMutePolicy {
 public:
  void Begin(bool current_mute_state) {
    active_ = true;
    original_mute_state_ = current_mute_state;
    controlled_mute_state_ = current_mute_state;
    changed_by_app_ = false;
    external_override_ = false;
  }

  void RecordAppChange(bool mute_state) {
    controlled_mute_state_ = mute_state;
    changed_by_app_ = mute_state != original_mute_state_;
  }

  void RecordExternalChange() { external_override_ = true; }

  bool ShouldRestore(bool current_mute_state) const {
    return active_ && changed_by_app_ && !external_override_ &&
           current_mute_state == controlled_mute_state_;
  }

  bool active() const { return active_; }
  bool original_mute_state() const { return original_mute_state_; }
  bool expected_mute_state() const { return controlled_mute_state_; }
  bool changed_by_app() const { return changed_by_app_; }
  bool external_override() const { return external_override_; }

  void End() {
    active_ = false;
    changed_by_app_ = false;
  }

 private:
  bool active_ = false;
  bool original_mute_state_ = false;
  bool controlled_mute_state_ = false;
  bool changed_by_app_ = false;
  bool external_override_ = false;
};

}  // namespace pctv
#endif  // RUNNER_NATIVE_AUDIO_ENDPOINT_MUTE_POLICY_H_
