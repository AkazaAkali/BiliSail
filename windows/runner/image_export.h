#ifndef RUNNER_IMAGE_EXPORT_H_
#define RUNNER_IMAGE_EXPORT_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

class ImageExportChannel {
 public:
  ImageExportChannel(flutter::BinaryMessenger* messenger, HWND owner);
  ~ImageExportChannel();
  ImageExportChannel(const ImageExportChannel&) = delete;
  ImageExportChannel& operator=(const ImageExportChannel&) = delete;

 private:
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};

#endif  // RUNNER_IMAGE_EXPORT_H_
