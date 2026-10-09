import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import XCTest
@testable import ImageHub

final class RunnerTests: XCTestCase {
  private let firstId = "11111111-1111-4111-8111-111111111111"
  private let secondId = "22222222-2222-4222-8222-222222222222"
  private let selectedURL = URL(fileURLWithPath: "/external/selected-backup.zip")

  func testNativeBackupPanelConfiguration() {
    onMain {
      let presenter = NativeMacBackupPanel()
      XCTAssertEqual(presenter.panel.allowedContentTypes, [.zip])
      XCTAssertFalse(presenter.panel.allowsOtherFileTypes)
      XCTAssertFalse(presenter.panel.allowsMultipleSelection)
      XCTAssertTrue(presenter.panel.canChooseFiles)
      XCTAssertFalse(presenter.panel.canChooseDirectories)
      XCTAssertFalse(presenter.panel.resolvesAliases)
      XCTAssertFalse(presenter.panel.treatsFilePackagesAsDirectories)
    }
  }

  func testInvalidSelectionIdsNeverPresentPanel() {
    onMain {
      let panel = TestBackupPanel()
      let bridge = MacFileBridge(window: nil, panelFactory: { panel })
      defer { bridge.dispose() }
      for id in ["", "../backup.zip", "11111111-1111-1111-8111-111111111111", firstId + "\n"] {
        var result: Result<AppleSelection, Error>?
        bridge.pickBackup(selectionId: id) { result = $0 }
        assertFailure(result, code: "invalidInput")
      }
      XCTAssertEqual(panel.callbacks.count, 0)
    }
  }

  func testReentryCannotReplaceOwnedSelection() {
    onMain {
      let panel = TestBackupPanel()
      var registrations = 0
      let bridge = MacFileBridge(window: nil, panelFactory: { panel }, registerBackup: { _ in
        registrations += 1
        return self.resourceSelection()
      })
      defer { bridge.dispose() }
      var first: Result<AppleSelection, Error>?
      var second: Result<AppleSelection, Error>?
      bridge.pickBackup(selectionId: firstId) { first = $0 }
      bridge.pickBackup(selectionId: secondId) { second = $0 }
      assertFailure(second, code: "unavailable")
      XCTAssertEqual(panel.callbacks.count, 1)
      XCTAssertNil(first)
      panel.respond(.OK, url: selectedURL)
      XCTAssertEqual(try? first?.get(), resourceSelection())
      XCTAssertEqual(registrations, 1)
    }
  }

  func testCancelWaitsForOwnPanelAndNeverRegistersLateURL() {
    onMain {
      let panel = TestBackupPanel()
      var registrations = 0
      let bridge = MacFileBridge(window: nil, panelFactory: { panel }, registerBackup: { _ in
        registrations += 1
        return self.resourceSelection()
      })
      defer { bridge.dispose() }
      var selectionReplies = 0
      var cancellationReplies = 0
      var selection: AppleSelection?
      bridge.pickBackup(selectionId: firstId) {
        selectionReplies += 1
        selection = try? $0.get()
      }
      bridge.cancelSelection(selectionId: secondId) { self.assertSuccessfulCancellation($0) }
      XCTAssertEqual(panel.cancelCalls, 0)
      bridge.cancelSelection(selectionId: firstId) { _ in cancellationReplies += 1 }
      bridge.cancelSelection(selectionId: firstId) { _ in cancellationReplies += 1 }
      XCTAssertEqual(panel.cancelCalls, 1)
      XCTAssertEqual(selectionReplies, 0)
      XCTAssertEqual(cancellationReplies, 0)
      panel.respond(.OK, url: selectedURL)
      XCTAssertEqual(selection, AppleSelection(cancelled: true, resources: []))
      XCTAssertEqual(selectionReplies, 1)
      XCTAssertEqual(cancellationReplies, 2)
      XCTAssertEqual(registrations, 0)
      panel.respond(.cancel)
      XCTAssertEqual(selectionReplies, 1)
      XCTAssertEqual(cancellationReplies, 2)
    }
  }

  func testOldCallbackAndOldCancelDoNotFinishNewSelection() {
    onMain {
      let panel = TestBackupPanel()
      var registrations = 0
      let bridge = MacFileBridge(window: nil, panelFactory: { panel }, registerBackup: { _ in
        registrations += 1
        return self.resourceSelection()
      })
      defer { bridge.dispose() }
      var firstReplies = 0
      var secondReplies = 0
      bridge.pickBackup(selectionId: firstId) { _ in firstReplies += 1 }
      panel.respond(.OK, url: selectedURL, index: 0)
      bridge.pickBackup(selectionId: secondId) { _ in secondReplies += 1 }
      panel.respond(.OK, url: selectedURL, index: 0)
      bridge.cancelSelection(selectionId: firstId) { self.assertSuccessfulCancellation($0) }
      XCTAssertEqual(panel.cancelCalls, 0)
      XCTAssertEqual(firstReplies, 1)
      XCTAssertEqual(secondReplies, 0)
      XCTAssertEqual(registrations, 1)
      panel.respond(.cancel, index: 1)
      XCTAssertEqual(secondReplies, 1)
    }
  }

  func testDisposeCancelsOwnedPanelAndPreservesItsActualCompletion() {
    onMain {
      let panel = TestBackupPanel()
      var registrations = 0
      var selectionReplies = 0
      let bridge = MacFileBridge(window: nil, panelFactory: { panel }, registerBackup: { _ in
        registrations += 1
        return self.resourceSelection()
      })
      bridge.pickBackup(selectionId: firstId) {
        selectionReplies += 1
        XCTAssertEqual(try? $0.get(), AppleSelection(cancelled: true, resources: []))
      }
      bridge.dispose()
      bridge.dispose()
      XCTAssertEqual(panel.cancelCalls, 1)
      XCTAssertEqual(selectionReplies, 0)
      var rejected: Result<AppleSelection, Error>?
      bridge.pickBackup(selectionId: secondId) { rejected = $0 }
      assertFailure(rejected, code: "unavailable")
      panel.respond(.OK, url: selectedURL)
      XCTAssertEqual(selectionReplies, 1)
      XCTAssertEqual(registrations, 0)
    }
  }

  func testRetiredSelectionIdCannotBeReusedOrCancelNewSelection() {
    onMain {
      let panel = TestBackupPanel()
      let bridge = MacFileBridge(window: nil, panelFactory: { panel })
      defer { bridge.dispose() }
      let retiredId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      bridge.pickBackup(selectionId: retiredId) { XCTAssertTrue((try? $0.get().cancelled) == true) }
      panel.respond(.cancel, index: 0)

      for reusedId in [retiredId, retiredId.uppercased()] {
        var rejected: Result<AppleSelection, Error>?
        bridge.pickBackup(selectionId: reusedId) { rejected = $0 }
        assertFailure(rejected, code: "unavailable")
      }
      XCTAssertEqual(panel.callbacks.count, 1)

      var newReplies = 0
      bridge.pickBackup(selectionId: secondId) { _ in newReplies += 1 }
      bridge.cancelSelection(selectionId: retiredId) { self.assertSuccessfulCancellation($0) }
      bridge.cancelSelection(selectionId: retiredId.uppercased()) { self.assertSuccessfulCancellation($0) }
      panel.respond(.cancel, index: 0)
      XCTAssertEqual(panel.cancelCalls, 0)
      XCTAssertEqual(newReplies, 0)
      panel.respond(.cancel, index: 1)
      XCTAssertEqual(newReplies, 1)
    }
  }

  func testUnknownRegistrationErrorNeverExposesItsDescription() {
    onMain {
      let panel = TestBackupPanel()
      let bridge = MacFileBridge(window: nil, panelFactory: { panel }, registerBackup: { _ in
        throw NSError(domain: "private-source", code: 19, userInfo: [NSLocalizedDescriptionKey: "secret /external/path"])
      })
      defer { bridge.dispose() }
      var result: Result<AppleSelection, Error>?
      bridge.pickBackup(selectionId: firstId) { result = $0 }
      panel.respond(.OK, url: selectedURL)
      assertFailure(result, code: "unavailable")
      if case .failure(let error)? = result, let pigeon = error as? PigeonError {
        XCTAssertNil(pigeon.details)
        XCTAssertEqual(pigeon.message, "Unable to complete the file operation.")
      }
    }
  }

  private func resourceSelection() -> AppleSelection {
    AppleSelection(cancelled: false, resources: [ApplePickedResource(handle: secondId, displayName: "backup.zip")])
  }

  private func assertSuccessfulCancellation(_ result: Result<Void, Error>, file: StaticString = #filePath, line: UInt = #line) {
    if case .failure = result {
      XCTFail("A valid unknown or retired cancellation must be harmless.", file: file, line: line)
    }
  }

  private func assertFailure<T>(_ result: Result<T, Error>?, code: String, file: StaticString = #filePath, line: UInt = #line) {
    guard case .failure(let error)? = result else {
      XCTFail("Expected a fixed file failure.", file: file, line: line)
      return
    }
    XCTAssertEqual((error as? PigeonError)?.code, code, file: file, line: line)
  }

  private func onMain(_ body: () -> Void) {
    if Thread.isMainThread { body() } else { DispatchQueue.main.sync(execute: body) }
  }
}

private final class TestBackupPanel: MacBackupPanel {
  var callbacks: [(NSApplication.ModalResponse, URL?) -> Void] = []
  var cancelCalls = 0

  func present(for window: NSWindow?, completion: @escaping (NSApplication.ModalResponse, URL?) -> Void) {
    callbacks.append(completion)
  }

  func cancel() { cancelCalls += 1 }

  func respond(_ response: NSApplication.ModalResponse, url: URL? = nil, index: Int = 0) {
    callbacks[index](response, url)
  }
}
