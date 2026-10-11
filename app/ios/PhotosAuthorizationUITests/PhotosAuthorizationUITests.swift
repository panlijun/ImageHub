import CoreFoundation
import Darwin
import Foundation
import XCTest

@MainActor
final class PhotosAuthorizationUITests: XCTestCase {
  private static let mainBundleID = "io.imagehost.imagehost"
  private static let testBundleID = "io.imagehost.imagehost.PhotosAuthorizationUITests"
  private static let snapshotKeys: Set<String> = [
    "formatVersion", "phase", "ownedSimulatorID", "mainBundleID", "mainProcessID",
    "photoUsageDescriptionPresent", "photoAddUsageDescriptionPresent", "addOnlyStatus",
    "readWriteStatus", "requestCount", "callbackCount", "callbackStatus",
    "requestDispatched", "failureLatched", "callbackWithinDeadline",
  ]

  private struct AuthorizationFailure: Error {
    let code: String
  }

  func testOwnedPhotosAuthorizationFromExpectedSystemAlert() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: Self.mainBundleID)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    do {
      let environment = ProcessInfo.processInfo.environment
      let simulatorID = environment["SIMULATOR_UDID"] ?? ""
      try require(matches(environment["SIMULATOR_DEVICE_NAME"] ?? "",
                          "^ImageHub-CI-[1-9][0-9]*-[1-9][0-9]*-[0-9a-f]{8}$"),
                  "owned-simulator-name-invalid")
      try require(matches(simulatorID,
                          "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") &&
                    UUID(uuidString: simulatorID) != nil,
                  "owned-simulator-id-invalid")
      try require(Bundle(for: PhotosAuthorizationUITests.self).bundleIdentifier == Self.testBundleID,
                  "ui-test-bundle-id-invalid")
      app.launchArguments = [
        "--imagehub-ci-photos-authorize", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      ]
      app.launch()
      let status = app.staticTexts["imagehub-ci-photos-status"]
      try require(status.waitForExistence(timeout: 15), "ready-status-missing")
      let ready = try readSnapshot(status)
      try validateIdentity(ready, simulatorID: simulatorID.lowercased())
      try require(try string(ready, "phase") == "ready", "initial-phase-not-ready")
      try require(try integer(ready, "addOnlyStatus") == 3, "initial-add-only-not-authorized")
      let initialReadWrite = try integer(ready, "readWriteStatus")
      try require(initialReadWrite == 0 || initialReadWrite == 3, "initial-read-write-not-permitted")
      try require(try integer(ready, "requestCount") == 0 && integer(ready, "callbackCount") == 0 &&
                    integer(ready, "callbackStatus") == -1 && !boolean(ready, "requestDispatched") &&
                    !boolean(ready, "failureLatched") && !boolean(ready, "callbackWithinDeadline"),
                  "ready-state-invalid")
      let expectedAlertNeeded = initialReadWrite == 0
      try emit(ready, alertNeeded: expectedAlertNeeded, alertHandled: false)
      let request = app.buttons["imagehub-ci-photos-request"]
      try require(request.exists && request.isHittable, "request-button-unavailable")
      request.tap()
      var expectedAlertHandled = false
      if expectedAlertNeeded {
        let alert = springboard.alerts.element(boundBy: 0)
        try require(alert.waitForExistence(timeout: 15), "expected-system-alert-missing")
        try require(springboard.alerts.count == 1, "system-alert-count-invalid")
        let identity = alert.staticTexts.matching(
          NSPredicate(format: "label CONTAINS %@", "ImageHub")
        )
        let photosIdentity = alert.staticTexts.matching(
          NSPredicate(format: "label CONTAINS[c] %@", "Photo")
        )
        logBoundedButtons(alert)
        try require(identity.count > 0 && photosIdentity.count > 0,
                    "expected-photos-alert-identity-missing")
        let fullAccess = alert.buttons.matching(
          NSPredicate(format: "label IN %@", ["Allow Full Access", "Allow Access to All Photos"] as NSArray)
        )
        try require(fullAccess.count == 1, "expected-full-access-button-missing-or-ambiguous")
        let fullAccessButton = fullAccess.element(boundBy: 0)
        try require(fullAccessButton.isHittable, "expected-full-access-button-not-hittable")
        fullAccessButton.tap()
        expectedAlertHandled = true
      }
      // The host owns the monotonic 30-second failure latch. This only observes it.
      let terminal = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value CONTAINS %@ OR value CONTAINS %@",
                               "\"phase\":\"confirmed\"", "\"phase\":\"failed\""),
        object: status
      )
      try require(XCTWaiter.wait(for: [terminal], timeout: 35) == .completed,
                  "terminal-authorization-status-missing")
      let confirmed = try readSnapshot(status)
      try validateIdentity(confirmed, simulatorID: simulatorID.lowercased())
      try require(try integer(confirmed, "mainProcessID") == integer(ready, "mainProcessID"),
                  "main-process-changed-within-ui-stage")
      try require(try string(confirmed, "phase") == "confirmed" &&
                    integer(confirmed, "addOnlyStatus") == 3 && integer(confirmed, "readWriteStatus") == 3 &&
                    integer(confirmed, "requestCount") == 1 && integer(confirmed, "callbackCount") == 1 &&
                    integer(confirmed, "callbackStatus") == 3 && boolean(confirmed, "requestDispatched") &&
                    !boolean(confirmed, "failureLatched") && boolean(confirmed, "callbackWithinDeadline"),
                  "authorization-not-confirmed-by-real-callback-and-sdk")
      try require(expectedAlertHandled == expectedAlertNeeded, "system-alert-handling-mismatch")
      try emit(confirmed, alertNeeded: expectedAlertNeeded, alertHandled: expectedAlertHandled)
    } catch let failure as AuthorizationFailure {
      attachFailureScreenshot()
      XCTFail(failure.code)
    } catch {
      attachFailureScreenshot()
      XCTFail("ui-authorization-unclassified-failure")
    }
  }

  private func require(_ condition: Bool, _ code: String) throws {
    if !condition { throw AuthorizationFailure(code: code) }
  }

  private func matches(_ value: String, _ pattern: String) -> Bool {
    guard let match = value.range(of: pattern, options: .regularExpression) else { return false }
    return match.lowerBound == value.startIndex && match.upperBound == value.endIndex
  }

  private func readSnapshot(_ element: XCUIElement) throws -> [String: Any] {
    guard let text = element.value as? String, text.utf8.count <= 4096,
          let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let snapshot = object as? [String: Any], Set(snapshot.keys) == Self.snapshotKeys else {
      throw AuthorizationFailure(code: "status-json-schema-invalid")
    }
    for key in ["formatVersion", "mainProcessID", "addOnlyStatus", "readWriteStatus",
                "requestCount", "callbackCount", "callbackStatus"] {
      _ = try integer(snapshot, key)
    }
    for key in ["photoUsageDescriptionPresent", "photoAddUsageDescriptionPresent", "requestDispatched",
                "failureLatched", "callbackWithinDeadline"] {
      _ = try boolean(snapshot, key)
    }
    for key in ["phase", "ownedSimulatorID", "mainBundleID"] { _ = try string(snapshot, key) }
    try require(try integer(snapshot, "formatVersion") == 1 && integer(snapshot, "mainProcessID") > 0 &&
                  (0...4).contains(integer(snapshot, "addOnlyStatus")) &&
                  (0...4).contains(integer(snapshot, "readWriteStatus")) &&
                  integer(snapshot, "requestCount") >= 0 && integer(snapshot, "callbackCount") >= 0 &&
                  (-1...4).contains(integer(snapshot, "callbackStatus")) &&
                  ["ready", "requesting", "confirmed", "failed"].contains(string(snapshot, "phase")),
                "status-json-values-invalid")
    return snapshot
  }

  private func integer(_ snapshot: [String: Any], _ key: String) throws -> Int {
    guard let value = snapshot[key] as? NSNumber,
          CFGetTypeID(value) != CFBooleanGetTypeID(),
          ["c", "s", "i", "l", "q"].contains(String(cString: value.objCType)),
          let integer = Int(exactly: value.int64Value) else {
      throw AuthorizationFailure(code: "status-integer-type-invalid")
    }
    return integer
  }

  private func boolean(_ snapshot: [String: Any], _ key: String) throws -> Bool {
    guard let value = snapshot[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
      throw AuthorizationFailure(code: "status-boolean-type-invalid")
    }
    return value.boolValue
  }

  private func string(_ snapshot: [String: Any], _ key: String) throws -> String {
    guard let value = snapshot[key] as? String else {
      throw AuthorizationFailure(code: "status-string-type-invalid")
    }
    return value
  }

  private func validateIdentity(_ snapshot: [String: Any], simulatorID: String) throws {
    try require(try string(snapshot, "ownedSimulatorID") == simulatorID &&
                  string(snapshot, "mainBundleID") == Self.mainBundleID &&
                  boolean(snapshot, "photoUsageDescriptionPresent") &&
                  boolean(snapshot, "photoAddUsageDescriptionPresent"),
                "host-identity-or-usage-description-invalid")
  }

  private func emit(_ snapshot: [String: Any], alertNeeded: Bool, alertHandled: Bool) throws {
    var evidence = snapshot
    evidence["testBundleID"] = Self.testBundleID
    evidence["testProcessID"] = Int(ProcessInfo.processInfo.processIdentifier)
    evidence["expectedAlertNeeded"] = alertNeeded
    evidence["expectedAlertHandled"] = alertHandled
    let data = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
    guard let text = String(data: data, encoding: .utf8), text.utf8.count <= 4096 else {
      throw AuthorizationFailure(code: "validated-evidence-serialization-failed")
    }
    print("IMAGEHUB_PHOTOS_UI_AUTHORIZATION \(text)")
    fflush(stdout)
  }

  private func logBoundedButtons(_ alert: XCUIElement) {
    let labels = alert.buttons.allElementsBoundByIndex.prefix(8).map { button in
      button.label.unicodeScalars.prefix(96).map {
        (0x20...0x7e).contains($0.value) ? String($0) : "?"
      }.joined()
    }
    guard let data = try? JSONSerialization.data(withJSONObject: labels),
          let text = String(data: data, encoding: .utf8) else { return }
    print("IMAGEHUB_PHOTOS_UI_ALERT_BUTTONS \(text)")
    fflush(stdout)
  }

  private func attachFailureScreenshot() {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "ImageHub-Photos-authorization-failure"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
