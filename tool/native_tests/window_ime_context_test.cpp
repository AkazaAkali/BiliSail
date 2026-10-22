#include "window_ime_context.h"

#include <cstdlib>
#include <iostream>

namespace {
void Check(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "FAIL: " << description << '\n';
    std::exit(1);
  }
}

HIMC Context(HWND window) {
  const HIMC context = ImmGetContext(window);
  if (context) ImmReleaseContext(window, context);
  return context;
}
bool blur_seen = false;
HIMC context_at_blur = nullptr;

LRESULT CALLBACK TestWindowProc(HWND window, UINT message, WPARAM wparam,
                                LPARAM lparam) {
  if (message == WM_KILLFOCUS) {
    blur_seen = true;
    context_at_blur = Context(window);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
}  // namespace

int main() {
  const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  WNDCLASSW definition{};
  definition.lpfnWndProc = TestWindowProc;
  definition.hInstance = GetModuleHandleW(nullptr);
  definition.lpszClassName = L"BiliSailImeContextTest";
  Check(RegisterClassW(&definition) != 0, "register native focus observer");
  const HWND window = CreateWindowExW(
      0, definition.lpszClassName, L"IME test", WS_POPUP, 0, 0, 100, 100,
      nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  const HWND other = CreateWindowExW(0, L"STATIC", L"Other IME window",
                                     WS_POPUP, 0, 0, 100, 100, nullptr, nullptr,
                                     GetModuleHandleW(nullptr), nullptr);
  Check(window && other, "create hidden native windows");
  SetFocus(window);
  Check(GetFocus() == window, "focus test view");
  const HIMC context = Context(window);
  Check(context != nullptr, "window has a default input context");
  const HIMC other_context = Context(other);
  const HKL layout = GetKeyboardLayout(0);
  const BOOL open = ImmGetOpenStatus(context);
  {
    WindowImeContext policy(window);
    Check(policy.SetActive(false), "detach IME outside editor");
    Check(Context(window) == nullptr, "view has no IME association");
    Check(Context(other) == other_context, "other window keeps IME");
    Check(GetKeyboardLayout(0) == layout, "input language is preserved");
    Check(ImmGetOpenStatus(context) == open, "conversion mode is preserved");
    Check(policy.SetActive(false), "repeated detach");
    Check(policy.SetActive(true), "restore IME inside editor");
    const HIMC editing_context = Context(window);
    Check(editing_context != nullptr && editing_context != context,
          "editing owns a context distinct from the stale thread default");
    Check(ImmGetOpenStatus(editing_context) == open,
          "new editing context preserves the user's input mode");
    Check(policy.SetActive(true), "repeated restore");
    Check(Context(window) == editing_context,
          "unchanged policy preserves an ongoing composition context");
    blur_seen = false;
    SetFocus(other);
    Check(blur_seen && context_at_blur == nullptr,
          "IME is detached before the original native focus handler");
    Check(Context(window) == nullptr,
          "native blur detaches before any Dart frame can run");
    Check(Context(other) == other_context,
          "native blur preserves other window");
    Check(policy.SetActive(true), "late editing request after native blur");
    Check(Context(window) == nullptr,
          "late request cannot enable a background view");
    SetFocus(window);
    Check(Context(window) != nullptr && Context(window) != context,
          "native focus returns with a fresh editing context");
    Check(policy.SetActive(false), "clear editing client");
    SetFocus(other);
    SetFocus(window);
    Check(Context(window) == nullptr,
          "focus gain without an editor keeps IME detached");
    Check(policy.SetActive(false), "detach before destruction");
  }
  Check(Context(window) == context, "policy destruction restores context");
  ImmAssociateContext(window, nullptr);
  {
    WindowImeContext policy(window);
    policy.SetActive(false);
    policy.SetActive(true);
    Check(Context(window) != nullptr && Context(window) != context,
          "editor creates an owned context when the default association was "
          "missing");
  }
  {
    WindowImeContext policy(window);
    Check(policy.SetActive(false), "detach before input method switch");
    const HIMC replacement = ImmCreateContext();
    Check(replacement != nullptr, "create replacement input context");
    ImmAssociateContext(window, replacement);
    Check(policy.SetActive(true), "enable after input method re-association");
    Check(Context(window) != nullptr && Context(window) != replacement,
          "a new editing interval owns its context rather than a borrowed one");
    ImmAssociateContext(window, replacement);
    Check(policy.SetActive(true),
          "reconcile a replacement during active editing");
    Check(Context(window) == replacement,
          "preserve newly associated input context");
    ImmAssociateContext(window, nullptr);
    Check(ImmDestroyContext(replacement) != FALSE, "release replaced context");
    Check(policy.SetActive(true), "reconcile unchanged editing policy");
    Check(Context(window) != nullptr && Context(window) != context,
          "recover a missing context without reusing the thread default");
    Check(policy.SetActive(false), "disable before external re-association");
    ImmAssociateContext(window, context);
    Check(policy.SetActive(false), "reconcile unchanged non-editing policy");
    Check(Context(window) == nullptr,
          "detach newly associated context outside editor");
  }
  Check(Context(window) == context, "destruction restores the default context");
  {
    WindowImeContext policy(window);
    policy.SetActive(false);
    DestroyWindow(window);
    Check(!policy.SetActive(true), "destroyed view is rejected");
  }
  DestroyWindow(other);
  if (SUCCEEDED(com)) CoUninitialize();
  std::cout << "PASS: owned IME context, native focus boundary, late requests, "
               "mode preservation, isolation, disposal\n";
  return 0;
}
