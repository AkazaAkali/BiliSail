#ifndef RUNNER_WINDOW_IME_CONTEXT_H_
#define RUNNER_WINDOW_IME_CONTEXT_H_

#include <windows.h>

#include <imm.h>

// Own the editing interval's context: a non-null default HIMC does not prove
// that its IMM32/TSF composition session survived a native focus change.
class WindowImeContext {
 public:
  explicit WindowImeContext(HWND window);
  ~WindowImeContext();
  WindowImeContext(const WindowImeContext&) = delete;
  WindowImeContext& operator=(const WindowImeContext&) = delete;

  WindowImeContext(WindowImeContext&&) = delete;
  WindowImeContext& operator=(WindowImeContext&&) = delete;

  bool SetActive(bool active) noexcept;

 private:
  struct InputState {
    bool valid = false;
    bool open = false;
    bool conversion_valid = false;
    DWORD conversion = 0;
    DWORD sentence = 0;
    HKL layout = nullptr;
    bool profile_valid = false;
    CLSID profile_class{};
    GUID profile{};
  };

  static InputState ReadState(HWND window) noexcept;
  static void ReadProfile(InputState& state) noexcept;
  static void ReadThreadState(InputState& state) noexcept;
  static bool SameProfile(const InputState& left,
                          const InputState& right) noexcept;
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR subclass_id,
                                     DWORD_PTR reference);
  bool Enable() noexcept;
  bool Detach() noexcept;
  void DestroyOwnedContext() noexcept;

  HWND window_;
  HIMC owned_context_ = nullptr;
  bool requested_ = false;
  bool interval_active_ = false;
  bool subclassed_ = false;
  InputState saved_state_;
};

#endif  // RUNNER_WINDOW_IME_CONTEXT_H_
