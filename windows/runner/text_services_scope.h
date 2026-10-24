#ifndef RUNNER_TEXT_SERVICES_SCOPE_H_
#define RUNNER_TEXT_SERVICES_SCOPE_H_

#include <windows.h>

#include <msctf.h>
#include <wrl/client.h>

// Keep TSF activated on the UI thread across native focus and input-profile
// changes. Holding a COM reference alone does not hold an activation. Create
// this after COM initialization and destroy it after all Flutter windows, on
// the same thread and before CoUninitialize.
class TextServicesScope {
 public:
  TextServicesScope() {
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&manager_)))) {
      TfClientId client = TF_CLIENTID_NULL;
      active_ = SUCCEEDED(manager_->Activate(&client));
    }
  }

  ~TextServicesScope() {
    if (active_) manager_->Deactivate();
  }

  TextServicesScope(const TextServicesScope&) = delete;
  TextServicesScope& operator=(const TextServicesScope&) = delete;
  TextServicesScope(TextServicesScope&&) = delete;
  TextServicesScope& operator=(TextServicesScope&&) = delete;

  bool active() const noexcept { return active_; }

 private:
  Microsoft::WRL::ComPtr<ITfThreadMgr> manager_;
  bool active_ = false;
};

#endif  // RUNNER_TEXT_SERVICES_SCOPE_H_
