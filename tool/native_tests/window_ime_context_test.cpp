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
  const HIMC context = ImmCreateContext();
  Check(context != nullptr, "create input context");
  const HIMC original = ImmAssociateContext(window, context);
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
    Check(Context(window) == context, "restore exact context after repeated detach");
    Check(policy.SetActive(true), "repeated restore");
    Check(policy.SetActive(false), "detach before destruction");
  }
  Check(Context(window) == context, "policy destruction restores context");
  ImmAssociateContext(window, nullptr);
  {
    WindowImeContext policy(window);
    policy.SetActive(false);
    policy.SetActive(true);
    Check(Context(window) == nullptr, "no original context stays absent");
  }
  ImmAssociateContext(window, original);
  ImmDestroyContext(context);
  {
    WindowImeContext policy(window);
    policy.SetActive(false);
    DestroyWindow(window);
    Check(!policy.SetActive(true), "destroyed view is rejected");
  }
  DestroyWindow(other);
  std::cout << "PASS: IME detach, exact restore, idempotence, isolation, lifecycle\n";
  return 0;
}
