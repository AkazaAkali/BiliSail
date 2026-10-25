#ifndef RUNNER_WINDOW_SIZE_CONSTRAINTS_H_
#define RUNNER_WINDOW_SIZE_CONSTRAINTS_H_

#include <algorithm>
#include <windows.h>

namespace window_layout {

inline void ConstrainMinimumTrackSize(MINMAXINFO& sizes,
                                      const RECT& work_area) noexcept {
  const LONG width = work_area.right - work_area.left;
  const LONG height = work_area.bottom - work_area.top;
  if (width > 0 && height > 0) {
    sizes.ptMinTrackSize.x = (std::min)(sizes.ptMinTrackSize.x, width);
    sizes.ptMinTrackSize.y = (std::min)(sizes.ptMinTrackSize.y, height);
  }
}

inline void ConstrainMinimumTrackSizeToMonitor(HWND window,
                                               MINMAXINFO& sizes) noexcept {
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                      &monitor)) {
    ConstrainMinimumTrackSize(sizes, monitor.rcWork);
  }
}

}  // namespace window_layout

#endif  // RUNNER_WINDOW_SIZE_CONSTRAINTS_H_
