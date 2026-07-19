#ifndef RUNNER_WINDOWS_SMTC_H_
#define RUNNER_WINDOWS_SMTC_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <atomic>
#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <string>

#include <winrt/Windows.Media.h>

class WindowsSmtc {
 public:
  WindowsSmtc(HWND window, flutter::BinaryMessenger* messenger);
  ~WindowsSmtc();

  WindowsSmtc(const WindowsSmtc&) = delete;
  WindowsSmtc& operator=(const WindowsSmtc&) = delete;

  std::optional<LRESULT> HandleWindowMessage(UINT message, WPARAM wparam,
                                              LPARAM lparam);

 private:
  struct PendingCommand {
    std::string method;
    int64_t position_ms = 0;
  };

  struct CallbackState {
    explicit CallbackState(HWND window_handle) : window(window_handle) {}

    HWND window;
    std::atomic<bool> closing{false};
    std::mutex mutex;
    std::deque<PendingCommand> commands;
  };

  static constexpr UINT kSmtcCommandMessage = WM_APP + 0x534;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void InitializeSession();
  void DisposeSession();
  void SetEnabled(bool enabled);
  void UpdateMetadata(const flutter::EncodableMap& arguments);
  void SetPlaybackStatus(const std::string& status);
  void UpdateTimeline(int64_t position_ms, int64_t duration_ms);
  static void QueueCommand(const std::shared_ptr<CallbackState>& state,
                           std::string method, int64_t position_ms = 0);
  void DrainCommands();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::shared_ptr<CallbackState> callback_state_;
  winrt::Windows::Media::SystemMediaTransportControls smtc_{nullptr};
  winrt::event_token button_pressed_token_{};
  winrt::event_token position_change_token_{};
  bool button_handler_registered_ = false;
  bool position_handler_registered_ = false;
};

#endif  // RUNNER_WINDOWS_SMTC_H_
