#include "text_input.h"

#include <flutter/standard_method_codec.h>

#include "window_ime_context.h"

TextInputChannel::TextInputChannel(flutter::BinaryMessenger* messenger,
                                 HWND view_window)
    : channel_(messenger, "bilisail/text_input",
               &flutter::StandardMethodCodec::GetInstance()) {
  auto context = std::make_shared<WindowImeContext>(view_window);
  channel_.SetMethodCallHandler(
      [context](const flutter::MethodCall<flutter::EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setActive") {
          result->NotImplemented();
          return;
        }
        const auto* active = call.arguments()
                                 ? std::get_if<bool>(call.arguments())
                                 : nullptr;
        if (!active) {
          result->Error("invalid_argument", "Expected a boolean IME policy.");
          return;
        }
        if (!context->SetActive(*active)) {
          result->Error("window_unavailable", "Flutter view is unavailable.");
          return;
        }
        result->Success();
      });
}

TextInputChannel::~TextInputChannel() {
  // MethodChannel alone does not unregister its messenger-owned callback.
  // Release the captured context while the Flutter view still exists.
  channel_.SetMethodCallHandler(nullptr);
}
