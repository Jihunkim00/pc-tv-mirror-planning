#ifndef RUNNER_NATIVE_TRANSPORT_BOUNDED_QUEUE_H_
#define RUNNER_NATIVE_TRANSPORT_BOUNDED_QUEUE_H_

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

  void PushDropOldest(T value) {
    {
      std::scoped_lock lock(mutex_);
      if (closed_) {
        return;
      }
      while (items_.size() >= capacity_) {
        items_.pop_front();
      }
      items_.push_back(std::move(value));
    }
    available_.notify_one();
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

 private:
  std::size_t capacity_;
  std::mutex mutex_;
  std::condition_variable available_;
  std::deque<T> items_;
  bool closed_ = false;
};

}  // namespace pctv

#endif  // RUNNER_NATIVE_TRANSPORT_BOUNDED_QUEUE_H_
