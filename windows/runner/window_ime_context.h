#ifndef RUNNER_WINDOW_IME_CONTEXT_H_
#define RUNNER_WINDOW_IME_CONTEXT_H_

#include <windows.h>
#include <imm.h>

// Windows/TSF owns the input context and can replace it during an IME switch.
// Never cache a borrowed HIMC across a detached interval. Restore the current
// default association without changing the input language or conversion mode.
class WindowImeContext {
 public:
  explicit WindowImeContext(HWND window) : window_(window) {}
  ~WindowImeContext() { SetActive(true); }
  WindowImeContext(const WindowImeContext&) = delete;
  WindowImeContext& operator=(const WindowImeContext&) = delete;

  bool SetActive(bool active) noexcept {
    if (!IsWindow(window_)) return false;
    const HIMC context = ImmGetContext(window_);
    if (context) ImmReleaseContext(window_, context);
    if (active) {
      // A newly selected input method may already have supplied a context.
      // Keep it; otherwise ask Windows for its current default, even when the
      // previous editing policy was also active or started without a HIMC.
      return context != nullptr ||
             ImmAssociateContextEx(window_, nullptr, IACE_DEFAULT) != FALSE;
    }
    return ImmAssociateContextEx(window_, nullptr, 0) != FALSE;
  }

 private:
  const HWND window_;
};

#endif  // RUNNER_WINDOW_IME_CONTEXT_H_
