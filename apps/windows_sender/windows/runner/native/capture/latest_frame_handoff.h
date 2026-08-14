#ifndef RUNNER_NATIVE_CAPTURE_LATEST_FRAME_HANDOFF_H_
#define RUNNER_NATIVE_CAPTURE_LATEST_FRAME_HANDOFF_H_

#include <algorithm>
#include <cstddef>
#include <deque>
#include <optional>
#include <utility>
#include <vector>

namespace pctv {

template <typename T>
class LatestFrameHandoff {
 public:
  explicit LatestFrameHandoff(std::size_t capacity) : capacity_(capacity) {}

  std::size_t Push(T value) {
    std::size_t dropped = 0;
    while (items_.size() >= capacity_) {
      items_.pop_front();
      ++dropped;
    }
    items_.push_back(std::move(value));
    dropped_count_ += dropped;
    return dropped;
  }

  bool Pop(T* value) {
    if (items_.empty()) {
      return false;
    }
    *value = std::move(items_.front());
    items_.pop_front();
    return true;
  }

  void Clear() { items_.clear(); }

  std::size_t Size() const { return items_.size(); }

  std::size_t dropped_count() const { return dropped_count_; }

 private:
  std::size_t capacity_;
  std::deque<T> items_;
  std::size_t dropped_count_ = 0;
};

class CaptureFrameSlotPool {
 public:
  enum class SlotState { kFree, kReserved, kPending, kProcessing };

  explicit CaptureFrameSlotPool(std::size_t capacity)
      : states_(capacity, SlotState::kFree) {}

  void Reset() {
    std::fill(states_.begin(), states_.end(), SlotState::kFree);
    pending_slot_.reset();
    replacement_count_ = 0;
    drop_count_ = 0;
  }

  std::optional<std::size_t> ReserveLatest() {
    if (pending_slot_.has_value()) {
      const auto slot = *pending_slot_;
      pending_slot_.reset();
      states_[slot] = SlotState::kReserved;
      ++replacement_count_;
      return slot;
    }
    for (std::size_t index = 0; index < states_.size(); ++index) {
      if (states_[index] == SlotState::kFree) {
        states_[index] = SlotState::kReserved;
        return index;
      }
    }
    ++drop_count_;
    return std::nullopt;
  }

  void Publish(std::size_t slot) {
    states_[slot] = SlotState::kPending;
    pending_slot_ = slot;
  }

  std::optional<std::size_t> TakePending() {
    if (!pending_slot_.has_value()) {
      return std::nullopt;
    }
    const auto slot = *pending_slot_;
    pending_slot_.reset();
    states_[slot] = SlotState::kProcessing;
    return slot;
  }

  void Release(std::size_t slot) { states_[slot] = SlotState::kFree; }

  std::size_t capacity() const { return states_.size(); }

  std::size_t in_use() const {
    std::size_t result = 0;
    for (const auto state : states_) {
      if (state != SlotState::kFree) {
        ++result;
      }
    }
    return result;
  }

  std::size_t queue_depth() const { return pending_slot_.has_value() ? 1 : 0; }

  std::size_t replacement_count() const { return replacement_count_; }

  std::size_t drop_count() const { return drop_count_; }

  SlotState state(std::size_t slot) const { return states_[slot]; }

 private:
  std::vector<SlotState> states_;
  std::optional<std::size_t> pending_slot_;
  std::size_t replacement_count_ = 0;
  std::size_t drop_count_ = 0;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_CAPTURE_LATEST_FRAME_HANDOFF_H_