#ifndef RUNNER_NATIVE_DISPLAY_DISPLAY_ENUMERATOR_H_
#define RUNNER_NATIVE_DISPLAY_DISPLAY_ENUMERATOR_H_

#include <flutter/encodable_value.h>
#include <windows.h>

#include <optional>
#include <string>

namespace pctv {

flutter::EncodableValue ListDisplays();
std::optional<HMONITOR> FindMonitorById(const std::string& source_id);
std::string WideToUtf8(const std::wstring& value);

}  // namespace pctv

#endif  // RUNNER_NATIVE_DISPLAY_DISPLAY_ENUMERATOR_H_
