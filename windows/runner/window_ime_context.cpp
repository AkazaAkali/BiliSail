#include "window_ime_context.h"

#include <commctrl.h>
#include <msctf.h>
#include <wrl/client.h>

namespace {
HIMC Context(HWND window) noexcept {
  const HIMC context = ImmGetContext(window);
  if (context) ImmReleaseContext(window, context);
  return context;
}

class NewContext {
 public:
  NewContext() : value_(ImmCreateContext()) {}
  ~NewContext() {
    if (value_) ImmDestroyContext(value_);
  }
  NewContext(const NewContext&) = delete;
  NewContext& operator=(const NewContext&) = delete;
  NewContext(NewContext&&) = delete;
  NewContext& operator=(NewContext&&) = delete;
  HIMC get() const noexcept { return value_; }
  HIMC release() noexcept {
    const HIMC value = value_;
    value_ = nullptr;
    return value;
  }

 private:
  HIMC value_;
};
}  // namespace

WindowImeContext::WindowImeContext(HWND window) : window_(window) {
  if (GetWindowThreadProcessId(window_, nullptr) == GetCurrentThreadId()) {
    subclassed_ =
        SetWindowSubclass(window_, WindowProc, reinterpret_cast<UINT_PTR>(this),
                          reinterpret_cast<DWORD_PTR>(this)) != FALSE;
  }
}

WindowImeContext::~WindowImeContext() {
  if (subclassed_ && IsWindow(window_)) {
    RemoveWindowSubclass(window_, WindowProc, reinterpret_cast<UINT_PTR>(this));
    const HIMC current = Context(window_);
    // Borrowed handles are never saved across an input-method switch.
    if (!current || current == owned_context_) {
      ImmAssociateContextEx(window_, nullptr, IACE_DEFAULT);
    }
  }
  DestroyOwnedContext();
}

void WindowImeContext::ReadProfile(InputState& state) noexcept {
  state.layout = GetKeyboardLayout(0);
  Microsoft::WRL::ComPtr<ITfInputProcessorProfileMgr> profiles;
  if (FAILED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&profiles)))) {
    return;
  }
  TF_INPUTPROCESSORPROFILE profile{};
  if (profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &profile) == S_OK) {
    state.profile_valid = true;
    state.profile_class = profile.clsid;
    state.profile = profile.guidProfile;
  }
}

WindowImeContext::InputState WindowImeContext::ReadState(HWND window) noexcept {
  InputState state;
  ReadProfile(state);
  const HIMC context = ImmGetContext(window);
  if (context) {
    state.valid = true;
    state.open = ImmGetOpenStatus(context) != FALSE;
    state.conversion_valid = ImmGetConversionStatus(context, &state.conversion,
                                                    &state.sentence) != FALSE;
    ImmReleaseContext(window, context);
  }
  return state;
}

bool WindowImeContext::SameProfile(const InputState& left,
                                   const InputState& right) noexcept {
  // HKL alone cannot distinguish two TSF Chinese IMEs. An unknown profile must
  // use the newly selected method's state, not a cached conversion mode.
  return left.profile_valid && right.profile_valid &&
         left.layout == right.layout &&
         IsEqualGUID(left.profile_class, right.profile_class) &&
         IsEqualGUID(left.profile, right.profile);
}

bool WindowImeContext::SetActive(bool active) noexcept {
  if (!subclassed_ || !IsWindow(window_) ||
      GetWindowThreadProcessId(window_, nullptr) != GetCurrentThreadId()) {
    return false;
  }
  requested_ = active;
  // Queued Dart notifications must not reattach IME after native focus loss.
  return active && GetFocus() == window_ ? Enable() : Detach();
}

bool WindowImeContext::Enable() noexcept {
  if (interval_active_ && Context(window_)) {
    // Do not cancel composition or overwrite a newly supplied context when the
    // same editing policy is reapplied during an already active interval.
    return true;
  }
  auto state = ReadState(window_);
  if (!state.valid) {
    const auto profile = state;
    if (!ImmAssociateContextEx(window_, nullptr, IACE_DEFAULT)) return false;
    state = ReadState(window_);
    if (saved_state_.valid && SameProfile(saved_state_, profile)) {
      state = saved_state_;
    }
  }
  NewContext fresh;
  if (!fresh.get()) return false;
  if (!ImmAssociateContextEx(window_, fresh.get(), 0)) return false;
  // Only this interval's allocation is owned; never destroy a borrowed context.
  DestroyOwnedContext();
  owned_context_ = fresh.release();
  if (state.valid) {
    if (state.conversion_valid) {
      ImmSetConversionStatus(owned_context_, state.conversion, state.sentence);
    }
    ImmSetOpenStatus(owned_context_, state.open ? TRUE : FALSE);
  }
  interval_active_ = true;
  return true;
}

bool WindowImeContext::Detach() noexcept {
  const auto state = ReadState(window_);
  if (state.valid) saved_state_ = state;
  if (!ImmAssociateContextEx(window_, nullptr, 0)) return false;
  interval_active_ = false;
  DestroyOwnedContext();
  return true;
}

void WindowImeContext::DestroyOwnedContext() noexcept {
  if (owned_context_) {
    ImmDestroyContext(owned_context_);
    owned_context_ = nullptr;
  }
}

LRESULT CALLBACK WindowImeContext::WindowProc(HWND window, UINT message,
                                              WPARAM wparam, LPARAM lparam,
                                              UINT_PTR subclass_id,
                                              DWORD_PTR reference) {
  auto* self = reinterpret_cast<WindowImeContext*>(reference);
  if (message == WM_KILLFOCUS) {
    // Run before Flutter/DefWindowProc processes the TSF native focus boundary,
    // not in a later Dart frame after the old composition session was retained.
    self->Detach();
  } else if (message == WM_SETFOCUS) {
    const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
    if (self->requested_ && GetFocus() == window) self->Enable();
    return result;
  } else if (message == WM_NCDESTROY) {
    self->Detach();
    RemoveWindowSubclass(window, WindowProc, subclass_id);
    self->subclassed_ = false;
    self->window_ = nullptr;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}
