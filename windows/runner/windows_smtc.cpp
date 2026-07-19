#include "windows_smtc.h"

#include <flutter/standard_method_codec.h>
#include <systemmediatransportcontrolsinterop.h>

#include <algorithm>
#include <chrono>
#include <utility>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::TimeSpan;
using winrt::Windows::Foundation::Uri;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using winrt::Windows::Media::PlaybackPositionChangeRequestedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

const EncodableValue* FindArgument(const EncodableMap& arguments,
                                   const char* key) {
  const auto iterator = arguments.find(EncodableValue(key));
  return iterator == arguments.end() ? nullptr : &iterator->second;
}

std::string StringArgument(const EncodableMap& arguments, const char* key) {
  const auto* value = FindArgument(arguments, key);
  if (value == nullptr) return {};
  const auto* string_value = std::get_if<std::string>(value);
  return string_value == nullptr ? std::string{} : *string_value;
}

bool BoolArgument(const EncodableMap& arguments, const char* key,
                  bool fallback = false) {
  const auto* value = FindArgument(arguments, key);
  if (value == nullptr) return fallback;
  const auto* bool_value = std::get_if<bool>(value);
  return bool_value == nullptr ? fallback : *bool_value;
}

int64_t IntArgument(const EncodableMap& arguments, const char* key,
                    int64_t fallback = 0) {
  const auto* value = FindArgument(arguments, key);
  if (value == nullptr) return fallback;
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return *int64_value;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  return fallback;
}

TimeSpan MillisecondsToTimeSpan(int64_t milliseconds) {
  return std::chrono::duration_cast<TimeSpan>(
      std::chrono::milliseconds(std::max<int64_t>(0, milliseconds)));
}

int64_t TimeSpanToMilliseconds(TimeSpan time_span) {
  return std::chrono::duration_cast<std::chrono::milliseconds>(time_span)
      .count();
}

}  // namespace

WindowsSmtc::WindowsSmtc(HWND window, flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "verse/windows_smtc",
          &flutter::StandardMethodCodec::GetInstance())),
      callback_state_(std::make_shared<CallbackState>(window)) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

WindowsSmtc::~WindowsSmtc() {
  callback_state_->closing.store(true);
  channel_->SetMethodCallHandler(nullptr);
  try {
    DisposeSession();
  } catch (const winrt::hresult_error&) {
    // The window or media session may already have been torn down by Windows.
  }
}

void WindowsSmtc::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    const auto* arguments = std::get_if<EncodableMap>(call.arguments());
    const EncodableMap empty_arguments;
    const EncodableMap& args = arguments == nullptr ? empty_arguments : *arguments;

    if (call.method_name() == "initialize") {
      InitializeSession();
    } else if (call.method_name() == "setEnabled") {
      SetEnabled(BoolArgument(args, "enabled"));
    } else if (call.method_name() == "updateMetadata") {
      UpdateMetadata(args);
    } else if (call.method_name() == "setPlaybackStatus") {
      SetPlaybackStatus(StringArgument(args, "status"));
    } else if (call.method_name() == "updateTimeline") {
      UpdateTimeline(IntArgument(args, "positionMs"),
                     IntArgument(args, "durationMs"));
    } else if (call.method_name() == "dispose") {
      DisposeSession();
    } else {
      result->NotImplemented();
      return;
    }
    result->Success();
  } catch (const winrt::hresult_error& error) {
    result->Error("windows_smtc_error", winrt::to_string(error.message()));
  } catch (const std::exception& error) {
    result->Error("windows_smtc_error", error.what());
  }
}

void WindowsSmtc::InitializeSession() {
  if (smtc_) return;

  auto interop = winrt::get_activation_factory<
      SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
  winrt::check_hresult(interop->GetForWindow(
      callback_state_->window, winrt::guid_of<SystemMediaTransportControls>(),
      winrt::put_abi(smtc_)));

  smtc_.IsEnabled(false);
  smtc_.IsPlayEnabled(true);
  smtc_.IsPauseEnabled(true);
  smtc_.IsNextEnabled(true);
  smtc_.IsPreviousEnabled(true);
  smtc_.IsStopEnabled(false);
  smtc_.IsFastForwardEnabled(false);
  smtc_.IsRewindEnabled(false);

  auto updater = smtc_.DisplayUpdater();
  updater.Type(MediaPlaybackType::Music);

  const std::weak_ptr<CallbackState> weak_state = callback_state_;
  button_pressed_token_ = smtc_.ButtonPressed(
      [weak_state](const SystemMediaTransportControls&,
             const SystemMediaTransportControlsButtonPressedEventArgs& args) {
        const auto state = weak_state.lock();
        if (!state || state->closing.load()) return;
        switch (args.Button()) {
          case SystemMediaTransportControlsButton::Play:
            QueueCommand(state, "play");
            break;
          case SystemMediaTransportControlsButton::Pause:
            QueueCommand(state, "pause");
            break;
          case SystemMediaTransportControlsButton::Next:
            QueueCommand(state, "next");
            break;
          case SystemMediaTransportControlsButton::Previous:
            QueueCommand(state, "previous");
            break;
          default:
            break;
        }
      });
  button_handler_registered_ = true;

  position_change_token_ = smtc_.PlaybackPositionChangeRequested(
      [weak_state](
          const SystemMediaTransportControls&,
          const PlaybackPositionChangeRequestedEventArgs& args) {
        const auto state = weak_state.lock();
        if (!state || state->closing.load()) return;
        QueueCommand(
            state, "seek",
            TimeSpanToMilliseconds(args.RequestedPlaybackPosition()));
      });
  position_handler_registered_ = true;
}

void WindowsSmtc::DisposeSession() {
  if (!smtc_) return;

  smtc_.IsEnabled(false);
  if (button_handler_registered_) {
    smtc_.ButtonPressed(button_pressed_token_);
    button_handler_registered_ = false;
  }
  if (position_handler_registered_) {
    smtc_.PlaybackPositionChangeRequested(position_change_token_);
    position_handler_registered_ = false;
  }
  smtc_ = nullptr;

  std::lock_guard<std::mutex> lock(callback_state_->mutex);
  callback_state_->commands.clear();
}

void WindowsSmtc::SetEnabled(bool enabled) {
  InitializeSession();
  smtc_.IsEnabled(enabled);
}

void WindowsSmtc::UpdateMetadata(const EncodableMap& arguments) {
  InitializeSession();

  auto updater = smtc_.DisplayUpdater();
  updater.Type(MediaPlaybackType::Music);
  auto properties = updater.MusicProperties();
  properties.Title(winrt::to_hstring(StringArgument(arguments, "title")));
  properties.Artist(winrt::to_hstring(StringArgument(arguments, "artist")));
  properties.AlbumTitle(winrt::to_hstring(StringArgument(arguments, "album")));

  const auto thumbnail_url = StringArgument(arguments, "thumbnailUrl");
  if (thumbnail_url.empty()) {
    updater.Thumbnail(nullptr);
  } else {
    try {
      updater.Thumbnail(RandomAccessStreamReference::CreateFromUri(
          Uri(winrt::to_hstring(thumbnail_url))));
    } catch (const winrt::hresult_error&) {
      updater.Thumbnail(nullptr);
    }
  }
  updater.Update();
  UpdateTimeline(0, 1);
}

void WindowsSmtc::SetPlaybackStatus(const std::string& status) {
  InitializeSession();
  if (status == "playing") {
    smtc_.PlaybackStatus(MediaPlaybackStatus::Playing);
  } else if (status == "paused") {
    smtc_.PlaybackStatus(MediaPlaybackStatus::Paused);
  } else if (status == "changing") {
    smtc_.PlaybackStatus(MediaPlaybackStatus::Changing);
  } else {
    smtc_.PlaybackStatus(MediaPlaybackStatus::Stopped);
  }
}

void WindowsSmtc::UpdateTimeline(int64_t position_ms, int64_t duration_ms) {
  InitializeSession();
  duration_ms = std::max<int64_t>(0, duration_ms);
  position_ms = std::clamp<int64_t>(position_ms, 0, duration_ms);

  SystemMediaTransportControlsTimelineProperties timeline;
  timeline.StartTime(MillisecondsToTimeSpan(0));
  timeline.MinSeekTime(MillisecondsToTimeSpan(0));
  timeline.Position(MillisecondsToTimeSpan(position_ms));
  timeline.MaxSeekTime(MillisecondsToTimeSpan(duration_ms));
  timeline.EndTime(MillisecondsToTimeSpan(duration_ms));
  smtc_.UpdateTimelineProperties(timeline);
}

void WindowsSmtc::QueueCommand(const std::shared_ptr<CallbackState>& state,
                               std::string method, int64_t position_ms) {
  if (state->closing.load()) return;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->closing.load()) return;
    state->commands.push_back({std::move(method), position_ms});
  }
  PostMessage(state->window, kSmtcCommandMessage, 0, 0);
}

void WindowsSmtc::DrainCommands() {
  std::deque<PendingCommand> commands;
  {
    std::lock_guard<std::mutex> lock(callback_state_->mutex);
    commands.swap(callback_state_->commands);
  }

  for (const auto& command : commands) {
    if (command.method == "seek") {
      EncodableMap arguments;
      arguments[EncodableValue("positionMs")] =
          EncodableValue(command.position_ms);
      channel_->InvokeMethod(
          command.method,
          std::make_unique<EncodableValue>(std::move(arguments)));
    } else {
      channel_->InvokeMethod(command.method, nullptr);
    }
  }
}

std::optional<LRESULT> WindowsSmtc::HandleWindowMessage(UINT message,
                                                         WPARAM,
                                                         LPARAM) {
  if (message != kSmtcCommandMessage) return std::nullopt;
  DrainCommands();
  return 0;
}
