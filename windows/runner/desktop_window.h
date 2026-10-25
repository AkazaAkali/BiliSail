#ifndef RUNNER_DESKTOP_WINDOW_H_
#define RUNNER_DESKTOP_WINDOW_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <unordered_map>

#include "playback_window_geometry_win32.h"

class CaptionBackButton;

class DesktopWindowChannel {
 public:
  using ViewResolver = std::function<HWND(int64_t)>;
  DesktopWindowChannel(flutter::BinaryMessenger* messenger,
                       ViewResolver resolve_view);
  ~DesktopWindowChannel();
  DesktopWindowChannel(const DesktopWindowChannel&) = delete;
  DesktopWindowChannel& operator=(const DesktopWindowChannel&) = delete;

 private:
  flutter::MethodChannel<flutter::EncodableValue> channel_;
  ViewResolver resolve_view_;
  playback_window::WindowGeometrySession geometry_;
  std::unordered_map<int64_t, std::unique_ptr<CaptionBackButton>> captions_;
};

#endif  // RUNNER_DESKTOP_WINDOW_H_
