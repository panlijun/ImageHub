import CryptoKit
import Photos
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  @MainActor
  func testITApplePickerCancellationOwnsOnlyItsWindowAndWaitsForDismissal() throws {
    let engine = AppleFileEngine()
    var picker: UIDocumentPickerViewController?
    var dismissDone: (() -> Void)?
    var dismissCount = 0
    let bridge = IOSFileBridge(engine: engine, presenter: { controller, done in
      picker = controller
      done(true)
    }, dismisser: { _, done in
      dismissCount += 1
      dismissDone = done
    })
    let selectionId = "a1234567-89ab-4cde-8f01-23456789abcd"
    var picks = 0
    var cancels = 0
    bridge.pickBackup(selectionId: selectionId.uppercased()) { result in
      picks += 1
      switch result {
      case .success(let value):
        XCTAssertTrue(value.cancelled)
        XCTAssertTrue(value.resources.isEmpty)
      case .failure: XCTFail("Cancellation must complete as a cancelled selection.")
      }
    }
    let ownedPicker = try XCTUnwrap(picker)
    bridge.cancelSelection(selectionId: UUID().uuidString.lowercased()) { result in
      if case .failure = result { XCTFail("Unknown valid token cancellation must be harmless.") }
    }
    XCTAssertEqual(dismissCount, 0)
    bridge.cancelSelection(selectionId: selectionId) { _ in cancels += 1 }
    XCTAssertEqual(dismissCount, 1)
    XCTAssertEqual(picks, 0)
    XCTAssertEqual(cancels, 0)
    // Even a late provider URL cannot open a resource after cancellation.
    bridge.documentPicker(ownedPicker, didPickDocumentsAt: [URL(fileURLWithPath: "/unowned.zip")])
    let finish = try XCTUnwrap(dismissDone)
    finish()
    finish()
    bridge.documentPickerWasCancelled(ownedPicker)
    XCTAssertEqual(picks, 1)
    XCTAssertEqual(cancels, 1)
    bridge.pickBackup(selectionId: selectionId) { result in
      if case .success = result { XCTFail("A retired selection token cannot own a new window.") }
    }
    bridge.pickBackup(selectionId: selectionId.uppercased()) { result in
      if case .success = result { XCTFail("A retired token's case variant cannot own a new window.") }
    }
    XCTAssertEqual(dismissCount, 1)
    let newId = UUID().uuidString.lowercased()
    var newReturned = false
    bridge.pickBackup(selectionId: newId) { result in
      newReturned = true
      if case .success(let value) = result { XCTAssertTrue(value.cancelled) }
      else { XCTFail("Expected new window's own cancelled result.") }
    }
    let newPicker = try XCTUnwrap(picker)
    XCTAssertFalse(newPicker === ownedPicker)
    bridge.cancelSelection(selectionId: selectionId.uppercased()) { result in
      if case .failure = result { XCTFail("A retired token's late case-variant cancellation must be harmless.") }
    }
    bridge.documentPickerWasCancelled(ownedPicker)
    finish()
    XCTAssertEqual(dismissCount, 1)
    XCTAssertFalse(newReturned)
    bridge.cancelSelection(selectionId: newId) { _ in }
    XCTAssertEqual(dismissCount, 2)
    try XCTUnwrap(dismissDone)()
    XCTAssertTrue(newReturned)
    bridge.dispose()
  }

  func testUTApplePhotoIdentifierIsBoundedASCIIOpaqueSegment() {
    XCTAssertEqual(IOSFileBridge.photoURI("abc_DEF-012/L0/001"), "ph://asset/abc_DEF-012%2FL0%2F001")
    XCTAssertNotNil(IOSFileBridge.photoURI(String(repeating: "A", count: 256)))
    for invalid in ["", String(repeating: "A", count: 257), "opaque id", "image.jpg", "中文", "a\n"] {
      XCTAssertNil(IOSFileBridge.photoURI(invalid))
    }
  }

  @MainActor
  func testITApplePickerCancelDuringPresentationWaitsForBothTransitions() throws {
    var presentDone: ((Bool) -> Void)?
    var dismissDone: (() -> Void)?
    let bridge = IOSFileBridge(presenter: { _, done in presentDone = done },
                              dismisser: { _, done in dismissDone = done })
    let id = UUID().uuidString.lowercased()
    var returned = false
    var cancellationReturned = false
    bridge.pickDirectory(selectionId: id, operationIds: [UUID().uuidString.lowercased()]) { result in
      returned = true
      switch result {
      case .success(let destination):
        XCTAssertTrue(destination.cancelled)
        XCTAssertNil(destination.handle)
      case .failure: XCTFail("Expected a cancelled directory selection.")
      }
    }
    bridge.cancelSelection(selectionId: id) { _ in cancellationReturned = true }
    XCTAssertFalse(returned)
    XCTAssertFalse(cancellationReturned)
    XCTAssertNil(dismissDone)
    try XCTUnwrap(presentDone)(true)
    XCTAssertFalse(returned)
    XCTAssertFalse(cancellationReturned)
    try XCTUnwrap(dismissDone)()
    XCTAssertTrue(returned)
    XCTAssertTrue(cancellationReturned)
    bridge.dispose()
  }

  @MainActor
  func testITApplePickerInvalidTokensAndUnavailablePresentationUseSafeErrors() {
    var presents = 0
    let bridge = IOSFileBridge(presenter: { _, done in presents += 1; done(false) })
    bridge.pickBackup(selectionId: "not-a-uuid") { result in
      if case .failure(let error) = result {
        XCTAssertEqual((error as? PigeonError)?.code, "invalidInput")
      } else { XCTFail("Invalid selection token accepted.") }
    }
    let operation = UUID().uuidString.lowercased()
    bridge.pickDirectory(selectionId: UUID().uuidString.lowercased(), operationIds: [operation, operation]) { result in
      if case .success = result { XCTFail("Duplicate operation identifiers accepted.") }
    }
    XCTAssertEqual(presents, 0)
    bridge.pickBackup(selectionId: UUID().uuidString.lowercased()) { result in
      if case .failure(let error) = result {
        XCTAssertEqual((error as? PigeonError)?.code, "unavailable")
        XCTAssertNil((error as? PigeonError)?.details)
      } else { XCTFail("A missing scene cannot report a selected resource.") }
    }
    XCTAssertEqual(presents, 1)
    bridge.dispose()
  }

  @MainActor
  func testITApplePhotosRealAddOnlyCommitPreservesSourceAndRetiresStage() throws {
    guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
      if ProcessInfo.processInfo.environment["CI"] != nil {
        XCTFail("CI must grant photos-add to this owned simulator's application before this real Photos test.")
        return
      }
      throw XCTSkip("A real Photos add-only grant is required; no permission stub counts as native validation.")
    }
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent("imagehub-ios-photos-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let source = root.appendingPathComponent("source.png")
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2))
    let bytes = renderer.pngData { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
    }
    try bytes.write(to: source, options: .withoutOverwriting)
    let engine = AppleFileEngine(privateRoots: [root])
    let bridge = IOSFileBridge(engine: engine)
    let done = expectation(description: "Real Photos transaction and stage cleanup finished")
    var saved: AppleExportReply?
    var ended = false
    let request = AppleExportRequest(operationId: UUID().uuidString.lowercased(), sourcePath: source.path,
                                     displayName: "ImageHub-native-photos.png", mimeType: "image/png",
                                     sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                                     byteCount: Int64(bytes.count), kind: .photos)
    bridge.savePhoto(request: request) { result in
      ended = true
      switch result {
      case .success(let reply): saved = reply
      case .failure: XCTFail("Real Photos save failed with a safe native error.")
      }
      done.fulfill()
    }
    wait(for: [done], timeout: 60)
    // On a timeout, retain the owned root: cancellation is not proof that
    // Photos or engine IO stopped using its stage.
    guard ended else { bridge.dispose(); return }
    defer { bridge.dispose(); try? FileManager.default.removeItem(at: root) }
    let reply = try XCTUnwrap(saved)
    XCTAssertEqual(reply.code, .ok)
    XCTAssertFalse(reply.cleanupPending)
    XCTAssertTrue(reply.uri?.hasPrefix("ph://asset/") == true)
    XCTAssertFalse(reply.uri?.contains("/L0/") == true, "Photos identifier must be percent encoded.")
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root,
      includingPropertiesForKeys: [.isRegularFileKey], options: []))
    var regularFiles: [URL] = []
    for case let file as URL in enumerator {
      if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
        regularFiles.append(file)
      }
    }
    XCTAssertEqual(regularFiles.map(\.lastPathComponent), ["source.png"],
                   "Photos must retain immutable source bytes and retire its private stage after actual completion.")
  }

}
