#ifndef RUNNER_PLAYBACK_WINDOW_FRAME_H_
#define RUNNER_PLAYBACK_WINDOW_FRAME_H_

#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>

namespace playback_window {

// Keep the native resize frame and window styles. Flutter supplies the taller
// caption inside the client area; fullscreen still follows the SDK's styles.
class PlaybackWindowFrame {
 public:
  explicit PlaybackWindowFrame(HWND window) : window_(window) {
    attached_ = SetWindowSubclass(window_, WindowProc, SubclassId(), 0) != FALSE;
    if (attached_) Refresh();
  }
  ~PlaybackWindowFrame() {
    if (!attached_ || !IsWindow(window_)) return;
    // The callback carries no object pointer, so even a failed removal is safe.
    if (RemoveWindowSubclass(window_, WindowProc, SubclassId())) Refresh();
  }
  PlaybackWindowFrame(const PlaybackWindowFrame&) = delete;
  PlaybackWindowFrame& operator=(const PlaybackWindowFrame&) = delete;

  bool ready() const { return attached_; }

  void SetTheme(bool dark, COLORREF caption_color) const {
    const BOOL enable_dark_mode = dark ? TRUE : FALSE;
    // SDK-managed secondary HWNDs do not pass through Win32Window::UpdateTheme.
    // These numeric attributes also compile with the Windows 10 SDK. Caption
    // color is optional on older Windows; immersive dark mode remains usable.
    constexpr DWORD kImmersiveDarkMode = 20;
    constexpr DWORD kCaptionColor = 35;
    DwmSetWindowAttribute(window_, kImmersiveDarkMode, &enable_dark_mode,
                          sizeof(enable_dark_mode));
    DwmSetWindowAttribute(window_, kCaptionColor, &caption_color,
                          sizeof(caption_color));
    RedrawWindow(window_, nullptr, nullptr, RDW_INVALIDATE | RDW_FRAME);
  }

 private:
  static UINT_PTR SubclassId() {
    return reinterpret_cast<UINT_PTR>(&WindowProc);
  }

  void Refresh() const {
    SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER |
                     SWP_FRAMECHANGED);
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR subclass_id,
                                     DWORD_PTR) {
    if (message == WM_NCCALCSIZE &&
        (GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) == WS_CAPTION) {
      auto* const rect = wparam
          ? &reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam)->rgrc[0]
          : reinterpret_cast<RECT*>(lparam);
      const LONG top = rect->top;
      const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
      const UINT dpi = GetDpiForWindow(window);
      rect->top = top + GetSystemMetricsForDpi(SM_CYFRAME, dpi) +
                  GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
      return result;
    }
    if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(window, WindowProc, subclass_id);
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  HWND window_;  // Borrowed from the Flutter window controller.
  bool attached_ = false;
};

}  // namespace playback_window

#endif  // RUNNER_PLAYBACK_WINDOW_FRAME_H_
