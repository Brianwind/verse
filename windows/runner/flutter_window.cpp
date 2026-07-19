#include "flutter_window.h"

#include <optional>
#include <propkey.h>
#include <propvarutil.h>
#include <shobjidl.h>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "windows_smtc.h"

namespace {

constexpr wchar_t kVerseAppUserModelId[] = L"Verse.Player";

void ApplyVerseWindowIdentity(HWND window) {
  IPropertyStore* property_store = nullptr;
  if (FAILED(SHGetPropertyStoreForWindow(
          window, IID_PPV_ARGS(&property_store)))) {
    return;
  }

  PROPVARIANT value;
  if (SUCCEEDED(InitPropVariantFromString(kVerseAppUserModelId, &value))) {
    property_store->SetValue(PKEY_AppUserModel_ID, value);
    PropVariantClear(&value);
  }

  wchar_t executable_path[MAX_PATH] = {};
  if (GetModuleFileName(nullptr, executable_path, MAX_PATH) > 0) {
    const std::wstring display_name_resource =
        L"@" + std::wstring(executable_path) + L",-102";
    if (SUCCEEDED(InitPropVariantFromString(display_name_resource.c_str(),
                                            &value))) {
      property_store->SetValue(
          PKEY_AppUserModel_RelaunchDisplayNameResource, value);
      PropVariantClear(&value);
    }
  }

  property_store->Commit();
  property_store->Release();
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  ApplyVerseWindowIdentity(GetHandle());

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  windows_smtc_ = std::make_unique<WindowsSmtc>(
      GetHandle(), flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  windows_smtc_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (windows_smtc_) {
    const auto result =
        windows_smtc_->HandleWindowMessage(message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
