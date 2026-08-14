#include "native/capture/latest_frame_handoff.h"

#include <cassert>
#include <string>

namespace {

void TestLatestFrameHandoff() {
  pctv::LatestFrameHandoff<std::string> handoff(2);
  assert(handoff.Push("old") == 0);
  assert(handoff.Push("middle") == 0);
  assert(handoff.Push("latest") == 1);
  std::string value;
  assert(handoff.Pop(&value));
  assert(value == "middle");
  assert(handoff.Pop(&value));
  assert(value == "latest");
  assert(!handoff.Pop(&value));
  assert(handoff.dropped_count() == 1);
}

void TestCaptureFrameSlotPool() {
  pctv::CaptureFrameSlotPool pool(3);
  const auto first = pool.ReserveLatest();
  assert(first.has_value());
  pool.Publish(*first);

  const auto replacement = pool.ReserveLatest();
  assert(replacement == first);
  assert(pool.replacement_count() == 1);
  pool.Publish(*replacement);

  const auto processing = pool.TakePending();
  assert(processing == first);
  const auto second = pool.ReserveLatest();
  assert(second.has_value());
  assert(second != processing);
  pool.Publish(*second);

  const auto processing_second = pool.TakePending();
  assert(processing_second == second);
  const auto third = pool.ReserveLatest();
  assert(third.has_value());
  assert(third != processing);
  assert(third != processing_second);
  pool.Publish(*third);
  const auto processing_third = pool.TakePending();
  assert(processing_third == third);

  assert(!pool.ReserveLatest().has_value());
  assert(pool.drop_count() == 1);
  pool.Release(*processing);
  pool.Release(*processing_second);
  pool.Release(*processing_third);
  assert(pool.in_use() == 0);

  pool.Reset();
  assert(pool.replacement_count() == 0);
  assert(pool.drop_count() == 0);
  assert(pool.queue_depth() == 0);
}

}  // namespace

int main() {
  TestLatestFrameHandoff();
  TestCaptureFrameSlotPool();
  return 0;
}