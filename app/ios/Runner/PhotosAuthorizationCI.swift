#if DEBUG && IMAGEHUB_PHOTOS_UI_CI && targetEnvironment(simulator)
import Foundation
import Photos
import UIKit

// Compiled only for the explicit owned Simulator CI build. No production hook.
@MainActor
final class PhotosAuthorizationCI: UIViewController {
  private static let mainBundleID = "io.imagehost.imagehost"
  private let ownedSimulatorID: String
  private let statusLabel = UILabel()
  private var phase = "ready"
  private var requestCount = 0
  private var callbackCount = 0
  private var callbackStatus = -1
  private var requestDispatched = false
  private var failureLatched = false
  private var callbackWithinDeadline = false
  private var deadline: TimeInterval?

  static func makeWindow(for scene: UIWindowScene) -> UIWindow? {
    let process = ProcessInfo.processInfo
    let environment = process.environment
    guard process.arguments.filter({ $0 == "--imagehub-ci-photos-authorize" }).count == 1,
          matches(environment["SIMULATOR_DEVICE_NAME"],
                  "^ImageHub-CI-[1-9][0-9]*-[1-9][0-9]*-[0-9a-f]{8}$"),
          let simulatorID = environment["SIMULATOR_UDID"],
          matches(simulatorID,
                  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"),
          UUID(uuidString: simulatorID) != nil,
          Bundle.main.bundleIdentifier == mainBundleID,
          hasUsageDescription("NSPhotoLibraryUsageDescription"),
          hasUsageDescription("NSPhotoLibraryAddUsageDescription") else {
      return nil
    }
    let controller = PhotosAuthorizationCI(ownedSimulatorID: simulatorID.lowercased())
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .normal + 1
    window.rootViewController = controller
    return window
  }

  private static func matches(_ value: String?, _ pattern: String) -> Bool {
    guard let value = value,
          let match = value.range(of: pattern, options: .regularExpression) else { return false }
    return match.lowerBound == value.startIndex && match.upperBound == value.endIndex
  }

  private static func hasUsageDescription(_ key: String) -> Bool {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
      return false
    }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private init(ownedSimulatorID: String) {
    self.ownedSimulatorID = ownedSimulatorID
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { return nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    statusLabel.text = "ImageHub Photos CI authorization"
    statusLabel.accessibilityIdentifier = "imagehub-ci-photos-status"
    statusLabel.isAccessibilityElement = true
    statusLabel.numberOfLines = 0
    let requestButton = UIButton(type: .system)
    requestButton.setTitle("Request Photos full access", for: .normal)
    requestButton.accessibilityIdentifier = "imagehub-ci-photos-request"
    requestButton.addTarget(self, action: #selector(requestAuthorization), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [statusLabel, requestButton])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
    ])
    let readWrite = PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue
    if PHPhotoLibrary.authorizationStatus(for: .addOnly) != .authorized ||
        (readWrite != 0 && readWrite != 3) {
      latchFailure()
    } else {
      publish()
    }
  }

  @objc private func requestAuthorization() {
    guard !failureLatched, phase == "ready", requestCount == 0,
          PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
      latchFailure()
      return
    }
    let initial = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard initial == .notDetermined || initial == .authorized else {
      latchFailure()
      return
    }
    requestCount = 1
    phase = "requesting"
    let requestDeadline = ProcessInfo.processInfo.systemUptime + 30
    deadline = requestDeadline
    publish()
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
      // Capture actual callback arrival before scheduling its MainActor publication.
      let arrived = ProcessInfo.processInfo.systemUptime
      let rawStatus = status.rawValue
      Task { @MainActor [weak self] in
        self?.receiveCallback(rawStatus, arrived: arrived)
      }
    }
    // This signal follows the real SDK call's return, never the pre-call snapshot.
    requestDispatched = true
    publish()
    let remaining = max(0, requestDeadline - ProcessInfo.processInfo.systemUptime)
    DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
      guard let self = self, self.phase == "requesting" else { return }
      self.latchFailure()
    }
  }

  private func receiveCallback(_ status: Int, arrived: TimeInterval) {
    callbackCount += 1
    callbackStatus = status
    guard !failureLatched, phase == "requesting", requestCount == 1,
          callbackCount == 1, requestDispatched,
          let deadline = deadline, arrived.isFinite, arrived <= deadline,
          ProcessInfo.processInfo.systemUptime <= deadline,
          status == PHAuthorizationStatus.authorized.rawValue,
          PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized,
          PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
      latchFailure()
      return
    }
    callbackWithinDeadline = true
    phase = "confirmed"
    publish()
  }

  private func latchFailure() {
    failureLatched = true
    callbackWithinDeadline = false
    phase = "failed"
    publish()
  }

  private func publish() {
    let snapshot: [String: Any] = [
      "formatVersion": 1,
      "phase": phase,
      "ownedSimulatorID": ownedSimulatorID,
      "mainBundleID": Self.mainBundleID,
      "mainProcessID": Int(ProcessInfo.processInfo.processIdentifier),
      "photoUsageDescriptionPresent": Self.hasUsageDescription("NSPhotoLibraryUsageDescription"),
      "photoAddUsageDescriptionPresent": Self.hasUsageDescription("NSPhotoLibraryAddUsageDescription"),
      "addOnlyStatus": PHPhotoLibrary.authorizationStatus(for: .addOnly).rawValue,
      "readWriteStatus": PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue,
      "requestCount": requestCount,
      "callbackCount": callbackCount,
      "callbackStatus": callbackStatus,
      "requestDispatched": requestDispatched,
      "failureLatched": failureLatched,
      "callbackWithinDeadline": callbackWithinDeadline,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
      // Serialization failure cannot expose a previously successful snapshot.
      failureLatched = true
      phase = "failed"
      statusLabel.accessibilityValue = ""
      return
    }
    statusLabel.accessibilityValue = text
  }
}
#endif
