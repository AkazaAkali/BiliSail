// Standalone native regression for the internal WIC/clipboard/file helpers.
#include "../runner/image_export.cpp"

#include <fstream>
#include <iostream>
#include <iterator>

namespace {
void Check(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

std::vector<uint8_t> LongPng() {
  Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
  Check(SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory))), "WIC factory unavailable");
  Microsoft::WRL::ComPtr<IStream> stream;
  Check(SUCCEEDED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)), "PNG stream unavailable");
  Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder;
  Check(SUCCEEDED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)), "PNG encoder unavailable");
  Check(SUCCEEDED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)), "PNG encoder init failed");
  Microsoft::WRL::ComPtr<IWICBitmapFrameEncode> frame;
  Check(SUCCEEDED(encoder->CreateNewFrame(&frame, nullptr)) && SUCCEEDED(frame->Initialize(nullptr)), "PNG frame unavailable");
  Check(SUCCEEDED(frame->SetSize(8, 24000)), "Long PNG size rejected");
  GUID format = GUID_WICPixelFormat32bppBGRA;
  Check(SUCCEEDED(frame->SetPixelFormat(&format)) && format == GUID_WICPixelFormat32bppBGRA, "PNG pixel format rejected");
  std::vector<uint8_t> pixels(8 * 24000 * 4, 255);
  Check(SUCCEEDED(frame->WritePixels(24000, 8 * 4, static_cast<UINT>(pixels.size()), pixels.data())) &&
      SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit()), "Long PNG encode failed");
  STATSTG info{};
  Check(SUCCEEDED(stream->Stat(&info, STATFLAG_NONAME)) && info.cbSize.HighPart == 0, "PNG stream size failed");
  std::vector<uint8_t> bytes(info.cbSize.LowPart);
  LARGE_INTEGER start{};
  ULONG read = 0;
  Check(SUCCEEDED(stream->Seek(start, STREAM_SEEK_SET, nullptr)) &&
      SUCCEEDED(stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read)) && read == bytes.size(), "PNG stream read failed");
  return bytes;
}

class IsolatedClipboard {
 public:
  IsolatedClipboard() {
    original_station_ = GetProcessWindowStation();
    original_desktop_ = GetThreadDesktop(GetCurrentThreadId());
    station_ = CreateWindowStationW(nullptr, 0, WINSTA_ALL_ACCESS, nullptr);
    Check(station_ != nullptr, "Could not create isolated window station");
    Check(SetProcessWindowStation(station_) != FALSE, "Could not select isolated station");
    desktop_ = CreateDesktopW(L"ImageExportTest", nullptr, nullptr, 0, GENERIC_ALL, nullptr);
    Check(desktop_ != nullptr && SetThreadDesktop(desktop_), "Could not select isolated desktop");
    window_ = CreateWindowExW(0, L"STATIC", L"", 0, 0, 0, 1, 1, nullptr, nullptr, nullptr, nullptr);
    Check(window_ != nullptr, "Could not create clipboard owner");
  }
  ~IsolatedClipboard() {
    if (window_) DestroyWindow(window_);
    SetThreadDesktop(original_desktop_);
    SetProcessWindowStation(original_station_);
    if (desktop_) CloseDesktop(desktop_);
    if (station_) CloseWindowStation(station_);
  }
  HWND owner() const { return window_; }
 private:
  HWINSTA original_station_ = nullptr, station_ = nullptr;
  HDESK original_desktop_ = nullptr, desktop_ = nullptr;
  HWND window_ = nullptr;
};
}  // namespace

int main(int argc, char** argv) {
  try {
    Check(argc == 2, "Expected a PNG fixture path");
    // A separate window station gives this process its own real clipboard.
    // The interactive user's clipboard is never opened or modified.
    IsolatedClipboard clipboard;
    Check(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)), "COM initialization failed");
    std::ifstream input(argv[1], std::ios::binary);
    const std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
    Check(!bytes.empty(), "Could not read PNG fixture");
    Check(CopyImage(clipboard.owner(), bytes, true), "WIC image copy failed");
    Check(OpenClipboard(clipboard.owner()) != FALSE, "Could not read test clipboard");
    const UINT png_format = RegisterClipboardFormatW(L"PNG");
    const auto png = GetClipboardData(png_format);
    const auto dib = GetClipboardData(CF_DIBV5);
    Check(png && dib, "PNG and DIBV5 must both be available");
    const void* png_data = GlobalLock(png);
    Check(png_data && std::memcmp(png_data, bytes.data(), bytes.size()) == 0, "Clipboard PNG differs from original");
    GlobalUnlock(png);
    const auto* header = static_cast<const BITMAPV5HEADER*>(GlobalLock(dib));
    Check(header && header->bV5Width > 0 && header->bV5Height < 0 && header->bV5BitCount == 32 &&
          header->bV5AlphaMask == 0xff000000, "Invalid top-down alpha bitmap");
    GlobalUnlock(dib);
    CloseClipboard();
    Check(!CopyImage(clipboard.owner(), {1, 2, 3}, false), "Corrupt input was accepted");
    Check(IsClipboardFormatAvailable(png_format) != FALSE, "Failed copy cleared the clipboard");

    const auto long_png = LongPng();
    Check(CopyImage(clipboard.owner(), long_png, true), "Long original copy failed");
    Check(OpenClipboard(clipboard.owner()) != FALSE, "Could not read long image clipboard");
    const auto long_dib = GetClipboardData(CF_DIBV5);
    const auto* long_header = static_cast<const BITMAPV5HEADER*>(GlobalLock(long_dib));
    Check(long_header && long_header->bV5Width == 8 && long_header->bV5Height == -24000,
          "Long clipboard image was resized or cropped");
    GlobalUnlock(long_dib);
    CloseClipboard();

    const auto path = SaveImage(bytes, "png");
    Check(!path.empty(), "Could not save into the system Pictures directory");
    const auto file = std::filesystem::u8path(path);
    std::ifstream saved(file, std::ios::binary);
    const std::vector<uint8_t> saved_bytes((std::istreambuf_iterator<char>(saved)), {});
    saved.close();
    std::error_code error;
    std::filesystem::remove(file, error);
    Check(!error, "Could not remove this test's saved file");
    Check(saved_bytes == bytes && file.parent_path().filename() == L"BiliSail", "Saved original mismatch");
    CoUninitialize();
    std::cout << "Native image export passed: real WIC/isolated clipboard/original save/cleanup.\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
