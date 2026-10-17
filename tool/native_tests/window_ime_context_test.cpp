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
}  // namespace

int main() {
  const HWND window = CreateWindowExW(0, L"STATIC", L"IME test", WS_POPUP,
                                      0, 0, 100, 100, nullptr, nullptr,
                                      GetModuleHandleW(nullptr), nullptr);
  const HWND other = CreateWindowExW(0, L"STATIC", L"Other IME window", WS_POPUP,
                                     0, 0, 100, 100, nullptr, nullptr,
                                     GetModuleHandleW(nullptr), nullptr);
  Check(window && other, "create hidden native windows");
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
    Check(Context(window) == context, "restore default context after repeated detach");
    Check(policy.SetActive(true), "repeated restore");
    Check(policy.SetActive(false), "detach before destruction");
  }
  Check(Context(window) == context, "policy destruction restores context");
  ImmAssociateContext(window, nullptr);
  {
    WindowImeContext policy(window);
    policy.SetActive(false);
    policy.SetActive(true);
    Check(Context(window) == context, "editor restores a missing default context");
  }
  {
    WindowImeContext policy(window);
    Check(policy.SetActive(false), "detach before input method switch");
    const HIMC replacement = ImmCreateContext();
    Check(replacement != nullptr, "create replacement input context");
    ImmAssociateContext(window, replacement);
    Check(policy.SetActive(true), "enable after input method re-association");
    Check(Context(window) == replacement, "preserve newly associated input context");
    ImmAssociateContext(window, nullptr);
    Check(ImmDestroyContext(replacement) != FALSE, "release replaced context");
    Check(policy.SetActive(true), "reconcile unchanged editing policy");
    Check(Context(window) == context, "recover missing context while already editing");
    Check(policy.SetActive(false), "disable before external re-association");
    ImmAssociateContext(window, context);
    Check(policy.SetActive(false), "reconcile unchanged non-editing policy");
    Check(Context(window) == nullptr, "detach newly associated context outside editor");
  }
  Check(Context(window) == context, "destruction restores the default context");
  {
    WindowImeContext policy(window);
    policy.SetActive(false);
    DestroyWindow(window);
    Check(!policy.SetActive(true), "destroyed view is rejected");
  }
  DestroyWindow(other);
  std::cout << "PASS: IME default restore, context replacement, reconciliation, isolation, lifecycle\n";
  return 0;
}
