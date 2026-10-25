#include "image_export.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <array>
#include <algorithm>
#include <cstring>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace {
constexpr size_t kMaxBytes = 32 * 1024 * 1024;
constexpr uint64_t kMaxPixels = 64 * 1024 * 1024;

// Ownership transfers to Windows only after SetClipboardData succeeds.
class GlobalMemory {
 public:
  explicit GlobalMemory(size_t size) : value_(GlobalAlloc(GMEM_MOVEABLE, size)) {}
  ~GlobalMemory() { if (value_) GlobalFree(value_); }
  GlobalMemory(const GlobalMemory&) = delete;
  GlobalMemory& operator=(const GlobalMemory&) = delete;
  void* Lock() { return value_ ? GlobalLock(value_) : nullptr; }
  void Unlock() { GlobalUnlock(value_); }
  bool Publish(UINT format) {
    if (!SetClipboardData(format, value_)) return false;
    value_ = nullptr;
    return true;
  }
 private:
  HGLOBAL value_;
};

class ClipboardScope {
 public:
  explicit ClipboardScope(HWND owner) : opened_(OpenClipboard(owner) != FALSE) {}
  ~ClipboardScope() { if (opened_) CloseClipboard(); }
  bool opened() const { return opened_; }
  ClipboardScope(const ClipboardScope&) = delete;
  ClipboardScope& operator=(const ClipboardScope&) = delete;
 private:
  bool opened_;
};

bool CopyImage(HWND owner, const std::vector<uint8_t>& bytes, bool is_png) {
  Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                             CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) return false;
  Microsoft::WRL::ComPtr<IStream> stream;
  stream.Attach(SHCreateMemStream(bytes.data(), static_cast<UINT>(bytes.size())));
  if (!stream) return false;
  Microsoft::WRL::ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromStream(stream.Get(), nullptr,
      WICDecodeMetadataCacheOnDemand, &decoder))) return false;
  Microsoft::WRL::ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame))) return false;
  UINT width = 0, height = 0;
  if (FAILED(frame->GetSize(&width, &height)) || !width || !height ||
      width > 262144 || height > 262144 ||
      static_cast<uint64_t>(width) * height > kMaxPixels) return false;
  Microsoft::WRL::ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA,
          WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom))) return false;

  const UINT stride = width * 4;
  const UINT pixel_bytes = stride * height;
  GlobalMemory dib(sizeof(BITMAPV5HEADER) + pixel_bytes);
  auto* header = static_cast<BITMAPV5HEADER*>(dib.Lock());
  if (!header) return false;
  *header = {};
  header->bV5Size = sizeof(BITMAPV5HEADER);
  header->bV5Width = static_cast<LONG>(width);
  header->bV5Height = -static_cast<LONG>(height);
  header->bV5Planes = 1;
  header->bV5BitCount = 32;
  header->bV5Compression = BI_BITFIELDS;
  header->bV5SizeImage = pixel_bytes;
  header->bV5RedMask = 0x00ff0000;
  header->bV5GreenMask = 0x0000ff00;
  header->bV5BlueMask = 0x000000ff;
  header->bV5AlphaMask = 0xff000000;
  header->bV5CSType = LCS_sRGB;
  const HRESULT status = converter->CopyPixels(nullptr, stride, pixel_bytes,
      reinterpret_cast<BYTE*>(header + 1));
  dib.Unlock();
  if (FAILED(status)) return false;

  GlobalMemory png(is_png ? bytes.size() : 1);
  if (is_png) {
    void* data = png.Lock();
    if (!data) return false;
    std::memcpy(data, bytes.data(), bytes.size());
    png.Unlock();
  }
  ClipboardScope clipboard(owner);
  if (!clipboard.opened() || !EmptyClipboard()) return false;
  if (!dib.Publish(CF_DIBV5)) return false;
  if (is_png) {
    const UINT format = RegisterClipboardFormatW(L"PNG");
    if (format) png.Publish(format);
  }
  return true;
}

std::string SaveImage(const std::vector<uint8_t>& bytes, const std::string& extension) {
  PWSTR raw_folder = nullptr;
  const HRESULT status = SHGetKnownFolderPath(FOLDERID_Pictures, KF_FLAG_CREATE,
                                             nullptr, &raw_folder);
  std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> folder(raw_folder, CoTaskMemFree);
  if (FAILED(status) || !folder) return {};
  const auto directory = std::filesystem::path(folder.get()) / L"BiliSail";
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  if (error) return {};
  GUID id{};
  std::array<wchar_t, 40> name{};
  if (FAILED(CoCreateGuid(&id)) || !StringFromGUID2(id, name.data(),
      static_cast<int>(name.size()))) return {};
  const auto file = directory / (std::wstring(L"BiliSail-") + name.data() + L"." +
      std::wstring(extension.begin(), extension.end()));
  const HANDLE raw_file = CreateFileW(file.c_str(), GENERIC_WRITE, 0, nullptr,
                                     CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (raw_file == INVALID_HANDLE_VALUE) return {};
  std::unique_ptr<void, decltype(&CloseHandle)> handle(raw_file, CloseHandle);
  DWORD written = 0;
  const bool saved = WriteFile(handle.get(), bytes.data(), static_cast<DWORD>(bytes.size()),
                               &written, nullptr) && written == bytes.size() &&
                     FlushFileBuffers(handle.get());
  handle.reset();
  if (!saved) { DeleteFileW(file.c_str()); return {}; }
  return file.u8string();
}
}  // namespace

ImageExportChannel::ImageExportChannel(flutter::BinaryMessenger* messenger, HWND owner)
    : channel_(messenger, "bilisail/image_export", &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler([owner](const auto& call, auto result) {
    if (call.method_name() != "save" && call.method_name() != "copy") {
      result->NotImplemented(); return;
    }
    const auto* args = call.arguments()
        ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    if (!args) { result->Error("invalid_image", "Expected image data"); return; }
    const auto data = args->find(flutter::EncodableValue("bytes"));
    const auto format = args->find(flutter::EncodableValue("extension"));
    const auto* bytes = data != args->end() ? std::get_if<std::vector<uint8_t>>(&data->second) : nullptr;
    const auto* extension = format != args->end() ? std::get_if<std::string>(&format->second) : nullptr;
    const std::array<std::string, 6> formats{"png", "jpg", "gif", "webp", "bmp", "avif"};
    if (!bytes || bytes->empty() || bytes->size() > kMaxBytes || !extension ||
        std::find(formats.begin(), formats.end(), *extension) == formats.end()) {
      result->Error("invalid_image", "Invalid image data"); return;
    }
    try {
      if (call.method_name() == "save") {
        const auto path = SaveImage(*bytes, *extension);
        if (path.empty()) { result->Error("save_failed", "Could not save image"); return; }
        result->Success(flutter::EncodableValue(path));
      } else {
        if (!CopyImage(owner, *bytes, *extension == "png")) {
          result->Error("copy_failed", "Could not copy image"); return;
        }
        result->Success();
      }
    } catch (const std::exception&) {
      result->Error("export_failed", "Could not export image");
    }
  });
}

ImageExportChannel::~ImageExportChannel() { channel_.SetMethodCallHandler(nullptr); }
