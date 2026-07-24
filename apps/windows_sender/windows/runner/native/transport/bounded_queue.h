#ifndef RUNNER_NATIVE_TRANSPORT_BOUNDED_QUEUE_H_
#define RUNNER_NATIVE_TRANSPORT_BOUNDED_QUEUE_H_

#include <algorithm>
#include <condition_variable>
#include <cstddef>
#include <deque>
#include <mutex>
#include <utility>

namespace pctv {

template <typename T>
class BoundedQueue {
 public:
  explicit BoundedQueue(std::size_t capacity) : capacity_(capacity) {}

  std::size_t PushDropOldest(T value) {
    std::size_t dropped = 0;
    {
      std::scoped_lock lock(mutex_);
      if (closed_) {
        return 0;
      }
      while (items_.size() >= capacity_) {
        items_.pop_front();
        ++dropped;
      }
      items_.push_back(std::move(value));
    }
    available_.notify_one();
    return dropped;
  }

  template <typename ShouldDropOld, typename ShouldDropIncoming>
  std::size_t PushDropOldestWhere(T value,
                                  ShouldDropOld should_drop_old,
                                  ShouldDropIncoming should_drop_incoming,
                                  bool* pushed) {
    std::size_t dropped = 0;
    {
      std::scoped_lock lock(mutex_);
      if (closed_) {
        *pushed = false;
        return 0;
      }
      while (items_.size() >= capacity_) {
        const auto old_item =
            std::find_if(items_.begin(), items_.end(), should_drop_old);
        if (old_item == items_.end()) {
          if (should_drop_incoming(value)) {
            *pushed = false;
            return dropped;
          }
          break;
        }
        items_.erase(old_item);
        ++dropped;
      }
      items_.push_back(std::move(value));
      *pushed = true;
    }
    available_.notify_one();
    return dropped;
  }

  bool Pop(T* value) {
    std::unique_lock lock(mutex_);
    available_.wait(lock, [&]() { return closed_ || !items_.empty(); });
    if (items_.empty()) {
      return false;
    }
    *value = std::move(items_.front());
    items_.pop_front();
    return true;
  }

  void Close() {
    {
      std::scoped_lock lock(mutex_);
      closed_ = true;
      items_.clear();
    }
    available_.notify_all();
  }

  void Reset() {
    std::scoped_lock lock(mutex_);
    closed_ = false;
    items_.clear();
  }

  std::size_t Size() const {
    std::scoped_lock lock(mutex_);
    return items_.size();
  }

 private:
  std::size_t capacity_;
  mutable std::mutex mutex_;
  std::condition_variable available_;
  std::deque<T> items_;
  bool closed_ = false;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_TRANSPORT_BOUNDED_QUEUE_H_
