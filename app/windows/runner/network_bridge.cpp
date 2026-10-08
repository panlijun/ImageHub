#include "network_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Networking.Connectivity.h>

#include <mutex>
#include <optional>
#include <utility>

namespace {

using flutter::EncodableValue;
using winrt::Windows::Networking::Connectivity::NetworkConnectivityLevel;
using winrt::Windows::Networking::Connectivity::NetworkInformation;

EncodableValue Snapshot(const char* status, const char* transport = nullptr) {
  flutter::EncodableList transports;
  if (transport != nullptr) {
    transports.emplace_back(transport);
  }
  return EncodableValue(flutter::EncodableMap{
      {EncodableValue("status"), EncodableValue(status)},
      {EncodableValue("transports"), EncodableValue(transports)},
  });
}

EncodableValue ReadSnapshot() {
  const auto profile = NetworkInformation::GetInternetConnectionProfile();
  if (!profile || profile.GetNetworkConnectivityLevel() ==
                      NetworkConnectivityLevel::None) {
    return Snapshot("offline");
  }
  // Connected is a local route observation, never a reachability guarantee.
  if (profile.IsWlanConnectionProfile()) {
    return Snapshot("connected", "wifi");
  }
  if (profile.IsWwanConnectionProfile()) {
    return Snapshot("connected", "cellular");
  }
  const auto adapter = profile.NetworkAdapter();
  if (adapter && adapter.IanaInterfaceType() == 6) {
    return Snapshot("connected", "ethernet");
  }
  return Snapshot("connected", "other");
}

// A callback can outlive unregistration. It owns this state, never Impl or the
// window object. Clearing the handle under this lock prevents post-destroy use.
struct CallbackState {
  std::mutex mutex;
  HWND window = nullptr;
  WPARAM generation = 0;
};

}  // namespace

class NetworkBridge::Impl {
 public:
  Impl(flutter::BinaryMessenger* messenger, HWND window)
      : window_(window), callback_state_(std::make_shared<CallbackState>()),
        method_channel_(messenger, "io.imagehost/network",
                        &flutter::StandardMethodCodec::GetInstance()),
        event_channel_(messenger, "io.imagehost/network_changes",
                       &flutter::StandardMethodCodec::GetInstance()) {
    method_channel_.SetMethodCallHandler(
        [](const flutter::MethodCall<EncodableValue>& call,
           std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
          if (call.method_name() != "read") {
            result->NotImplemented();
            return;
          }
          try {
            result->Success(ReadSnapshot());
          } catch (...) {
            result->Error("network_error", "Unable to read network type.");
          }
        });
    event_channel_.SetStreamHandler(
        std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
            [this](const EncodableValue*,
                   std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
                -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
              Stop();
              sink_ = std::move(sink);
              ++generation_;
              const WPARAM listener_generation = generation_;
              const auto state = callback_state_;
              {
                std::lock_guard<std::mutex> lock(state->mutex);
                state->window = window_;
                state->generation = generation_;
              }
              try {
                token_ = NetworkInformation::NetworkStatusChanged(
                    [state, listener_generation](
                        const winrt::Windows::Foundation::IInspectable&) {
                      std::lock_guard<std::mutex> lock(state->mutex);
                      if (state->window != nullptr &&
                          state->generation == listener_generation) {
                        // Always enqueue; querying and Flutter calls stay on UI.
                        PostMessageW(state->window, kChangedMessage,
                                     state->generation, 0);
                      }
                    });
                Publish();
                return nullptr;
              } catch (...) {
                Stop();
                return std::make_unique<
                    flutter::StreamHandlerError<EncodableValue>>(
                    "network_error", "Unable to observe network type.", nullptr);
              }
            },
            [this](const EncodableValue*)
                -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
              Stop();
              return nullptr;
            }));
  }

  ~Impl() {
    Stop();
    // Flutter channels do not unregister their handlers in their destructors.
    event_channel_.SetStreamHandler(nullptr);
    method_channel_.SetMethodCallHandler(nullptr);
  }

  void OnChanged(WPARAM generation) noexcept {
    if (sink_ && generation == generation_) {
      Publish();
    }
  }

 private:
  void Publish() noexcept {
    try {
      const auto value = ReadSnapshot();
      if (!last_ || !(*last_ == value)) {
        last_ = value;
        sink_->Success(value);
      }
    } catch (...) {
      // A failed query invalidates the previous observation immediately.
      last_ = Snapshot("unknown");
      sink_->Error("network_error", "Unable to read network type.");
      sink_->Success(*last_);
    }
  }

  void Stop() noexcept {
    {
      std::lock_guard<std::mutex> lock(callback_state_->mutex);
      callback_state_->window = nullptr;
    }
    if (token_) {
      try {
        NetworkInformation::NetworkStatusChanged(*token_);
      } catch (...) {
        // Even a failed removal leaves the callback inert through shared state.
      }
      token_.reset();
    }
    sink_.reset();
    last_.reset();
  }

  const HWND window_;
  WPARAM generation_ = 0;
  std::shared_ptr<CallbackState> callback_state_;
  std::optional<winrt::event_token> token_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> sink_;
  std::optional<EncodableValue> last_;
  flutter::MethodChannel<EncodableValue> method_channel_;
  flutter::EventChannel<EncodableValue> event_channel_;
};

NetworkBridge::NetworkBridge(flutter::BinaryMessenger* messenger, HWND window)
    : impl_(std::make_unique<Impl>(messenger, window)) {}

NetworkBridge::~NetworkBridge() = default;

void NetworkBridge::OnChanged(WPARAM generation) noexcept {
  impl_->OnChanged(generation);
}
