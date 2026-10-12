// Exercise the patched production ANGLE implementation on a real D3D11 device.
// Readback is confined to this test's staging texture, never the player path.
#include "angle_surface_manager.h"

#include <array>
#include <iostream>
#include <memory>
#include <stdexcept>

namespace {
void Require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

Microsoft::WRL::ComPtr<ID3D11Device> CurrentDevice() {
  const auto query_display = reinterpret_cast<PFNEGLQUERYDISPLAYATTRIBEXTPROC>(
      eglGetProcAddress("eglQueryDisplayAttribEXT"));
  const auto query_device = reinterpret_cast<PFNEGLQUERYDEVICEATTRIBEXTPROC>(
      eglGetProcAddress("eglQueryDeviceAttribEXT"));
  EGLAttrib device = 0;
  EGLAttrib d3d = 0;
  Require(query_display != nullptr && query_device != nullptr,
          "ANGLE device query is unavailable");
  Require(query_display(eglGetCurrentDisplay(), EGL_DEVICE_EXT, &device) ==
                  EGL_TRUE &&
              query_device(reinterpret_cast<EGLDeviceEXT>(device),
                           EGL_D3D11_DEVICE_ANGLE, &d3d) == EGL_TRUE,
          "Cannot inspect the current ANGLE D3D11 device");
  Microsoft::WRL::ComPtr<ID3D11Device> result =
      reinterpret_cast<ID3D11Device *>(d3d);
  return result;
}

void CheckPixels(ID3D11Device *device, HANDLE handle, int width, int height,
                 const std::array<uint8_t, 4> &expected) {
  Microsoft::WRL::ComPtr<ID3D11Texture2D> source;
  Require(SUCCEEDED(device->OpenSharedResource(handle, IID_PPV_ARGS(&source))),
          "Cannot open delivered texture");
  D3D11_TEXTURE2D_DESC descriptor{};
  source->GetDesc(&descriptor);
  Require(descriptor.Width == static_cast<UINT>(width) &&
              descriptor.Height == static_cast<UINT>(height),
          "Delivered texture has stale dimensions");
  descriptor.Usage = D3D11_USAGE_STAGING;
  descriptor.BindFlags = 0;
  descriptor.MiscFlags = 0;
  descriptor.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> staging;
  Require(SUCCEEDED(device->CreateTexture2D(&descriptor, nullptr, &staging)),
          "Cannot create test-only staging texture");
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
  device->GetImmediateContext(&context);
  context->CopyResource(staging.Get(), source.Get());
  D3D11_MAPPED_SUBRESOURCE mapped{};
  Require(SUCCEEDED(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped)),
          "Cannot map test-only staging texture");
  bool valid = true;
  for (int y = 0; y < height; ++y) {
    const auto *row = static_cast<const uint8_t *>(mapped.pData) +
                      static_cast<size_t>(y) * mapped.RowPitch;
    for (int x = 0; x < width; ++x) {
      for (size_t channel = 0; channel < expected.size(); ++channel) {
        valid = valid &&
                row[static_cast<size_t>(x) * 4 + channel] == expected[channel];
      }
    }
  }
  context->Unmap(staging.Get(), 0);
  Require(valid, "Texture contains stale or torn pixels");
}
} // namespace

int main() {
  try {
    auto producer = std::make_unique<ANGLESurfaceManager>(64, 32);
    ANGLESurfaceManager consumer(64, 32);
    consumer.MakeCurrent(true);
    const auto device = CurrentDevice();
    consumer.MakeCurrent(false);
    for (int frame = 0; frame < 100; ++frame) {
      const bool red = frame % 2 == 0;
      producer->Draw([red] {
        glClearColor(red ? 1.0f : 0.0f, 0.0f, red ? 0.0f : 1.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
      });
      consumer.MakeCurrent(true);
      const auto handle = producer->Read();
      Require(handle != producer->handle(), "Same-device path still copies");
      CheckPixels(device.Get(), handle, 64, 32,
                  red ? std::array<uint8_t, 4>{0, 0, 255, 255}
                      : std::array<uint8_t, 4>{255, 0, 0, 255});
      consumer.MakeCurrent(false);
    }
    // No current consumer context must use the separate copied texture.
    producer->Draw([] {
      glClearColor(0, 1, 0, 1);
      glClear(GL_COLOR_BUFFER_BIT);
    });
    const auto copied = producer->Read();
    Require(copied == producer->handle(), "Unknown consumer bypassed copying");
    CheckPixels(device.Get(), copied, 64, 32, {0, 255, 0, 255});
    Require(producer->Read() == copied, "Unchanged frame changed its delivery");
    producer->SetSize(32, 16);
    producer->Draw([] {
      glClearColor(1, 1, 1, 1);
      glClear(GL_COLOR_BUFFER_BIT);
    });
    consumer.MakeCurrent(true);
    CheckPixels(device.Get(), producer->Read(), 32, 16, {255, 255, 255, 255});
    consumer.MakeCurrent(false);
    producer.reset();
    // Disposing a player cannot terminate Flutter's still-live EGL display.
    consumer.Draw([] {
      glClearColor(0, 1, 0, 1);
      glClear(GL_COLOR_BUFFER_BIT);
    });
    consumer.MakeCurrent(true);
    CheckPixels(device.Get(), consumer.Read(), 64, 32, {0, 255, 0, 255});
    consumer.MakeCurrent(false);
    std::cout << "PASS: 100 same-device frames, copied fallback, resize and "
                 "shared-display lifetime\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
