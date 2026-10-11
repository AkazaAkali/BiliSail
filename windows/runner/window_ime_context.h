#ifndef RUNNER_WINDOW_IME_CONTEXT_H_
#define RUNNER_WINDOW_IME_CONTEXT_H_

#include <windows.h>
#include <imm.h>

// The window owns its HIMC. Borrow and restore the exact association without
// changing the selected input language, conversion mode, or other windows.
class WindowImeContext {
 public:
  explicit WindowImeContext(HWND window) : window_(window) {}
  ~WindowImeContext() { SetActive(true); }
  WindowImeContext(const WindowImeContext&) = delete;
  WindowImeContext& operator=(const WindowImeContext&) = delete;

  bool SetActive(bool active) noexcept {
    if (!IsWindow(window_)) return false;
    if (active && detached_) {
      ImmAssociateContext(window_, saved_context_);
      detached_ = false;
    } else if (!active && !detached_) {
      saved_context_ = ImmAssociateContext(window_, nullptr);
      detached_ = true;
    }
    return true;
  }

 private:
  const HWND window_;
  HIMC saved_context_ = nullptr;
  bool detached_ = false;
};

#endif  // RUNNER_WINDOW_IME_CONTEXT_H_
