#include "text_input.h"

#include <flutter/standard_method_codec.h>

#include <utility>

#include "window_ime_context.h"

TextInputChannel::TextInputChannel(flutter::BinaryMessenger* messenger,
                                 HWND view_window, ViewResolver resolve_view)
    : channel_(messenger, "bilisail/text_input",
               &flutter::StandardMethodCodec::GetInstance()),
      implicit_window_(view_window),
      implicit_context_(std::make_unique<WindowImeContext>(view_window)),
      resolve_view_(std::move(resolve_view)) {
  channel_.SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setActive") {
          result->NotImplemented();
          return;
        }
        const auto* active = call.arguments()
                                 ? std::get_if<bool>(call.arguments())
                                 : nullptr;
        WindowImeContext* context = implicit_context_.get();
        if (const auto* arguments = call.arguments()
                                        ? std::get_if<flutter::EncodableMap>(
                                              call.arguments())
                                        : nullptr) {
          const auto active_value = arguments->find(
              flutter::EncodableValue("active"));
          const auto view_value = arguments->find(
              flutter::EncodableValue("viewId"));
          if (active_value == arguments->end() ||
              view_value == arguments->end()) {
            result->Error("invalid_argument", "Expected an IME policy and view ID.");
            return;
          }
          active = std::get_if<bool>(&active_value->second);
          const auto* wide_id = std::get_if<int64_t>(&view_value->second);
          const auto* small_id = std::get_if<int32_t>(&view_value->second);
          if (!wide_id && !small_id) {
            result->Error("invalid_argument", "Expected an integer view ID.");
            return;
          }
          context = ContextForView(wide_id ? *wide_id : *small_id);
        }
        if (!active) {
          result->Error("invalid_argument", "Expected a boolean IME policy.");
          return;
        }
        if (!context || !context->SetActive(*active)) {
          result->Error("window_unavailable", "Flutter view is unavailable.");
          return;
        }
        result->Success();
      });
}

WindowImeContext* TextInputChannel::ContextForView(int64_t view_id) {
  if (!resolve_view_) return nullptr;
  // A view can be destroyed independently of the engine. Drop its owned HIMC
  // before accepting another window, without retaining borrowed native views.
  for (auto it = view_contexts_.begin(); it != view_contexts_.end();) {
    if (resolve_view_(it->first) != it->second.window ||
        !IsWindow(it->second.window)) {
      it = view_contexts_.erase(it);
    } else {
      ++it;
    }
  }
  const HWND window = resolve_view_(view_id);
  if (!window || !IsWindow(window)) return nullptr;
  if (window == implicit_window_) return implicit_context_.get();
  const auto existing = view_contexts_.find(view_id);
  if (existing != view_contexts_.end()) return existing->second.context.get();
  auto context = std::make_unique<WindowImeContext>(window);
  auto* const result = context.get();
  view_contexts_.emplace(view_id, ViewContext{window, std::move(context)});
  return result;
}

TextInputChannel::~TextInputChannel() {
  // MethodChannel alone does not unregister its messenger-owned callback.
  // Release the captured context while the Flutter view still exists.
  channel_.SetMethodCallHandler(nullptr);
}
