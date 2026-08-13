#include "native/display/display_enumerator.h"

#include <string>

namespace pctv {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }

  const int size = WideCharToMultiByte(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (size <= 0) {
    return {};
  }

  std::string result(size, static_cast<char>(0));
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

double CurrentDisplayRefreshRate(const std::wstring& device_name) {
  DEVMODEW mode{};
  mode.dmSize = sizeof(mode);
  if (!device_name.empty() &&
      EnumDisplaySettingsW(device_name.c_str(), ENUM_CURRENT_SETTINGS, &mode) &&
      mode.dmDisplayFrequency > 1) {
    return static_cast<double>(mode.dmDisplayFrequency);
  }
  return 0.0;
}
namespace {

struct MonitorEnumeration {
  EncodableList displays;
  int next_index = 1;
};

struct MonitorSearch {
  std::string source_id;
  HMONITOR monitor = nullptr;
  int next_index = 1;
};

BOOL CALLBACK MonitorEnumProc(HMONITOR monitor,
                              HDC,
                              LPRECT,
                              LPARAM user_data) {
  auto* enumeration = reinterpret_cast<MonitorEnumeration*>(user_data);

  MONITORINFOEXW info;
  info.cbSize = sizeof(MONITORINFOEXW);
  if (!GetMonitorInfoW(monitor, &info)) {
    return TRUE;
  }
  const double refresh_rate_hz = CurrentDisplayRefreshRate(info.szDevice);

  const RECT monitor_rect = info.rcMonitor;
  const int width = monitor_rect.right - monitor_rect.left;
  const int height = monitor_rect.bottom - monitor_rect.top;
  const bool primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
  const std::string device_name = WideToUtf8(info.szDevice);
  const std::string id =
      device_name.empty()
          ? "DISPLAY" + std::to_string(enumeration->next_index)
          : device_name;

  EncodableMap display;
  display[EncodableValue("id")] = EncodableValue(id);
  display[EncodableValue("name")] =
      EncodableValue(primary ? id + " (Primary)" : id);
  display[EncodableValue("width")] = EncodableValue(width);
  display[EncodableValue("height")] = EncodableValue(height);
  display[EncodableValue("refreshRateHz")] = EncodableValue(refresh_rate_hz);
  display[EncodableValue("x")] = EncodableValue(monitor_rect.left);
  display[EncodableValue("y")] = EncodableValue(monitor_rect.top);
  display[EncodableValue("scaleFactor")] = EncodableValue(1.0);
  display[EncodableValue("isPrimary")] = EncodableValue(primary);

  enumeration->displays.emplace_back(display);
  enumeration->next_index += 1;
  return TRUE;
}

BOOL CALLBACK MonitorSearchProc(HMONITOR monitor,
                                HDC,
                                LPRECT,
                                LPARAM user_data) {
  auto* search = reinterpret_cast<MonitorSearch*>(user_data);

  MONITORINFOEXW info;
  info.cbSize = sizeof(MONITORINFOEXW);
  if (!GetMonitorInfoW(monitor, &info)) {
    return TRUE;
  }

  const std::string device_name = WideToUtf8(info.szDevice);
  const std::string id =
      device_name.empty() ? "DISPLAY" + std::to_string(search->next_index)
                          : device_name;
  search->next_index += 1;

  if (id == search->source_id) {
    search->monitor = monitor;
    return FALSE;
  }

  return TRUE;
}

}  // namespace

flutter::EncodableValue ListDisplays() {
  MonitorEnumeration enumeration;
  if (!EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc,
                           reinterpret_cast<LPARAM>(&enumeration))) {
    EncodableList fallback;
    EncodableMap display;
    display[EncodableValue("id")] = EncodableValue("DISPLAY1");
    display[EncodableValue("name")] = EncodableValue("DISPLAY1");
    display[EncodableValue("width")] = EncodableValue(0);
    display[EncodableValue("height")] = EncodableValue(0);
    display[EncodableValue("x")] = EncodableValue(0);
    display[EncodableValue("y")] = EncodableValue(0);
    display[EncodableValue("scaleFactor")] = EncodableValue(1.0);
    display[EncodableValue("refreshRateHz")] = EncodableValue(0.0);
    display[EncodableValue("isPrimary")] = EncodableValue(true);
    fallback.emplace_back(display);
    return EncodableValue(fallback);
  }
  return EncodableValue(enumeration.displays);
}

std::optional<HMONITOR> FindMonitorById(const std::string& source_id) {
  MonitorSearch search;
  search.source_id = source_id;
  EnumDisplayMonitors(nullptr, nullptr, MonitorSearchProc,
                      reinterpret_cast<LPARAM>(&search));
  if (search.monitor == nullptr) {
    return std::nullopt;
  }
  return search.monitor;
}

}  // namespace pctv
