#ifndef RUNNER_NATIVE_SESSION_CADENCE_LIMITER_H_
#define RUNNER_NATIVE_SESSION_CADENCE_LIMITER_H_

#include <cstdint>

namespace pctv {

enum class CadenceSkipReason {
  kUnavailable,
  kFallbackClock,
  kSourceBelowOrEqualTarget,
  kSourceAboveTarget,
  kSourceGap,
  kSourceAboveTargetAccepted,
};

struct CadenceDecision {
  bool admitted = false;
  CadenceSkipReason reason = CadenceSkipReason::kUnavailable;
};

inline const char* CadenceSkipReasonText(CadenceSkipReason reason) {
  switch (reason) {
    case CadenceSkipReason::kFallbackClock:
      return "fallback_clock";
    case CadenceSkipReason::kSourceBelowOrEqualTarget:
      return "source_below_or_equal_target";
    case CadenceSkipReason::kSourceAboveTarget:
      return "source_above_target";
    case CadenceSkipReason::kSourceGap:
      return "source_gap";
    case CadenceSkipReason::kSourceAboveTargetAccepted:
      return "source_above_target_accepted";
    case CadenceSkipReason::kUnavailable:
      return "unavailable";
  }
  return "unavailable";
}

class CadenceLimiter {
 public:
  explicit CadenceLimiter(std::uint64_t target_interval_us = 33'333,
                           std::uint64_t tolerance_us = 1'500)
      : target_interval_us_(target_interval_us), tolerance_us_(tolerance_us) {}

  void SetTargetIntervalUs(std::uint64_t target_interval_us) {
    target_interval_us_ = target_interval_us;
    Reset();
  }

  void Reset() {
    next_deadline_us_ = 0;
    last_timeline_us_ = 0;
    timeline_initialized_ = false;
    source_pts_valid_ = false;
  }

  CadenceDecision Admit(std::uint64_t capture_us,
                        std::uint64_t source_pts_us,
                        bool source_pts_valid) {
    const auto timeline_us = source_pts_valid ? source_pts_us : capture_us;
    if (!timeline_initialized_ || source_pts_valid_ != source_pts_valid) {
      timeline_initialized_ = true;
      source_pts_valid_ = source_pts_valid;
      last_timeline_us_ = timeline_us;
      next_deadline_us_ = timeline_us + target_interval_us_;
      return {true, source_pts_valid
                          ? CadenceSkipReason::kSourceBelowOrEqualTarget
                          : CadenceSkipReason::kFallbackClock};
    }

    const auto source_interval_us =
        timeline_us >= last_timeline_us_ ? timeline_us - last_timeline_us_ : 0;
    last_timeline_us_ = timeline_us;
    const bool source_is_at_or_below_target =
        source_interval_us + tolerance_us_ >= target_interval_us_;
    if (source_is_at_or_below_target) {
      next_deadline_us_ = timeline_us + target_interval_us_;
      return {true, CadenceSkipReason::kSourceBelowOrEqualTarget};
    }
    if (timeline_us + tolerance_us_ < next_deadline_us_) {
      return {false, CadenceSkipReason::kSourceAboveTarget};
    }
    if (timeline_us > next_deadline_us_ + target_interval_us_) {
      next_deadline_us_ = timeline_us + target_interval_us_;
      return {true, CadenceSkipReason::kSourceGap};
    }
    next_deadline_us_ += target_interval_us_;
    return {true, CadenceSkipReason::kSourceAboveTargetAccepted};
  }

 private:
  std::uint64_t target_interval_us_;
  std::uint64_t tolerance_us_;
  std::uint64_t next_deadline_us_ = 0;
  std::uint64_t last_timeline_us_ = 0;
  bool timeline_initialized_ = false;
  bool source_pts_valid_ = false;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_SESSION_CADENCE_LIMITER_H_
