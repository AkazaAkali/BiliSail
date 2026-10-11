#ifndef RUNNER_TEXT_INPUT_H_
#define RUNNER_TEXT_INPUT_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

class TextInputChannel {
 public:
  TextInputChannel(flutter::BinaryMessenger* messenger, HWND view_window);
  ~TextInputChannel();
  TextInputChannel(const TextInputChannel&) = delete;
  TextInputChannel& operator=(const TextInputChannel&) = delete;

 private:
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};

#endif  // RUNNER_TEXT_INPUT_H_
