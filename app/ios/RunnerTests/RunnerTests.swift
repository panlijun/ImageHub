import CryptoKit
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers
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

  @MainActor
  func testITApplePhotosPNGOriginalResourceMatchesSource() throws {
    try verifyPhotoFormat(.png, requiresSave: true)
  }

  @MainActor
  func testITApplePhotosJPEGOriginalResourceMatchesSource() throws {
    try verifyPhotoFormat(.jpeg, requiresSave: true)
  }

  @MainActor
  func testITApplePhotosGIFOriginalResourceOrSafeFailure() throws {
    try verifyPhotoFormat(.gif, requiresSave: false)
  }

  @MainActor
  func testITApplePhotosWebPOriginalResourceOrSafeFailure() throws {
    try verifyPhotoFormat(.webp, requiresSave: false)
  }

  @MainActor
  func testITApplePhotosBMPOriginalResourceOrSafeFailure() throws {
    try verifyPhotoFormat(.bmp, requiresSave: false)
  }

  @MainActor
  func testITApplePhotosPrecancelledOperationPreservesSourceWithoutSave() throws {
    try requireOwnedPhotosSimulator(readBack: false)
    let bytes = try photoFixture(.png)
    let root = try makePhotoRoot()
    let source = root.appendingPathComponent("source.png")
    try bytes.write(to: source, options: .withoutOverwriting)
    let bridge = IOSFileBridge(engine: AppleFileEngine(privateRoots: [root]))
    let request = photoRequest(source: source, bytes: bytes, format: .png)
    try bridge.cancelExport(operationId: request.operationId)
    var ended = false
    var cancelled = false
    defer {
      bridge.dispose()
      if ended && cancelled { try? FileManager.default.removeItem(at: root) }
    }
    let done = expectation(description: "Precancelled Photos preparation has actually finished")
    bridge.savePhoto(request: request) { result in
      ended = true
      if case .failure(let error) = result {
        XCTAssertEqual((error as? PigeonError)?.code, "cancelled")
        XCTAssertNil((error as? PigeonError)?.details)
        cancelled = (error as? PigeonError)?.code == "cancelled"
      } else { XCTFail("Precancelled preparation cannot report a Photos save.") }
      done.fulfill()
    }
    wait(for: [done], timeout: 60)
    guard ended && cancelled else { return }
    try assertSourceAndRetiredStage(root: root, source: source, bytes: bytes)
    reportPhoto(format: "PNG", result: "cancelled-before-Photos", bytes: bytes)
  }

  @MainActor
  func testITApplePhotosInvalidContentWaitsForFailureAndRetiresStage() throws {
    try requireOwnedPhotosSimulator(readBack: false)
    let bytes = Data("ImageHub synthetic invalid image; not PNG bytes.".utf8)
    XCTAssertNil(CGImageSourceCreateWithData(bytes as CFData, nil))
    let root = try makePhotoRoot()
    let source = root.appendingPathComponent("source.png")
    try bytes.write(to: source, options: .withoutOverwriting)
    let bridge = IOSFileBridge(engine: AppleFileEngine(privateRoots: [root]))
    var cleanupSafe = false
    defer {
      bridge.dispose()
      if cleanupSafe { try? FileManager.default.removeItem(at: root) }
    }
    let done = expectation(description: "Real Photos rejects invalid content and ends stage IO")
    var saved: Result<AppleExportReply, Error>?
    bridge.savePhoto(request: photoRequest(source: source, bytes: bytes, format: .png)) { result in
      saved = result
      done.fulfill()
    }
    wait(for: [done], timeout: 60)
    guard let result = saved else { return } // A deadline does not prove IO ended.
    let reply = try result.get()
    cleanupSafe = !reply.cleanupPending
    XCTAssertEqual(reply.code, .unconfirmed)
    XCTAssertFalse(reply.cleanupPending)
    XCTAssertNil(reply.uri)
    XCTAssertNil(reply.displayName)
    try assertSourceAndRetiredStage(root: root, source: source, bytes: bytes)
    guard reply.code == .unconfirmed, !reply.cleanupPending,
          reply.uri == nil, reply.displayName == nil else { throw PhotoVerificationFailure.resource }
    reportPhoto(format: "invalid-PNG", result: "safe-unconfirmed", bytes: bytes)
  }

  private enum PhotoFixtureFormat: Equatable {
    case png, jpeg, gif, webp, bmp
    var name: String {
      switch self {
      case .png: return "PNG"
      case .jpeg: return "JPEG"
      case .gif: return "GIF"
      case .webp: return "WebP"
      case .bmp: return "BMP"
      }
    }
    var ext: String { self == .jpeg ? "jpg" : name.lowercased() }
    var mime: String { "image/\(self == .jpeg ? "jpeg" : ext)" }
    var type: String {
      switch self {
      case .png: return UTType.png.identifier
      case .jpeg: return UTType.jpeg.identifier
      case .gif: return UTType.gif.identifier
      case .webp: return "org.webmproject.webp"
      case .bmp: return UTType.bmp.identifier
      }
    }
  }

  /// No picker, all-library query, deletion, network fetch or permission prompt.
  /// Only the helper-created CI simulator can receive temporary read access.
  private func requireOwnedPhotosSimulator(readBack: Bool) throws {
    #if targetEnvironment(simulator)
    let environment = ProcessInfo.processInfo.environment
    let name = environment["SIMULATOR_DEVICE_NAME"] ?? ""
    guard name.range(of: "^ImageHub-CI-[1-9][0-9]*-[1-9][0-9]*-[0-9a-f]{8}$",
                     options: .regularExpression) != nil,
          let identifier = environment["SIMULATOR_UDID"], UUID(uuidString: identifier) != nil else {
      throw XCTSkip("Photos resource verification runs only on a newly owned ImageHub CI simulator.")
    }
    XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .addOnly), .authorized,
                   "CI must grant photos-add to its confirmed owned simulator application.")
    if readBack {
      XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .readWrite), .authorized,
                     "CI must temporarily grant photos for exact synthetic-resource readback.")
    }
    guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized,
          !readBack || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
      throw PhotoVerificationFailure.authorization
    }
    #else
    throw XCTSkip("These tests must never read a physical device's photo library.")
    #endif
  }

  private enum PhotoVerificationFailure: Error {
    case authorization, resource, unfinishedRead
  }

  @MainActor
  private func photoFixture(_ format: PhotoFixtureFormat) throws -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 2),
      format: UIGraphicsImageRendererFormat.default())
    let image = renderer.image { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
      UIColor.blue.setFill()
      context.fill(CGRect(x: 1, y: 0, width: 1, height: 2))
    }
    let bytes: Data
    switch format {
    case .png: bytes = try XCTUnwrap(image.pngData())
    case .jpeg: bytes = try XCTUnwrap(image.jpegData(compressionQuality: 0.85))
    case .gif:
      let output = NSMutableData()
      let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output as CFMutableData,
        UTType.gif.identifier as CFString, 2, nil))
      let properties = [kCGImagePropertyGIFDictionary as String:
        [kCGImagePropertyGIFDelayTime as String: 0.1]] as CFDictionary
      let pixels = try XCTUnwrap(image.cgImage)
      let secondImage = renderer.image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
      }
      CGImageDestinationAddImage(destination, pixels, properties)
      CGImageDestinationAddImage(destination, try XCTUnwrap(secondImage.cgImage), properties)
      guard CGImageDestinationFinalize(destination) else { throw PhotoVerificationFailure.resource }
      bytes = output as Data
    case .webp:
      // A synthetic 1x1 fixture generated and decoded with the locked image
      // package. ImageIO below independently checks the declared format here.
      bytes = try XCTUnwrap(Data(base64Encoded: "UklGRhwAAABXRUJQVlA4TBAAAAAvAAAAAAfQqZa0sv+BiIgA"))
    case .bmp:
      // A 3x2 24-bit BI_RGB image: each bottom-up row has nine bytes + padding.
      // The fixed header and payload are generated here, not a user image.
      var output = Data([0x42, 0x4d])
      func le(_ value: UInt32, count: Int = 4) {
        for shift in 0..<count { output.append(UInt8((value >> (shift * 8)) & 0xff)) }
      }
      le(78); le(0); le(54); le(40); le(3); le(2)
      le(1, count: 2); le(24, count: 2)
      le(0); le(24); le(2835); le(2835); le(0); le(0)
      for _ in 0..<2 { output.append(contentsOf: [0, 0, 255, 255, 0, 0, 0, 0, 255, 0, 0, 0]) }
      bytes = output
    }
    XCTAssertGreaterThan(bytes.count, 0)
    XCTAssertLessThanOrEqual(bytes.count, 1024 * 1024)
    let decoder = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
    let type = try XCTUnwrap(CGImageSourceGetType(decoder))
    XCTAssertEqual(type as String, format.type, "The declared format must match the actual fixture.")
    guard type as String == format.type else { throw PhotoVerificationFailure.resource }
    let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
    XCTAssertGreaterThan(decoded.width, 0)
    XCTAssertGreaterThan(decoded.height, 0)
    if format == .gif { XCTAssertEqual(CGImageSourceGetCount(decoder), 2) }
    return bytes
  }

  private func makePhotoRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent("imagehub-ios-photos-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
  }

  private func photoRequest(source: URL, bytes: Data, format: PhotoFixtureFormat) -> AppleExportRequest {
    AppleExportRequest(operationId: UUID().uuidString.lowercased(), sourcePath: source.path,
      displayName: "ImageHub-native-\(UUID().uuidString).\(format.ext)", mimeType: format.mime,
      sha256: photoDigest(bytes), byteCount: Int64(bytes.count), kind: .photos)
  }

  private func photoDigest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  private func assertSourceAndRetiredStage(root: URL, source: URL, bytes: Data) throws {
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root,
      includingPropertiesForKeys: [.isRegularFileKey], options: []))
    var files: [String] = []
    for case let file as URL in enumerator {
      if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
        files.append(file.path)
      }
    }
    XCTAssertEqual(files.sorted(), [source.path], "Actual Photos completion must retire its closed private stage.")
  }

  @MainActor
  private func verifyPhotoFormat(_ format: PhotoFixtureFormat, requiresSave: Bool) throws {
    try requireOwnedPhotosSimulator(readBack: true)
    let bytes = try photoFixture(format)
    let root = try makePhotoRoot()
    let source = root.appendingPathComponent("source.\(format.ext)")
    try bytes.write(to: source, options: .withoutOverwriting)
    let bridge = IOSFileBridge(engine: AppleFileEngine(privateRoots: [root]))
    var cleanupSafe = false
    defer {
      bridge.dispose()
      if cleanupSafe { try? FileManager.default.removeItem(at: root) }
    }
    let request = photoRequest(source: source, bytes: bytes, format: format)
    let done = expectation(description: "Real \(format.name) Photos save and stage retirement")
    var result: Result<AppleExportReply, Error>?
    bridge.savePhoto(request: request) { value in result = value; done.fulfill() }
    wait(for: [done], timeout: 60)
    guard let saved = result else { return } // Retain root until actual IO ends.
    let reply = try saved.get()
    cleanupSafe = !reply.cleanupPending
    XCTAssertFalse(reply.cleanupPending)
    try assertSourceAndRetiredStage(root: root, source: source, bytes: bytes)
    guard reply.code == .ok else {
      XCTAssertFalse(requiresSave, "\(format.name) must save and independently match original resource bytes.")
      XCTAssertTrue(reply.code == .unsupported || reply.code == .unconfirmed,
                    "Only an explicit safe unsupported/unconfirmed result is a valid format outcome.")
      XCTAssertNil(reply.uri)
      XCTAssertNil(reply.displayName)
      guard reply.code == .unsupported || reply.code == .unconfirmed else {
        throw PhotoVerificationFailure.resource
      }
      reportPhoto(format: format.name,
                  result: reply.code == .unsupported ? "safe-unsupported" : "safe-unconfirmed", bytes: bytes)
      return
    }
    XCTAssertEqual(reply.displayName, request.displayName)
    let uri = try XCTUnwrap(reply.uri)
    let prefix = "ph://asset/"
    guard uri.hasPrefix(prefix),
          let identifier = String(uri.dropFirst(prefix.count)).removingPercentEncoding,
          IOSFileBridge.photoURI(identifier) == uri else {
      XCTFail("A successful Photos reply needs a canonical opaque identifier.")
      throw PhotoVerificationFailure.resource
    }
    // This is the sole Photos query. Never enumerate any collection or all
    // assets, infer an identity from timestamps, or look at another image.
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
    XCTAssertEqual(assets.count, 1)
    let asset = try XCTUnwrap(assets.firstObject)
    XCTAssertEqual(asset.localIdentifier, identifier)
    let resources = PHAssetResource.assetResources(for: asset).filter {
      $0.type == .photo && $0.originalFilename == request.displayName
    }
    XCTAssertEqual(resources.count, 1, "Read the original uploaded resource, never a converted rendition.")
    let resource = try XCTUnwrap(resources.first)
    let stream = PhotoResourceDigest(limit: bytes.count)
    let readDone = expectation(description: "Independent original Photos resource stream actually ended")
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = false
    PHAssetResourceManager.default().requestData(for: resource, options: options,
      dataReceivedHandler: { stream.receive($0) }, completionHandler: { error in
        stream.complete(error: error)
        readDone.fulfill()
      })
    cleanupSafe = false
    wait(for: [readDone], timeout: 60)
    let read = stream.snapshot()
    guard read.ended else { throw PhotoVerificationFailure.unfinishedRead }
    cleanupSafe = !reply.cleanupPending
    XCTAssertTrue(read.succeeded, "Original Photos resource read must complete without error or excess bytes.")
    XCTAssertEqual(read.count, bytes.count)
    XCTAssertEqual(read.digest, request.sha256, "Converted bytes do not count as an original-byte save.")
    reportPhoto(format: format.name,
      result: read.succeeded && read.count == bytes.count && read.digest == request.sha256
        ? "saved-original-bytes-verified" : "saved-readback-mismatch", bytes: bytes)
    try assertSourceAndRetiredStage(root: root, source: source, bytes: bytes)
    // Test assets are retired with the owned simulator. No Photos deletion API
    // is called, even after an assertion fails or resource read times out.
  }

  private func reportPhoto(format: String, result: String, bytes: Data) {
    let record: [String: Any] = ["format": format, "result": result,
      "byteCount": bytes.count, "sha256": photoDigest(bytes)]
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
      print("IMAGEHUB_PHOTOS_RESULT \(text)")
    }
  }

  /// Incremental SHA-256 uses at most a 64 KiB slice, rejects bytes beyond the
  /// fixture bound and retains no image buffers. Completion, not cancellation
  /// or a timeout, is the proof that the PhotoKit read has ended.
  private final class PhotoResourceDigest {
    private let lock = NSLock()
    private let limit: Int
    private var hash = SHA256()
    private var count = 0
    private var valid = true
    private var ended = false
    init(limit: Int) { self.limit = limit }
    func receive(_ bytes: Data) {
      lock.lock(); defer { lock.unlock() }
      guard !ended, valid, bytes.count <= limit - count else { valid = false; return }
      var offset = bytes.startIndex
      while offset < bytes.endIndex {
        let end = min(offset + 65536, bytes.endIndex)
        hash.update(data: bytes.subdata(in: offset..<end))
        offset = end
      }
      count += bytes.count
    }
    func complete(error: Error?) {
      lock.lock(); defer { lock.unlock() }
      valid = valid && error == nil
      ended = true
    }
    func snapshot() -> (ended: Bool, succeeded: Bool, count: Int, digest: String) {
      lock.lock(); defer { lock.unlock() }
      return (ended, ended && valid, count, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
  }
}
