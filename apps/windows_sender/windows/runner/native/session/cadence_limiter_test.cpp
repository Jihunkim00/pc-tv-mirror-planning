#include "native/session/cadence_limiter.h"

#include <cassert>
#include <cstdint>

namespace {

int CountAccepted(std::uint64_t source_interval_us,
                  std::uint64_t target_interval_us,
                  int frame_count) {
  pctv::CadenceLimiter limiter(target_interval_us);
  int accepted = 0;
  for (int index = 0; index < frame_count; ++index) {
    const auto decision = limiter.Admit(
        static_cast<std::uint64_t>(index) * source_interval_us,
        static_cast<std::uint64_t>(index) * source_interval_us, true);
    accepted += decision.admitted ? 1 : 0;
  }
  return accepted;
}

void TestCadenceScenarios() {
  assert(CountAccepted(16'667, 33'333, 120) >= 58);
  assert(CountAccepted(27'778, 33'333, 120) >= 58);
  assert(CountAccepted(33'333, 33'333, 120) == 120);
  assert(CountAccepted(41'667, 41'667, 120) == 120);
  assert(CountAccepted(50'000, 33'333, 120) == 120);

  pctv::CadenceLimiter limiter(33'333);
  const auto first = limiter.Admit(0, 0, true);
  const auto next = limiter.Admit(16'667, 16'667, true);
  assert(first.admitted);
  assert(!next.admitted);
  assert(next.reason == pctv::CadenceSkipReason::kSourceAboveTarget);
}

}  // namespace

int main() {
  TestCadenceScenarios();
  return 0;
}
