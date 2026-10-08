#include "flutter_window.h"

#include <windows.h>

#include <climits>
#include <cstdint>
#include <cstring>
#include <limits>
#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

bool ConvertUtf8PathToWide(const std::string& path, std::wstring* wide_path) {
  const size_t path_length = std::strlen(path.c_str());
  if (path_length == 0 || path_length > INT_MAX ||
      path_length != path.size()) {
    return false;
  }

  const int utf8_length = static_cast<int>(path_length);
  const int wide_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, path.data(), utf8_length, nullptr, 0);
  if (wide_length <= 0) {
    return false;
  }

  wide_path->assign(static_cast<size_t>(wide_length), L'\0');
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.data(),
                             utf8_length, wide_path->data(), wide_length) ==
         wide_length;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

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

  network_bridge_ = std::make_unique<NetworkBridge>(
      flutter_controller_->engine()->messenger(), GetHandle());

  storage_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "io.imagehost/storage_capacity",
      &flutter::StandardMethodCodec::GetInstance());
  storage_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "publishExclusive") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("invalid_argument", "Invalid file arguments.");
            return;
          }

          const auto source_it =
              arguments->find(flutter::EncodableValue("source"));
          const auto destination_it =
              arguments->find(flutter::EncodableValue("destination"));
          const auto* source = source_it == arguments->end()
                                   ? nullptr
                                   : std::get_if<std::string>(&source_it->second);
          const auto* destination =
              destination_it == arguments->end()
                  ? nullptr
                  : std::get_if<std::string>(&destination_it->second);
          std::wstring wide_source;
          std::wstring wide_destination;
          if (source == nullptr || destination == nullptr ||
              !ConvertUtf8PathToWide(*source, &wide_source) ||
              !ConvertUtf8PathToWide(*destination, &wide_destination)) {
            result->Error("invalid_argument", "Invalid file arguments.");
            return;
          }

          if (MoveFileExW(wide_source.c_str(), wide_destination.c_str(),
                          MOVEFILE_WRITE_THROUGH)) {
            result->Success(flutter::EncodableValue(true));
            return;
          }

          const DWORD error = GetLastError();
          if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          result->Error("publish_error", "Unable to publish the backup file.");
          return;
        }

        if (call.method_name() != "availableBytes") {
          result->NotImplemented();
          return;
        }

        const auto* directory =
            std::get_if<std::string>(call.arguments());
        if (directory == nullptr) {
          result->Error("invalid_argument", "Invalid directory argument.");
          return;
        }

        std::wstring path;
        if (!ConvertUtf8PathToWide(*directory, &path)) {
          result->Error("invalid_argument", "Invalid directory argument.");
          return;
        }

        ULARGE_INTEGER available_bytes = {};
        if (!GetDiskFreeSpaceExW(path.c_str(), &available_bytes, nullptr,
                                 nullptr)) {
          result->Error("read_error", "Unable to read available storage.");
          return;
        }
        if (available_bytes.QuadPart >
            static_cast<ULONGLONG>((std::numeric_limits<int64_t>::max)())) {
          result->Error("read_error", "Unable to read available storage.");
          return;
        }

        result->Success(flutter::EncodableValue(
            static_cast<int64_t>(available_bytes.QuadPart)));
      });

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
  network_bridge_.reset();
  storage_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == NetworkBridge::kChangedMessage) {
    if (network_bridge_) {
      network_bridge_->OnChanged(wparam);
    }
    return 0;
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
