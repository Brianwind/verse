#include <bitsdojo_window_windows/bitsdojo_window_plugin.h>
auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP);
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include "app_identity.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

class ScopedComInitializer {
 public:
  ScopedComInitializer()
      : result_(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
  ~ScopedComInitializer() {
    if (SUCCEEDED(result_)) {
      ::CoUninitialize();
    }
  }

  HRESULT result() const { return result_; }

 private:
  HRESULT result_;
};

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ScopedComInitializer com_initializer;
  const HRESULT process_identity_result =
      ::SetCurrentProcessExplicitAppUserModelID(kVerseAppUserModelId);
  if (FAILED(process_identity_result)) {
    OutputDebugStringW(
        L"Verse: failed to set the Windows application identity.\n");
  }
  if (SUCCEEDED(com_initializer.result())) {
    const HRESULT identity_result = RegisterVerseAppIdentity();
    if (FAILED(identity_result)) {
      OutputDebugStringW(
          L"Verse: failed to register Windows application identity.\n");
    }
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Verse", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  return EXIT_SUCCESS;
}
