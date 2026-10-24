#include "window_ime_context.h"

#include <msctf.h>
#include <wrl/client.h>

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

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
HIMC watched_default_context = nullptr;
bool default_context_activated = false;

LRESULT CALLBACK TestWindowProc(HWND window, UINT message, WPARAM wparam,
                                LPARAM lparam) {
  if (message == WM_KILLFOCUS) {
    blur_seen = true;
    context_at_blur = Context(window);
  }
  if (message == WM_IME_SETCONTEXT && wparam && watched_default_context &&
      Context(window) == watched_default_context) {
    default_context_activated = true;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void PumpMessages() {
  const ULONGLONG until = GetTickCount64() + 100;
  do {
    MSG message{};
    while (GetTickCount64() < until &&
           PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 10, QS_ALLINPUT);
  } while (GetTickCount64() < until);
}

void CheckRealProfiles(HWND window, HWND other) {
  Microsoft::WRL::ComPtr<ITfInputProcessorProfileMgr> profiles;
  Check(SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&profiles))),
        "obtain profile manager for opt-in real IME checks");
  Microsoft::WRL::ComPtr<ITfInputProcessorProfiles> descriptions;
  Check(SUCCEEDED(profiles.As(&descriptions)), "obtain profile descriptions");
  Microsoft::WRL::ComPtr<IEnumTfInputProcessorProfiles> entries;
  Check(SUCCEEDED(profiles->EnumProfiles(0x0804, &entries)),
        "enumerate Chinese IME profiles");
  std::vector<TF_INPUTPROCESSORPROFILE> chosen;
  TF_INPUTPROCESSORPROFILE entry{};
  ULONG fetched = 0;
  while (entries->Next(1, &entry, &fetched) == S_OK) {
    if (entry.dwProfileType != TF_PROFILETYPE_INPUTPROCESSOR ||
        !(entry.dwFlags & TF_IPP_FLAG_ENABLED)) {
      continue;
    }
    BSTR description = nullptr;
    if (FAILED(descriptions->GetLanguageProfileDescription(
            entry.clsid, entry.langid, entry.guidProfile, &description))) {
      continue;
    }
    const std::wstring name = description ? description : L"";
    SysFreeString(description);
    // Explicitly opt into these locally installed services; no registry or
    // default-input settings are changed, and no account/network is involved.
    if (name == L"\u5fae\u4fe1\u8f93\u5165\u6cd5" ||
        name == L"\u5fae\u8f6f\u62fc\u97f3") {
      chosen.push_back(entry);
    }
  }
  Check(chosen.size() == 2,
        "real-profile checks require enabled WeChat and Microsoft Pinyin");
  TF_INPUTPROCESSORPROFILE original{};
  Check(profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &original) == S_OK,
        "save this test process's active profile");
  const auto activate = [&](const TF_INPUTPROCESSORPROFILE& profile) {
    Check(profiles->ActivateProfile(profile.dwProfileType, profile.langid,
                                    profile.clsid, profile.guidProfile,
                                    profile.hkl, TF_IPPMF_FORPROCESS) == S_OK,
          "activate profile in this test process only");
  };
  const auto check_profile = [&](const TF_INPUTPROCESSORPROFILE& expected) {
    TF_INPUTPROCESSORPROFILE actual{};
    Check(
        profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &actual) == S_OK &&
            IsEqualGUID(expected.clsid, actual.clsid) &&
            IsEqualGUID(expected.guidProfile, actual.guidProfile),
        "user-selected real IME remains active");
  };
  SetFocus(window);
  const HIMC default_context = Context(window);
  {
    WindowImeContext policy(window);
    for (int round = 0; round < 3; ++round) {
      for (const auto& profile : chosen) {
        Check(policy.SetActive(false), "leave editor before profile switch");
        activate(profile);
        PumpMessages();
        check_profile(profile);
        watched_default_context = default_context;
        default_context_activated = false;
        Check(policy.SetActive(true), "enter editor after real profile switch");
        Check(!default_context_activated,
              "real profile restore has no thread-default activation");
        watched_default_context = nullptr;
        PumpMessages();
        check_profile(profile);
        const HIMC editing_context = Context(window);
        Check(editing_context != nullptr,
              "real profile has an editing context");
        Check(policy.SetActive(true), "reapply policy after real switch");
        Check(Context(window) == editing_context,
              "reapplying policy preserves the real IME composition context");
        SetFocus(other);
        PumpMessages();
        SetFocus(window);
        PumpMessages();
        check_profile(profile);
      }
    }
  }
  activate(original);
  std::cout << "PASS: real WeChat/Microsoft profile switching, editor restore, "
               "native refocus (process scope only)\n";
}
}  // namespace

int main(int argc, char** argv) {
  const bool real_profiles =
      argc == 2 && std::string(argv[1]) == "--real-profiles";
  Check(argc == 1 || real_profiles,
        "usage: window_ime_context_test [--real-profiles]");
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
    watched_default_context = context;
    default_context_activated = false;
    Check(policy.SetActive(true), "restore IME inside editor");
    Check(!default_context_activated,
          "editor restore must not activate the detached thread default");
    watched_default_context = nullptr;
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
  if (real_profiles) {
    CheckRealProfiles(window, other);
  }
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
