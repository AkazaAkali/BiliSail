#ifndef RUNNER_PLAYBACK_WINDOW_GEOMETRY_WIN32_H_
#define RUNNER_PLAYBACK_WINDOW_GEOMETRY_WIN32_H_

#include <windows.h>
#include <commctrl.h>

#include <cmath>
#include <memory>
#include <optional>

#include "playback_window_geometry.h"

namespace playback_window {

inline Bounds RectBounds(const RECT& rect) {
  return {static_cast<double>(rect.left), static_cast<double>(rect.top),
          static_cast<double>(rect.right) - rect.left,
          static_cast<double>(rect.bottom) - rect.top};
}

inline bool CaptureNormalBounds(
    HWND window, int64_t view, int64_t owner, GeometrySession& session,
    std::optional<bool> last_maximized = std::nullopt) {
  // Fullscreen removes the native caption and may replace WINDOWPLACEMENT.
  // Dart captures immediately before entering fullscreen; never save its frame.
  if ((GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) != WS_CAPTION) {
    return true;
  }
  RECT rect{};
  if (!IsIconic(window) && !IsZoomed(window)) {
    if (!GetWindowRect(window, &rect)) return false;
    session.Capture(view, owner, RectBounds(rect));
    return true;
  }
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window, &placement)) return false;
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                      &monitor)) return false;
  const bool tool_window =
      (GetWindowLongPtr(window, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0;
  // WINDOWPLACEMENT uses workspace coordinates for ordinary top-level windows.
  // Convert once, including negative monitor origins and left/top taskbars.
  const bool maximized = IsIconic(window)
      ? last_maximized.value_or(session.maximized())
      : IsZoomed(window) != FALSE;
  session.Capture(view, owner, PlacementToScreen(
      RectBounds(placement.rcNormalPosition), RectBounds(monitor.rcMonitor),
      RectBounds(monitor.rcWork), tool_window), maximized);
  return true;
}

inline bool RestoreNormalBounds(HWND window, const GeometrySession& session) {
  if (!session.normal()) return true;  // First window keeps the SDK default.
  const auto saved = *session.normal();
  const RECT previous{static_cast<LONG>(std::lround(saved.left)),
                      static_cast<LONG>(std::lround(saved.top)),
                      static_cast<LONG>(std::lround(saved.left + saved.width)),
                      static_cast<LONG>(std::lround(saved.top + saved.height))};
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfo(MonitorFromRect(&previous, MONITOR_DEFAULTTONEAREST),
                      &monitor)) return true;
  const auto fitted = FitToWorkArea(saved, RectBounds(monitor.rcWork));
  if (!fitted) return true;
  return SetWindowPos(window, nullptr,
                      static_cast<int>(std::lround(fitted->left)),
                      static_cast<int>(std::lround(fitted->top)),
                      static_cast<int>(std::lround(fitted->width)),
                      static_cast<int>(std::lround(fitted->height)),
                      SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER) != FALSE;
}

// Flutter 3.47.6 HostWindow captures SW_SHOWNORMAL at creation and executes it
// after the first rendered frame. Maximizing during prepare would show a blank
// window early, then that SDK callback would unmaximize it. Consume only the
// first native show, after its normal placement is applied, in the same message
// stack. Later user Restore commands must pass through without intervention.
class InitialShowMaximizer {
 public:
  explicit InitialShowMaximizer(HWND window) : window_(window) {}
  ~InitialShowMaximizer() { Cancel(); }
  InitialShowMaximizer(const InitialShowMaximizer&) = delete;
  InitialShowMaximizer& operator=(const InitialShowMaximizer&) = delete;

  bool Prepare(bool maximized) {
    if (!maximized) return true;
    if (IsWindowVisible(window_)) {
      ShowWindow(window_, SW_MAXIMIZE);
      return true;
    }
    return SetWindowSubclass(window_, WindowProc, SubclassId(), 1) != FALSE;
  }

  bool pending() const {
    DWORD_PTR pending = 0;
    return IsWindow(window_) &&
           GetWindowSubclass(window_, WindowProc, SubclassId(), &pending) &&
           pending != 0;
  }

 private:
  static UINT_PTR SubclassId() {
    return reinterpret_cast<UINT_PTR>(&WindowProc);
  }

  void Cancel() {
    if (!IsWindow(window_)) return;
    if (!RemoveWindowSubclass(window_, WindowProc, SubclassId())) {
      // No callback references this object. If native removal fails, leave an
      // inert callback rather than carrying an old owner's restore forward.
      if (pending()) {
        SetWindowSubclass(window_, WindowProc, SubclassId(), 0);
      }
    }
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR subclass_id,
                                     DWORD_PTR pending) {
    if (message == WM_NCDESTROY) {
      RemoveWindowSubclass(window, WindowProc, subclass_id);
    } else if (message == WM_WINDOWPOSCHANGED && pending != 0 &&
               (reinterpret_cast<const WINDOWPOS*>(lparam)->flags &
                SWP_SHOWWINDOW) != 0) {
      // Disarm before forwarding: DefSubclassProc sends WM_SIZE, which calls
      // Dart listeners synchronously, and maximization reenters this procedure.
      SetWindowSubclass(window, WindowProc, subclass_id, 0);
      RemoveWindowSubclass(window, WindowProc, subclass_id);
      const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
      if (IsWindow(window) && IsWindowVisible(window) && !IsIconic(window) &&
          (GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) == WS_CAPTION) {
        ShowWindow(window, SW_MAXIMIZE);
      }
      return result;
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  HWND window_;
};

// Own both the saved geometry and the first-show hook under the same view lease.
// Channel replies and asynchronous close/retire operations can cross new opens.
class WindowGeometrySession {
 public:
  bool Restore(HWND window, int64_t view, int64_t owner) {
    const bool maximized = geometry_.maximized();
    initial_show_.reset();
    if (!RestoreNormalBounds(window, geometry_)) return false;
    auto initial_show = std::make_unique<InitialShowMaximizer>(window);
    if (!initial_show->Prepare(maximized)) return false;
    geometry_.Begin(view, owner);
    initial_show_ = std::move(initial_show);
    return Capture(window, view, owner);
  }

  bool Owns(int64_t view, int64_t owner) const {
    return geometry_.Owns(view, owner);
  }

  bool Capture(HWND window, int64_t view, int64_t owner,
               std::optional<bool> last_maximized = std::nullopt) {
    if (!Owns(view, owner)) return true;
    // A close before the first frame must not sample its temporary normal size
    // and erase the maximized state remembered by the previous playback window.
    if (initial_show_ && initial_show_->pending()) return true;
    return CaptureNormalBounds(window, view, owner, geometry_, last_maximized);
  }

  void Retire(int64_t view, int64_t owner) {
    if (!Owns(view, owner)) return;
    initial_show_.reset();
    geometry_.Retire(view, owner);
  }

  const GeometrySession& saved() const { return geometry_; }

 private:
  GeometrySession geometry_;
  std::unique_ptr<InitialShowMaximizer> initial_show_;
};

inline void ActivateWindow(HWND window, HWND view) {
  // Preparation may receive a newer media activation before the first frame.
  // Keep that window hidden until the SDK's first-frame callback shows it.
  if (!IsWindowVisible(window)) return;
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window);
  SetFocus(view);
}

}  // namespace playback_window

#endif  // RUNNER_PLAYBACK_WINDOW_GEOMETRY_WIN32_H_
