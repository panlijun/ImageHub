import XCTest
import Foundation
import CryptoKit
import Darwin
#if os(macOS)
@testable import ImageHub
#else
@testable import Runner
#endif

final class AppleFileEngineTests: XCTestCase {
  private var root: URL!
  private var engine: AppleFileEngine!

  override func setUpWithError() throws {
    // /var and /tmp can be system aliases. Resolve the system root before
    // creating our own namespace, while keeping every managed child link-free.
    root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent("imagehub-apple-file-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    engine = AppleFileEngine(privateRoots: [root])
  }

  override func tearDownWithError() throws {
    // A queued close acts as a drain after dispose's queued scope retirement.
    // Tests await every actual read/export/Photos completion before deleting.
    if let engine = engine {
      engine.dispose()
      let drained = expectation(description: "engine queue drained")
      engine.closeResource(handle: UUID().uuidString.lowercased()) { _ in drained.fulfill() }
      guard XCTWaiter.wait(for: [drained], timeout: 10) == .completed else {
        XCTFail("Actual native IO did not drain; preserving the test-owned directory.")
        return
      }
    }
    if let root = root { try FileManager.default.removeItem(at: root) }
    engine = nil; root = nil
  }

  private func write(_ name: String, _ data: Data) throws -> URL {
    let file = root.appendingPathComponent(name)
    try data.write(to: file)
    return file
  }
  private func sha(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
  private func request(_ file: URL, _ bytes: Data, id: String = UUID().uuidString.lowercased(),
                       kind: AppleDestinationKind = .directory, handle: String? = nil,
                       name: String = "saved.bin") -> AppleExportRequest {
    AppleExportRequest(operationId: id, sourcePath: file.path, displayName: name,
      mimeType: "application/octet-stream", sha256: sha(bytes), byteCount: Int64(bytes.count),
      kind: kind, destinationHandle: handle)
  }
  private func awaitReply<T>(_ start: (@escaping (Result<T, Error>) -> Void) -> Void,
                             file: StaticString = #filePath, line: UInt = #line) throws -> T {
    let done = expectation(description: "native actual IO completion")
    var result: Result<T, Error>?
    start { value in
      XCTAssertTrue(Thread.isMainThread, file: file, line: line)
      result = value; done.fulfill()
    }
    wait(for: [done], timeout: 20)
    return try XCTUnwrap(result, file: file, line: line).get()
  }
  private func directory(_ name: String = "destination") throws -> URL {
    let url = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }
  private func register(_ directory: URL, _ ids: [String]) throws -> String {
    try XCTUnwrap(engine.registerDirectory(directory, operationIds: ids, requireSecurityScope: true).handle)
  }
  private func closeDirectory(_ handle: String) throws {
    let _: Void = try awaitReply { engine.closeDestination(handle: handle, completion: $0) }
  }
  private func assertCleanupPending(_ start: (@escaping (Result<Void, Error>) -> Void) -> Void,
                                    file: StaticString = #filePath, line: UInt = #line) {
    do {
      let _: Void = try awaitReply(start, file: file, line: line)
      XCTFail("Uncertain retirement unexpectedly succeeded.", file: file, line: line)
    } catch {
      XCTAssertEqual((error as? AppleFileFailure)?.code, .cleanupPending, file: file, line: line)
    }
  }

  func testUT036DirectoryExportPreservesExistingBytesAndUsesOneOperationOnce() throws {
    let bytes = Data((0..<140000).map { UInt8($0 % 251) })
    let source = try write("source.bin", bytes)
    let target = try directory()
    let old = target.appendingPathComponent("saved.bin")
    let oldBytes = Data("keep existing external bytes".utf8)
    try oldBytes.write(to: old)
    let id = UUID().uuidString.lowercased()
    let handle = try register(target, [id])
    let input = request(source, bytes, id: id, handle: handle)
    let reply: AppleExportReply = try awaitReply { engine.exportFile(request: input, completion: $0) }
    XCTAssertEqual(reply.code, .ok); XCTAssertFalse(reply.cleanupPending)
    XCTAssertEqual(reply.displayName, "saved (1).bin")
    XCTAssertEqual(try Data(contentsOf: old), oldBytes)
    let exported = try XCTUnwrap(URL(string: XCTUnwrap(reply.uri)))
    XCTAssertEqual(try Data(contentsOf: exported), bytes)
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    let repeated: AppleExportReply = try awaitReply { engine.exportFile(request: input, completion: $0) }
    XCTAssertEqual(repeated.code, .invalidInput)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path).count, 2)
    try closeDirectory(handle)
  }

  func testUT036DigestAndChangedSourceRejectBeforeCreatingDestination() throws {
    let bytes = Data("frozen source".utf8)
    let source = try write("source.bin", bytes)
    let target = try directory()
    let ids = [UUID().uuidString.lowercased(), UUID().uuidString.lowercased()]
    let handle = try register(target, ids)
    var badDigest = request(source, bytes, id: ids[0], handle: handle)
    badDigest.sha256 = String(repeating: "0", count: 64)
    let mismatch: AppleExportReply = try awaitReply { engine.exportFile(request: badDigest, completion: $0) }
    XCTAssertEqual(mismatch.code, .inputChanged)
    let frozen = request(source, bytes, id: ids[1], handle: handle)
    try Data("source changed".utf8).write(to: source)
    let changed: AppleExportReply = try awaitReply { engine.exportFile(request: frozen, completion: $0) }
    XCTAssertEqual(changed.code, .inputChanged)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
    try closeDirectory(handle)
  }

  func testUT036SourceReadIsBoundedSequentialAndClosedAfterActualReads() throws {
    let bytes = Data((0..<150001).map { UInt8($0 % 241) })
    let source = try write("backup.zip", bytes)
    let selection = try engine.registerBackup(source, requireSecurityScope: true)
    let handle = try XCTUnwrap(selection.resources.first?.handle)
    var read = Data()
    var sizes: [Int] = []
    while true {
      let reply: AppleReadReply = try awaitReply { engine.readResource(handle: handle, completion: $0) }
      XCTAssertEqual(reply.code, .ok)
      XCTAssertLessThanOrEqual(reply.bytes.data.count, 65536)
      sizes.append(reply.bytes.data.count); read.append(reply.bytes.data)
      if reply.eof { break }
    }
    XCTAssertEqual(sizes, [65536, 65536, 18929]); XCTAssertEqual(read, bytes)
    let eof: AppleReadReply = try awaitReply { engine.readResource(handle: handle, completion: $0) }
    XCTAssertTrue(eof.eof); XCTAssertEqual(eof.bytes.data.count, 0)
    let _: Void = try awaitReply { engine.closeResource(handle: handle, completion: $0) }
    let stale: AppleReadReply = try awaitReply { engine.readResource(handle: handle, completion: $0) }
    XCTAssertEqual(stale.code, .invalidInput)
    XCTAssertEqual(try Data(contentsOf: source), bytes)
  }

  func testUT036SourceIdentityChangeInvalidatesRemainingRead() throws {
    let bytes = Data(repeating: 17, count: 70000)
    let source = try write("backup.zip", bytes)
    let handle = try XCTUnwrap(engine.registerBackup(source, requireSecurityScope: true).resources.first?.handle)
    let first: AppleReadReply = try awaitReply { engine.readResource(handle: handle, completion: $0) }
    XCTAssertEqual(first.bytes.data.count, 65536)
    // Replace the selected pathname with a distinct inode, preserving length.
    try FileManager.default.removeItem(at: source)
    try Data(repeating: 19, count: bytes.count).write(to: source)
    let changed: AppleReadReply = try awaitReply { engine.readResource(handle: handle, completion: $0) }
    XCTAssertEqual(changed.code, .inputChanged); XCTAssertTrue(changed.bytes.data.isEmpty)
    let _: Void = try awaitReply { engine.closeResource(handle: handle, completion: $0) }
  }

  func testUT036RegistrationDefersMissingSourceIOUntilFirstRead() throws {
    let missing = root.appendingPathComponent("not-created.zip")
    let handle = try XCTUnwrap(engine.registerBackup(missing, requireSecurityScope: true).resources.first?.handle)
    let result: AppleReadReply = try awaitReply { engine.readResource(handle: handle, completion: $0) }
    XCTAssertEqual(result.code, .sourceMissing)
    XCTAssertTrue(result.bytes.data.isEmpty)
    let _: Void = try awaitReply { engine.closeResource(handle: handle, completion: $0) }
  }

  func testUT036SourceUnknownCloseRetainsHandleAndScopeAfterDispose() throws {
    let bytes = Data(repeating: 9, count: 70000)
    let source = try write("backup.zip", bytes)
    var injected = false
    engine.dispose()
    engine = AppleFileEngine(privateRoots: [root], closeDescriptor: { descriptor in
      var identity = stat()
      let regular = fstat(descriptor, &identity) == 0 &&
        (identity.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
      // This is a result-reporting fault injection after a REAL close. No real
      // descriptor or worker is left open; it is not a hardware-fault claim.
      let actual = Darwin.close(descriptor)
      if regular && !injected && actual == 0 { injected = true; return -1 }
      return actual
    })
    let handle = try XCTUnwrap(engine.registerBackup(source, requireSecurityScope: true).resources.first?.handle)
    let read: AppleReadReply = try awaitReply { engine.readResource(handle: handle, completion: $0) }
    XCTAssertTrue(injected); XCTAssertEqual(read.code, .unconfirmed)
    XCTAssertTrue(read.bytes.data.isEmpty)
    assertCleanupPending { engine.closeResource(handle: handle, completion: $0) }
    assertCleanupPending { engine.closeResource(handle: handle, completion: $0) }
    engine.dispose()
    assertCleanupPending { engine.closeResource(handle: handle, completion: $0) }
    XCTAssertEqual(try Data(contentsOf: source), bytes)
  }

  func testUT036DestinationUnknownCloseRetainsHandleAndScopeAfterDispose() throws {
    let bytes = Data(repeating: 6, count: 150000)
    let source = try write("source.bin", bytes)
    let target = try directory()
    var selected = stat()
    XCTAssertEqual(lstat(target.path, &selected), 0)
    let selectedInode = selected.st_ino
    let selectedDevice = selected.st_dev
    var injected = false
    engine.dispose()
    engine = AppleFileEngine(privateRoots: [root], closeDescriptor: { descriptor in
      var identity = stat()
      let selectedDirectory = fstat(descriptor, &identity) == 0 &&
        (identity.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) &&
        identity.st_ino == selectedInode && identity.st_dev == selectedDevice
      let actual = Darwin.close(descriptor)
      if selectedDirectory && !injected && actual == 0 { injected = true; return -1 }
      return actual
    })
    let id = UUID().uuidString.lowercased()
    let handle = try register(target, [id])
    let exported: AppleExportReply = try awaitReply {
      engine.exportFile(request: request(source, bytes, id: id, handle: handle), completion: $0)
    }
    XCTAssertTrue(injected); XCTAssertEqual(exported.code, .unconfirmed)
    XCTAssertTrue(exported.cleanupPending); XCTAssertNil(exported.uri)
    assertCleanupPending { engine.closeDestination(handle: handle, completion: $0) }
    assertCleanupPending { engine.closeDestination(handle: handle, completion: $0) }
    engine.dispose()
    assertCleanupPending { engine.closeDestination(handle: handle, completion: $0) }
    XCTAssertEqual(try Data(contentsOf: source), bytes)
  }

  func testUT036ReadQueuedBeforeCloseCompletesBeforeScopeRetirement() throws {
    let bytes = Data(repeating: 3, count: 70000)
    let source = try write("backup.zip", bytes)
    let handle = try XCTUnwrap(engine.registerBackup(source, requireSecurityScope: true).resources.first?.handle)
    let read = expectation(description: "accepted read")
    let close = expectation(description: "actual close")
    var order: [String] = []
    engine.readResource(handle: handle) { result in
      if case let .success(value) = result { XCTAssertEqual(value.bytes.data.count, 65536) }
      else { XCTFail("read failed") }
      order.append("read"); read.fulfill()
    }
    engine.closeResource(handle: handle) { result in
      if case .failure = result { XCTFail("close failed") }
      order.append("close"); close.fulfill()
    }
    wait(for: [read, close], timeout: 20, enforceOrder: true)
    XCTAssertEqual(order, ["read", "close"])
  }

  func testUT036CancellationClosesAcceptedWorkAndDoesNotCreateAFile() throws {
    let bytes = Data(repeating: 23, count: 150000)
    let source = try write("source.bin", bytes)
    let target = try directory()
    let id = UUID().uuidString.lowercased()
    let handle = try register(target, [id])
    engine.cancelExport(operationId: id)
    let reply: AppleExportReply = try awaitReply {
      engine.exportFile(request: request(source, bytes, id: id, handle: handle), completion: $0)
    }
    XCTAssertEqual(reply.code, .cancelled); XCTAssertFalse(reply.cleanupPending)
    try closeDirectory(handle)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
    XCTAssertEqual(try Data(contentsOf: source), bytes)
  }

  func testUT036DirectoryHandleRejectsOtherIdentityAndUnregisteredOperation() throws {
    let bytes = Data("bytes".utf8)
    let source = try write("source.bin", bytes)
    let target = try directory()
    let id = UUID().uuidString.lowercased()
    let warmupID = UUID().uuidString.lowercased()
    let handle = try register(target, [warmupID, id])
    let unauthorized: AppleExportReply = try awaitReply {
      engine.exportFile(request: request(source, bytes, handle: handle), completion: $0)
    }
    XCTAssertEqual(unauthorized.code, .invalidInput)
    let warmup: AppleExportReply = try awaitReply {
      engine.exportFile(request: request(source, bytes, id: warmupID, handle: handle), completion: $0)
    }
    XCTAssertEqual(warmup.code, .ok)
    let moved = root.appendingPathComponent("old-destination")
    try FileManager.default.moveItem(at: target, to: moved)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    let changed: AppleExportReply = try awaitReply {
      engine.exportFile(request: request(source, bytes, id: id, handle: handle), completion: $0)
    }
    XCTAssertEqual(changed.code, .inputChanged)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: moved.path), ["saved.bin"])
    try closeDirectory(handle)
  }

  func testUT036RejectsSymlinkSourcesAncestorsAndDestination() throws {
    let bytes = Data("source bytes".utf8)
    let source = try write("source.bin", bytes)
    let link = root.appendingPathComponent("linked.bin")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
    let linkedResource = try XCTUnwrap(engine.registerBackup(link, requireSecurityScope: true).resources.first?.handle)
    let linkedRead: AppleReadReply = try awaitReply { engine.readResource(handle: linkedResource, completion: $0) }
    XCTAssertEqual(linkedRead.code, .invalidInput)
    let _: Void = try awaitReply { engine.closeResource(handle: linkedResource, completion: $0) }
    let target = try directory()
    let linkedDirectory = root.appendingPathComponent("linked-directory")
    try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: target)
    let linkedID = UUID().uuidString.lowercased()
    let linkedHandle = try register(linkedDirectory, [linkedID])
    let linkedExport: AppleExportReply = try awaitReply {
      engine.exportFile(request: request(source, bytes, id: linkedID, handle: linkedHandle), completion: $0)
    }
    XCTAssertEqual(linkedExport.code, .invalidInput)
    try closeDirectory(linkedHandle)
    let id = UUID().uuidString.lowercased()
    let handle = try register(target, [id])
    let refused: AppleExportReply = try awaitReply {
      engine.exportFile(request: request(link, bytes, id: id, handle: handle), completion: $0)
    }
    XCTAssertEqual(refused.code, .invalidInput)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
    try closeDirectory(handle)
  }

  func testUT036StrictUUIDsAndPrivateSourceBoundary() throws {
    let target = try directory()
    XCTAssertThrowsError(try engine.registerDirectory(target,
      operationIds: ["00000000-0000-0000-0000-000000000000"], requireSecurityScope: true))
    let id = UUID().uuidString.lowercased()
    XCTAssertThrowsError(try engine.registerDirectory(target, operationIds: [id, id], requireSecurityScope: true))
    let bytes = Data("private bytes".utf8)
    let source = try write("source.bin", bytes)
    let handle = try register(target, [id])
    var escape = request(source, bytes, id: id, handle: handle)
    escape.sourcePath = root.path + "/../outside.bin"
    let refused: AppleExportReply = try awaitReply { engine.exportFile(request: escape, completion: $0) }
    XCTAssertEqual(refused.code, .invalidInput)
    try closeDirectory(handle)
  }

  func testUT036PhotosStageKeepsSourceAndLateCancellationPreservesCommit() throws {
    let bytes = Data((0..<145000).map { UInt8($0 % 239) })
    let source = try write("source.gif", bytes)
    let id = UUID().uuidString.lowercased()
    let stage: ApplePhotoStage = try awaitReply {
      engine.preparePhoto(request: request(source, bytes, id: id, kind: .photos, name: "original.gif"), completion: $0)
    }
    XCTAssertNotEqual(stage.file, source)
    XCTAssertEqual(stage.file.pathExtension, "gif")
    XCTAssertEqual(try Data(contentsOf: stage.file), bytes)
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    engine.cancelExport(operationId: id)
    let reply: AppleExportReply = try awaitReply {
      engine.finishPhoto(stage, code: .ok, uri: "photos://confirmed-test", completion: $0)
    }
    XCTAssertEqual(reply.code, .ok); XCTAssertFalse(reply.cleanupPending)
    XCTAssertEqual(reply.uri, "photos://confirmed-test")
    XCTAssertFalse(FileManager.default.fileExists(atPath: stage.file.path))
    XCTAssertEqual(try Data(contentsOf: source), bytes)
  }

  func testUT036PhotosStageTamperingRetainsBytesAndSuccessEvidence() throws {
    let bytes = Data("original photo bytes".utf8)
    let source = try write("source.png", bytes)
    let stage: ApplePhotoStage = try awaitReply {
      engine.preparePhoto(request: request(source, bytes, kind: .photos, name: "original.png"), completion: $0)
    }
    let changed = Data(repeating: 42, count: bytes.count)
    try changed.write(to: stage.file)
    let reply: AppleExportReply = try awaitReply {
      engine.finishPhoto(stage, code: .ok, uri: "photos://confirmed-test", completion: $0)
    }
    XCTAssertEqual(reply.code, .ok); XCTAssertTrue(reply.cleanupPending)
    XCTAssertEqual(reply.uri, "photos://confirmed-test")
    XCTAssertEqual(try Data(contentsOf: stage.file), changed)
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    // Restore our test-owned bytes and explicitly complete cleanup before the
    // test's namespace is removed; no active Photos request exists in this test.
    try bytes.write(to: stage.file)
    let cleaned: AppleExportReply = try awaitReply {
      engine.finishPhoto(stage, code: .ok, uri: "photos://confirmed-test", completion: $0)
    }
    XCTAssertFalse(cleaned.cleanupPending)
  }

  func testUT036PhotosPrecommitCancellationCleansClosedStageOnly() throws {
    let bytes = Data(repeating: 11, count: 140000)
    let source = try write("source.png", bytes)
    let id = UUID().uuidString.lowercased()
    let stage: ApplePhotoStage = try awaitReply {
      engine.preparePhoto(request: request(source, bytes, id: id, kind: .photos, name: "original.png"), completion: $0)
    }
    engine.cancelExport(operationId: id)
    // Represents the UI's precommit rejection: no Photos request was begun.
    let reply: AppleExportReply = try awaitReply {
      engine.finishPhoto(stage, code: .cancelled, uri: nil, completion: $0)
    }
    XCTAssertEqual(reply.code, .cancelled); XCTAssertFalse(reply.cleanupPending)
    XCTAssertFalse(FileManager.default.fileExists(atPath: stage.file.path))
    XCTAssertEqual(try Data(contentsOf: source), bytes)
  }
}
