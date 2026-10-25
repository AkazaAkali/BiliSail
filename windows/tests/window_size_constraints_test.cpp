#include "../runner/window_size_constraints.h"

#include <cassert>
#include <charconv>
#include <cmath>
#include <cstring>
#include <iostream>

namespace {

struct WindowQuery {
  DWORD process_id;
  HWND window = nullptr;
};

BOOL CALLBACK FindRunnerWindow(HWND window, LPARAM parameter) {
  auto& query = *reinterpret_cast<WindowQuery*>(parameter);
  DWORD owner{};
  GetWindowThreadProcessId(window, &owner);
  wchar_t class_name[128]{};
  if (owner == query.process_id &&
      GetClassNameW(window, class_name, 128) != 0 &&
      std::wcscmp(class_name, L"FLUTTER_RUNNER_WIN32_WINDOW") == 0) {
    query.window = window;
    return FALSE;
  }
  return TRUE;
}

int ProbeRunner(DWORD process_id) {
  WindowQuery query{process_id};
  EnumWindows(FindRunnerWindow, reinterpret_cast<LPARAM>(&query));
  if (!query.window) return 2;
  MINMAXINFO sizes{};
  DWORD_PTR result{};
  if (!SendMessageTimeoutW(query.window, WM_GETMINMAXINFO, 0,
                          reinterpret_cast<LPARAM>(&sizes), SMTO_ABORTIFHUNG,
                          2000, &result)) return 3;
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfoW(MonitorFromWindow(query.window, MONITOR_DEFAULTTONEAREST),
                      &monitor)) return 4;
  const LONG width = monitor.rcWork.right - monitor.rcWork.left;
  const LONG height = monitor.rcWork.bottom - monitor.rcWork.top;
  if (sizes.ptMinTrackSize.x <= 0 || sizes.ptMinTrackSize.y <= 0 ||
      sizes.ptMinTrackSize.x > width || sizes.ptMinTrackSize.y > height) return 5;
  std::cout << "PASS min_track=" << sizes.ptMinTrackSize.x << ','
            << sizes.ptMinTrackSize.y << " work_area=" << width << ',' << height
            << '\n';
  return 0;
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc == 2) {
    DWORD process_id{};
    const auto parsed = std::from_chars(argv[1], argv[1] + std::strlen(argv[1]),
                                        process_id);
    if (parsed.ec != std::errc{} || *parsed.ptr != '\0') return 1;
    return ProbeRunner(process_id);
  }
  for (const RECT work : {RECT{0, 0, 1920, 1040}, RECT{0, 0, 1366, 728},
                          RECT{-1280, 40, 0, 720}}) {
    for (const double scale : {1.0, 1.25, 1.5, 1.75, 2.0, 2.5}) {
      MINMAXINFO sizes{};
      sizes.ptMinTrackSize = {static_cast<LONG>(std::lround(420 * scale)),
                              static_cast<LONG>(std::lround(560 * scale))};
      sizes.ptMaxTrackSize = {4000, 3000};
      const POINT before = sizes.ptMinTrackSize;
      window_layout::ConstrainMinimumTrackSize(sizes, work);
      assert(sizes.ptMinTrackSize.x == (std::min)(before.x, work.right - work.left));
      assert(sizes.ptMinTrackSize.y == (std::min)(before.y, work.bottom - work.top));
      assert(sizes.ptMaxTrackSize.x == 4000 && sizes.ptMaxTrackSize.y == 3000);
    }
  }
  MINMAXINFO unchanged{};
  unchanged.ptMinTrackSize = {420, 560};
  window_layout::ConstrainMinimumTrackSize(unchanged, RECT{});
  assert(unchanged.ptMinTrackSize.x == 420 && unchanged.ptMinTrackSize.y == 560);
  std::cout << "PASS minimum size: 18 DPI/work-area combinations and invalid work area\n";
}
