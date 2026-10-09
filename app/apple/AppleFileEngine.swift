import Foundation
import CryptoKit
import Darwin
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

struct AppleFileFailure: Error, LocalizedError {
  let code: AppleIoCode
  var errorDescription: String? { "Apple file operation could not be confirmed." }
}

// A stage is an engine-owned, closed byte copy. Photos must retain it until its
// actual completion handler has run; cancellation alone does not end that work.
final class ApplePhotoStage {
  let file: URL
  let operationId: String
  let displayName: String
  fileprivate let owner: UUID
  fileprivate let identity: AppleFileIdentity
  fileprivate let digest: String
  fileprivate let count: Int64
  fileprivate init(file: URL, operationId: String, displayName: String,
                   owner: UUID, identity: AppleFileIdentity, digest: String, count: Int64) {
    self.file = file; self.operationId = operationId; self.displayName = displayName
    self.owner = owner; self.identity = identity; self.digest = digest; self.count = count
  }
}

fileprivate struct AppleFileIdentity: Equatable {
  let device: dev_t
  let inode: ino_t
  let size: Int64
  let modifiedSeconds: Int64
  let modifiedNanos: Int64
  let changedSeconds: Int64
  let changedNanos: Int64
  init(_ value: stat) {
    device = value.st_dev; inode = value.st_ino; size = Int64(value.st_size)
    modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
    modifiedNanos = Int64(value.st_mtimespec.tv_nsec)
    changedSeconds = Int64(value.st_ctimespec.tv_sec)
    changedNanos = Int64(value.st_ctimespec.tv_nsec)
  }
  func sameObject(_ other: AppleFileIdentity) -> Bool {
    device == other.device && inode == other.inode
  }
}

final class AppleFileEngine {
  private final class Resource {
    let url: URL
    let scoped: Bool
    var identity: AppleFileIdentity?
    var offset: Int64 = 0
    var failed = false
    var retirementUncertain = false
    init(_ url: URL, _ scoped: Bool) {
      self.url = url; self.scoped = scoped
    }
  }
  private final class Destination {
    let url: URL
    let scoped: Bool
    var identity: AppleFileIdentity?
    var retirementUncertain = false
    let operations: Set<String>
    init(url: URL, scoped: Bool, operations: Set<String>) {
      self.url = url; self.scoped = scoped; self.operations = operations
    }
  }
  private struct OwnedFile {
    let url: URL
    let identity: AppleFileIdentity
    let digest: String
    let count: Int64
    let closed: Bool
  }
  private let io = DispatchQueue(label: "imagehost.apple.files.io")
  private let lock = NSLock()
  private let owner = UUID()
  private let roots: [(original: URL, canonical: URL)]
  private let systemAliases: [(alias: String, canonical: String)]
  private let closeDescriptor: (Int32) -> Int32
  private var resources: [String: Resource] = [:]
  private var destinations: [String: Destination] = [:]
  private var stages: [String: ApplePhotoStage] = [:]
  // These sets are deliberately not reset after completion: an operation ID is
  // a one-use authority and may not create a second external file.
  private var started: Set<String> = []
  private var cancelled: Set<String> = []
  private var stopping = false
  private let chunkSize = 64 * 1024
  private let maxHandles = 256
  private let maxOperations = 10000

  init(privateRoots: [URL]? = nil, closeDescriptor: ((Int32) -> Int32)? = nil) {
    self.closeDescriptor = closeDescriptor ?? { Darwin.close($0) }
    let manager = FileManager.default
    let defaults = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      + manager.urls(for: .cachesDirectory, in: .userDomainMask) + [manager.temporaryDirectory]
    roots = (privateRoots ?? defaults).map {
      ($0.standardizedFileURL, $0.standardizedFileURL.resolvingSymlinksInPath())
    }
    systemAliases = ["/var", "/tmp"].map {
      ($0, URL(fileURLWithPath: $0).resolvingSymlinksInPath().path)
    }
  }

  func registerBackup(_ url: URL, requireSecurityScope: Bool) throws -> AppleSelection {
    try requireRunning()
    let safe = try checkedURL(url)
    let scoped = try beginScope(url, requireSecurityScope)
    do {
      return try withState {
        guard !stopping, resources.count < maxHandles else { throw failure(.unavailable) }
        guard !resources.values.contains(where: { (try? checkedURL($0.url)) == safe }) else { throw failure(.invalidInput) }
        let handle = UUID().uuidString.lowercased()
        // Scope release must use the same original URL that acquired it.
        // Identity is frozen only on the first accepted read, after Dart has
        // checked cancellation. Registration never opens or coordinates data.
        resources[handle] = Resource(url, scoped)
        return AppleSelection(cancelled: false, resources: [
          ApplePickedResource(handle: handle, displayName: safe.lastPathComponent)
        ])
      }
    } catch {
      if scoped { url.stopAccessingSecurityScopedResource() }
      throw safeError(error)
    }
  }

  func readResource(handle: String, completion: @escaping (Result<AppleReadReply, Error>) -> Void) {
    io.async {
      let result: Result<AppleReadReply, Error>
      do {
        try self.requireRunning()
        guard self.validUUID(handle), let resource = self.withState({ self.resources[handle] }), !resource.failed else {
          throw self.failure(.invalidInput)
        }
        do {
          let url = try self.checkedURL(resource.url)
          try self.checkCloud(url)
          let data = try self.coordinatedRead(url) { coordinated -> Data in
            let fd = try self.openFile(coordinated)
            return try self.withClosed(fd) {
              let current = try self.fileIdentity(fd)
              if resource.identity == nil { resource.identity = current }
              guard let identity = resource.identity, current == identity,
                    resource.offset <= identity.size else { throw self.failure(.inputChanged) }
              guard lseek(fd, off_t(resource.offset), SEEK_SET) == off_t(resource.offset) else {
                throw self.failure(.storage)
              }
              let remaining = identity.size - resource.offset
              let data = try self.readChunk(fd, limit: Int(min(Int64(self.chunkSize), remaining)))
              guard !data.isEmpty || remaining == 0,
                    try self.fileIdentity(fd) == identity,
                    try self.pathIdentity(coordinated) == identity else {
                throw self.failure(.inputChanged)
              }
              return data
            }
          }
          resource.offset += Int64(data.count)
          result = .success(AppleReadReply(code: .ok,
            bytes: FlutterStandardTypedData(bytes: data), eof: resource.offset == resource.identity?.size))
        } catch {
          resource.failed = true
          if self.code(error) == .unconfirmed { resource.retirementUncertain = true }
          throw error
        }
      } catch {
        result = .success(AppleReadReply(code: self.code(error),
          bytes: FlutterStandardTypedData(bytes: Data()), eof: false))
      }
      self.deliver(result, completion)
    }
  }

  func closeResource(handle: String, completion: @escaping (Result<Void, Error>) -> Void) {
    io.async {
      guard self.validUUID(handle), let resource = self.withState({ self.resources[handle] }) else {
        self.deliver(.failure(self.failure(.invalidInput)), completion); return
      }
      guard !resource.retirementUncertain else {
        self.deliver(.failure(self.failure(.cleanupPending)), completion); return
      }
      _ = self.withState { self.resources.removeValue(forKey: handle) }
      if resource.scoped { resource.url.stopAccessingSecurityScopedResource() }
      self.deliver(.success(()), completion)
    }
  }

  func registerDirectory(_ url: URL, operationIds: [String], requireSecurityScope: Bool) throws -> AppleDestination {
    try requireRunning()
    guard !operationIds.isEmpty, operationIds.count <= 1000,
          Set(operationIds).count == operationIds.count, operationIds.allSatisfy(validUUID) else {
      throw failure(.invalidInput)
    }
    _ = try checkedURL(url)
    let scoped = try beginScope(url, requireSecurityScope)
    do {
      return try withState {
        guard !stopping, destinations.count < maxHandles else { throw failure(.unavailable) }
        guard destinations.values.allSatisfy({ $0.operations.isDisjoint(with: operationIds) }),
              started.isDisjoint(with: operationIds) else { throw failure(.invalidInput) }
        let handle = UUID().uuidString.lowercased()
        destinations[handle] = Destination(url: url, scoped: scoped, operations: Set(operationIds))
        return AppleDestination(cancelled: false, handle: handle)
      }
    } catch {
      if scoped { url.stopAccessingSecurityScopedResource() }
      throw safeError(error)
    }
  }

  func closeDestination(handle: String, completion: @escaping (Result<Void, Error>) -> Void) {
    io.async {
      guard self.validUUID(handle), let destination = self.withState({ self.destinations[handle] }) else {
        self.deliver(.failure(self.failure(.invalidInput)), completion); return
      }
      guard !destination.retirementUncertain else {
        self.deliver(.failure(self.failure(.cleanupPending)), completion); return
      }
      _ = self.withState { self.destinations.removeValue(forKey: handle) }
      if destination.scoped { destination.url.stopAccessingSecurityScopedResource() }
      self.deliver(.success(()), completion)
    }
  }

  func cancelExport(operationId: String) {
    guard validUUID(operationId) else { return }
    lock.lock(); defer { lock.unlock() }
    if cancelled.count < maxOperations || started.contains(operationId) { cancelled.insert(operationId) }
    else { stopping = true } // Bound the ledger without silently losing a stop request.
  }

  func isCancelled(operationId: String) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return stopping || cancelled.contains(operationId)
  }

  func exportFile(request: AppleExportRequest, completion: @escaping (Result<AppleExportReply, Error>) -> Void) {
    io.async {
      do {
        guard request.kind == .directory, let handle = request.destinationHandle,
              self.validUUID(handle), let destination = self.withState({ self.destinations[handle] }),
              destination.operations.contains(request.operationId), !destination.retirementUncertain else {
          throw self.failure(.invalidInput)
        }
        let source = try self.validateRequest(request)
        try self.beginOperation(request.operationId)
        let reply = try self.coordinatedWrite(try self.checkedURL(destination.url)) { directory in
          let directoryFD = try self.openDirectory(directory)
          return try self.withClosed(directoryFD) {
            let current = try self.directoryIdentity(directoryFD)
            if destination.identity == nil { destination.identity = current }
            guard let identity = destination.identity, current.sameObject(identity) else {
              throw self.failure(.inputChanged)
            }
            return try self.copy(request, source: source, directory: directory,
                                 directoryFD: directoryFD)
          }
        }
        if reply.code == .unconfirmed {
          destination.retirementUncertain = true
          self.deliver(.success(self.reply(.unconfirmed, pending: true)), completion)
        } else { self.deliver(.success(reply), completion) }
      } catch {
        if self.code(error) == .unconfirmed, let handle = request.destinationHandle,
           let destination = self.withState({ self.destinations[handle] }) {
          destination.retirementUncertain = true
        }
        self.deliver(.success(self.reply(self.code(error), pending: self.code(error) == .unconfirmed)), completion)
      }
    }
  }

  func preparePhoto(request: AppleExportRequest, completion: @escaping (Result<ApplePhotoStage, Error>) -> Void) {
    io.async {
      var prepared: ApplePhotoStage?
      do {
        guard request.kind == .photos, request.destinationHandle == nil else { throw self.failure(.invalidInput) }
        let stageExtension = try self.photoExtension(request)
        let source = try self.validateRequest(request)
        try self.beginOperation(request.operationId)
        guard let root = self.roots.last?.canonical else { throw self.failure(.unavailable) }
        let directory = root.appendingPathComponent("imagehost_apple_photo_staging_v1", isDirectory: true)
        // Only this engine owns newly created stage filenames. Existing directory
        // contents are never enumerated, adopted, or recursively cleaned.
        let rootFD = try self.openDirectory(root)
        var stageDirectoryFD: Int32 = -1
        let directoryFD: Int32
        do {
          directoryFD = try self.withClosed(rootFD) {
            if mkdirat(rootFD, directory.lastPathComponent, 0o700) != 0 && errno != EEXIST {
              throw self.failure(.storage)
            }
            stageDirectoryFD = openat(rootFD, directory.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard stageDirectoryFD >= 0 else { throw self.failure(.storage) }
            return stageDirectoryFD
          }
        } catch {
          if stageDirectoryFD >= 0 && self.closeFD(stageDirectoryFD) != 0 { throw self.failure(.unconfirmed) }
          throw error
        }
        let stageRequest = AppleExportRequest(operationId: request.operationId, sourcePath: request.sourcePath,
          displayName: "\(self.owner.uuidString)-\(UUID().uuidString).\(stageExtension)",
          mimeType: request.mimeType, sha256: request.sha256, byteCount: request.byteCount, kind: .photos)
        let reply = try self.withClosed(directoryFD) {
          try self.copy(stageRequest, source: source, directory: directory, directoryFD: directoryFD) { file, identity in
            let stage = ApplePhotoStage(file: file, operationId: request.operationId, displayName: request.displayName,
              owner: self.owner, identity: identity, digest: request.sha256.lowercased(), count: request.byteCount)
            prepared = stage
            self.stages[request.operationId] = stage
          }
        }
        guard reply.code == .ok, let stage = prepared else {
          throw self.failure(reply.code)
        }
        self.deliver(.success(stage), completion)
      } catch {
        if let stage = prepared {
          let owned = OwnedFile(url: stage.file, identity: stage.identity, digest: stage.digest,
                                count: stage.count, closed: true)
          if self.removeOwned(owned) { self.stages.removeValue(forKey: stage.operationId) }
          else { self.deliver(.failure(self.failure(.cleanupPending)), completion); return }
        }
        self.deliver(.failure(self.safeError(error)), completion)
      }
    }
  }

  func finishPhoto(_ stage: ApplePhotoStage, code: AppleIoCode, uri: String?,
                   completion: @escaping (Result<AppleExportReply, Error>) -> Void) {
    io.async {
      guard stage.owner == self.owner, self.stages[stage.operationId] === stage else {
        self.deliver(.failure(self.failure(.invalidInput)), completion); return
      }
      let owned = OwnedFile(url: stage.file, identity: stage.identity, digest: stage.digest,
                            count: stage.count, closed: true)
      let clean = self.removeOwned(owned)
      if clean { self.stages.removeValue(forKey: stage.operationId) }
      // The caller passes the actual Photos result. A confirmed commit remains
      // confirmed even if cancellation arrived or private cleanup failed later.
      let finalCode = code == .ok ? AppleIoCode.ok : (clean ? code : AppleIoCode.unconfirmed)
      self.deliver(.success(AppleExportReply(code: finalCode, cleanupPending: !clean,
        uri: code == .ok ? uri : nil, displayName: code == .ok ? stage.displayName : nil)), completion)
    }
  }

  func dispose() {
    lock.lock(); stopping = true; lock.unlock()
    io.async {
      let retired = self.withState { () -> ([Resource], [Destination]) in
        let items = (self.resources.values.filter { !$0.retirementUncertain },
                     self.destinations.values.filter { !$0.retirementUncertain })
        self.resources = self.resources.filter { $0.value.retirementUncertain }
        self.destinations = self.destinations.filter { $0.value.retirementUncertain }
        return items
      }
      for resource in retired.0 where resource.scoped { resource.url.stopAccessingSecurityScopedResource() }
      for destination in retired.1 where destination.scoped { destination.url.stopAccessingSecurityScopedResource() }
      // Photos stages are intentionally retained for their actual completion.
    }
  }

  private func copy(_ request: AppleExportRequest, source: URL, directory: URL,
                    directoryFD: Int32, confirmed: ((URL, AppleFileIdentity) -> Void)? = nil) throws -> AppleExportReply {
    let input = try openFile(source)
    return try withClosed(input) {
      let original = try fileIdentity(input)
      guard original.size == request.byteCount else { throw failure(.inputChanged) }
      let verified = try digestFile(input, operation: request.operationId)
      guard verified.digest == request.sha256.lowercased(), verified.count == request.byteCount,
            try fileIdentity(input) == original, try pathIdentity(source) == original else {
        throw failure(.inputChanged)
      }
      try checkCancellation(request.operationId)
      guard lseek(input, 0, SEEK_SET) == 0 else { throw failure(.storage) }
      let created = try createUnique(directoryFD, name: request.displayName)
      let output = created.fd
      let url = directory.appendingPathComponent(created.name)
      var closed = false
      var copied: Int64 = 0
      var hash = SHA256()
      var identity: AppleFileIdentity?
      var copyError: Error?
      do {
        identity = try fileIdentity(output)
        while true {
          try checkCancellation(request.operationId)
          let bytes = try readChunk(input, limit: chunkSize)
          if bytes.isEmpty { break }
          try writeAll(output, bytes)
          hash.update(data: bytes); copied += Int64(bytes.count)
          guard copied <= request.byteCount else { throw failure(.inputChanged) }
        }
        guard copied == request.byteCount, hex(hash.finalize()) == request.sha256.lowercased(),
              try fileIdentity(input) == original, try pathIdentity(source) == original else {
          throw failure(.inputChanged)
        }
        guard fsync(output) == 0 else { throw failure(.storage) }
      } catch { copyError = error }
      // close is never retried: an EINTR/unknown result cannot prove ownership of
      // that descriptor after another thread reuses the descriptor number.
      closed = closeFD(output) == 0
      let expectedDigest = hex(hash.finalize())
      guard let createdIdentity = identity else { return reply(.unconfirmed, pending: true) }
      let owned = OwnedFile(url: url, identity: createdIdentity, digest: expectedDigest,
                            count: copied, closed: closed)
      if !closed { return reply(.unconfirmed, pending: true) }
      do {
        if let error = copyError { throw error }
        let readback = try inspectOwned(owned)
        guard readback.digest == request.sha256.lowercased(), readback.count == request.byteCount,
              try fileIdentity(input) == original, try pathIdentity(source) == original else {
          throw failure(.inputChanged)
        }
        try checkCancellation(request.operationId)
        confirmed?(url, readback.identity)
        return AppleExportReply(code: .ok, cleanupPending: false, uri: url.absoluteString, displayName: created.name)
      } catch {
        let cleaned = removeOwned(owned)
        return reply(cleaned ? code(error) : .unconfirmed, pending: !cleaned)
      }
    }
  }

  private func validateRequest(_ request: AppleExportRequest) throws -> URL {
    try requireRunning()
    guard validUUID(request.operationId), request.byteCount >= 0,
          request.sha256.utf8.count == 64,
          request.sha256.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
          validName(request.displayName), !request.sourcePath.contains("\0"),
          !request.sourcePath.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
          request.sourcePath.hasPrefix("/") else { throw failure(.invalidInput) }
    let source = try privateURL(URL(fileURLWithPath: request.sourcePath))
    try checkCloud(source)
    return source
  }

  private func beginOperation(_ id: String) throws {
    lock.lock(); defer { lock.unlock() }
    guard !stopping else { throw failure(.unavailable) }
    guard !started.contains(id), started.count < maxOperations else { throw failure(.invalidInput) }
    started.insert(id)
    guard !cancelled.contains(id) else { throw failure(.cancelled) }
  }

  private func requireRunning() throws {
    lock.lock(); defer { lock.unlock() }
    if stopping { throw failure(.unavailable) }
  }
  private func withState<T>(_ work: () throws -> T) rethrows -> T {
    lock.lock(); defer { lock.unlock() }
    return try work()
  }
  private func checkCancellation(_ id: String) throws {
    if isCancelled(operationId: id) { throw failure(.cancelled) }
  }
  private func validUUID(_ value: String) -> Bool {
    guard value.utf8.count == 36, let parsed = UUID(uuidString: value),
          parsed.uuidString.lowercased() == value.lowercased() else { return false }
    let bytes = Array(value.lowercased().utf8)
    return bytes[14] == 52 && [56, 57, 97, 98].contains(bytes[19])
  }
  private func validName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 200
      && !name.contains("/") && !name.contains("\\")
      && !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
  }
  private func photoExtension(_ request: AppleExportRequest) throws -> String {
    let ext = (request.displayName as NSString).pathExtension.lowercased()
    if ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "heif", "tif", "tiff", "avif"].contains(ext) {
      return ext
    }
    throw failure(.invalidInput)
  }
  private func beginScope(_ url: URL, _ required: Bool) throws -> Bool {
    let started = url.startAccessingSecurityScopedResource()
    if required && !started && (try? privateURL(url)) == nil { throw failure(.permissionDenied) }
    return started
  }
  private func privateURL(_ url: URL) throws -> URL {
    guard url.isFileURL else { throw failure(.invalidInput) }
    let raw = url.path
    guard !raw.contains("\0"), !raw.split(separator: "/").contains("..") else { throw failure(.invalidInput) }
    for root in roots {
      for prefix in [root.original.path, root.canonical.path] where raw.hasPrefix(prefix + "/") {
        let suffix = String(raw.dropFirst(prefix.count + 1))
        return try checkedURL(root.canonical.appendingPathComponent(suffix))
      }
    }
    throw failure(.permissionDenied)
  }
  private func checkedURL(_ url: URL) throws -> URL {
    guard url.isFileURL, !url.path.contains("\0"), !url.path.split(separator: "/").contains("..") else {
      throw failure(.invalidInput)
    }
    // These OS-owned aliases are resolved before walking child components. No
    // application-managed or user-selected symlink is accepted as an ancestor.
    var path = url.path
    for entry in systemAliases where path == entry.alias || path.hasPrefix(entry.alias + "/") {
      path = entry.canonical + String(path.dropFirst(entry.alias.count))
    }
    return URL(fileURLWithPath: path).standardizedFileURL
  }
  private func openDirectory(_ url: URL) throws -> Int32 {
    let safe = try checkedURL(url)
    var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard current >= 0 else { throw posixFailure() }
    for component in safe.path.split(separator: "/") {
      let next = openat(current, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      let nextError = next < 0 ? posixFailure() : nil
      let closeOK = closeFD(current) == 0
      if !closeOK {
        if next >= 0 { _ = closeFD(next) }
        throw failure(.unconfirmed)
      }
      if let error = nextError { throw error }
      current = next
    }
    return current
  }
  private func openFile(_ url: URL) throws -> Int32 {
    let safe = try checkedURL(url)
    let parent = try openDirectory(safe.deletingLastPathComponent())
    var fd: Int32 = -1
    do {
      _ = try withClosed(parent) {
        fd = openat(parent, safe.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw posixFailure() }
      }
      _ = try fileIdentity(fd)
      return fd
    } catch {
      if fd >= 0 && closeFD(fd) != 0 { throw failure(.unconfirmed) }
      throw error
    }
  }
  private func fileIdentity(_ fd: Int32) throws -> AppleFileIdentity {
    var value = stat()
    guard fstat(fd, &value) == 0 else { throw posixFailure() }
    guard (value.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), value.st_size >= 0 else {
      throw failure(.invalidInput)
    }
    return AppleFileIdentity(value)
  }
  private func directoryIdentity(_ fd: Int32) throws -> AppleFileIdentity {
    var value = stat()
    guard fstat(fd, &value) == 0, (value.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
      throw failure(.invalidInput)
    }
    return AppleFileIdentity(value)
  }
  private func pathIdentity(_ url: URL) throws -> AppleFileIdentity {
    let fd = try openFile(url)
    return try withClosed(fd) { try fileIdentity(fd) }
  }
  private func withClosed<T>(_ fd: Int32, _ work: () throws -> T) throws -> T {
    let result: Result<T, Error>
    do { result = .success(try work()) } catch { result = .failure(error) }
    guard closeFD(fd) == 0 else { throw failure(.unconfirmed) }
    return try result.get()
  }
  private func closeFD(_ fd: Int32) -> Int32 { closeDescriptor(fd) }
  private func checkCloud(_ url: URL) throws {
    do {
      let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
      if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded {
        throw failure(.cloudPending)
      }
    } catch let error as AppleFileFailure { throw error }
    catch {
      let native = error as NSError
      if native.domain == NSCocoaErrorDomain && native.code == NSFileReadNoSuchFileError {
        throw failure(.sourceMissing)
      }
      if native.domain == NSCocoaErrorDomain && native.code == NSFileReadNoPermissionError {
        throw failure(.permissionDenied)
      }
      throw failure(.unavailable)
    }
  }
  private func readChunk(_ fd: Int32, limit: Int) throws -> Data {
    if limit == 0 { return Data() }
    var buffer = [UInt8](repeating: 0, count: limit)
    var count: Int
    repeat { count = Darwin.read(fd, &buffer, limit) } while count < 0 && errno == EINTR
    guard count >= 0 else { throw posixFailure() }
    return Data(buffer.prefix(count))
  }
  private func writeAll(_ fd: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset < raw.count {
        let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw posixFailure() }
        offset += count
      }
    }
  }
  private func digestFile(_ fd: Int32, operation: String? = nil) throws -> (digest: String, count: Int64) {
    guard lseek(fd, 0, SEEK_SET) == 0 else { throw failure(.storage) }
    var hash = SHA256(); var count: Int64 = 0
    while true {
      if let operation = operation { try checkCancellation(operation) }
      let data = try readChunk(fd, limit: chunkSize)
      if data.isEmpty { break }
      hash.update(data: data); count += Int64(data.count)
    }
    return (hex(hash.finalize()), count)
  }
  private func hex(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }
  private func createUnique(_ directory: Int32, name: String) throws -> (fd: Int32, name: String) {
    let ext = (name as NSString).pathExtension
    let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
    for attempt in 0..<10000 {
      let candidate = attempt == 0 ? name : "\(stem) (\(attempt))\(ext.isEmpty ? "" : "." + ext)"
      let fd = openat(directory, candidate, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      if fd >= 0 { return (fd, candidate) }
      if errno != EEXIST { throw posixFailure() }
    }
    throw failure(.storage)
  }
  private func inspectOwned(_ owned: OwnedFile) throws -> (digest: String, count: Int64, identity: AppleFileIdentity) {
    guard owned.closed else { throw failure(.unconfirmed) }
    let fd = try openFile(owned.url)
    return try withClosed(fd) {
      let before = try fileIdentity(fd)
      guard before.sameObject(owned.identity), before.size == owned.count else { throw failure(.inputChanged) }
      let bytes = try digestFile(fd)
      guard bytes.count == owned.count, bytes.digest == owned.digest,
            try fileIdentity(fd) == before, try pathIdentity(owned.url) == before else {
        throw failure(.inputChanged)
      }
      return (bytes.digest, bytes.count, before)
    }
  }
  private func removeOwned(_ owned: OwnedFile) -> Bool {
    do {
      let verified = try inspectOwned(owned)
      let parent = try openDirectory(owned.url.deletingLastPathComponent())
      return try withClosed(parent) {
        var value = stat()
        guard fstatat(parent, owned.url.lastPathComponent, &value, AT_SYMLINK_NOFOLLOW) == 0,
              (value.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              AppleFileIdentity(value) == verified.identity else { return false }
        return unlinkat(parent, owned.url.lastPathComponent, 0) == 0
      }
    } catch { return false }
  }
  private func coordinatedRead<T>(_ url: URL, _ work: (URL) throws -> T) throws -> T {
    var coordinationError: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
      do {
        guard try checkedURL(coordinated) == checkedURL(url) else { throw failure(.invalidInput) }
        result = .success(try work(url))
      } catch { result = .failure(error) }
    }
    if case let .failure(error)? = result { throw error }
    guard coordinationError == nil, let actual = result else { throw failure(.unavailable) }
    return try actual.get()
  }
  private func coordinatedWrite<T>(_ url: URL, _ work: (URL) throws -> T) throws -> T {
    var coordinationError: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinated in
      do {
        guard try checkedURL(coordinated) == checkedURL(url) else { throw failure(.invalidInput) }
        result = .success(try work(url))
      } catch { result = .failure(error) }
    }
    if case let .failure(error)? = result { throw error }
    guard coordinationError == nil, let actual = result else { throw failure(.unavailable) }
    return try actual.get()
  }
  private func posixFailure() -> AppleFileFailure {
    switch errno {
    case ENOENT: return failure(.sourceMissing)
    case EACCES, EPERM: return failure(.permissionDenied)
    case ELOOP, ENOTDIR: return failure(.invalidInput)
    default: return failure(.storage)
    }
  }
  private func failure(_ code: AppleIoCode) -> AppleFileFailure { AppleFileFailure(code: code) }
  private func code(_ error: Error) -> AppleIoCode { (error as? AppleFileFailure)?.code ?? .unavailable }
  private func safeError(_ error: Error) -> Error { failure(code(error)) }
  private func reply(_ code: AppleIoCode, pending: Bool = false) -> AppleExportReply {
    AppleExportReply(code: code, cleanupPending: pending)
  }
  private func deliver<T>(_ result: Result<T, Error>, _ completion: @escaping (Result<T, Error>) -> Void) {
    DispatchQueue.main.async { completion(result) }
  }
}
