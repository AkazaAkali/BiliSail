#ifndef RUNNER_TEXT_INPUT_H_
#define RUNNER_TEXT_INPUT_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <cstdint>
#include <functional>
#include <unordered_map>

class WindowImeContext;

class TextInputChannel {
 public:
  using ViewResolver = std::function<HWND(int64_t)>;

  TextInputChannel(flutter::BinaryMessenger* messenger, HWND view_window,
                   ViewResolver resolve_view = {});
  ~TextInputChannel();
  TextInputChannel(const TextInputChannel&) = delete;
  TextInputChannel& operator=(const TextInputChannel&) = delete;

 private:
  struct ViewContext {
    HWND window;
    std::unique_ptr<WindowImeContext> context;
  };

  WindowImeContext* ContextForView(int64_t view_id);

  flutter::MethodChannel<flutter::EncodableValue> channel_;
  HWND implicit_window_;
  std::unique_ptr<WindowImeContext> implicit_context_;
  ViewResolver resolve_view_;
  std::unordered_map<int64_t, ViewContext> view_contexts_;
};

#endif  // RUNNER_TEXT_INPUT_H_
