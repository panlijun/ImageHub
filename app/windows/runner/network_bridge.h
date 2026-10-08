#ifndef RUNNER_NETWORK_BRIDGE_H_
#define RUNNER_NETWORK_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// Passive default-path observation. Native callbacks never access Flutter.
class NetworkBridge {
 public:
  static constexpr UINT kChangedMessage = WM_APP + 41;

  NetworkBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~NetworkBridge();
  NetworkBridge(const NetworkBridge&) = delete;
  NetworkBridge& operator=(const NetworkBridge&) = delete;

  void OnChanged(WPARAM generation) noexcept;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_NETWORK_BRIDGE_H_
