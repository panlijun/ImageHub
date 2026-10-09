import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

// The presenter seam verifies selection ownership without showing system UI.
protocol MacBackupPanel: AnyObject {
  func present(for window: NSWindow?, completion: @escaping (NSApplication.ModalResponse, URL?) -> Void)
  func cancel()
}

final class NativeMacBackupPanel: MacBackupPanel {
  let panel = NSOpenPanel()

  init() {
    panel.allowedContentTypes = [.zip]
    panel.allowsOtherFileTypes = false
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.resolvesAliases = false
    panel.treatsFilePackagesAsDirectories = false
  }

  func present(for window: NSWindow?, completion: @escaping (NSApplication.ModalResponse, URL?) -> Void) {
    let finish: (NSApplication.ModalResponse) -> Void = { [panel] response in
      completion(response, response == .OK ? panel.url : nil)
    }
    if let window = window {
      panel.beginSheetModal(for: window, completionHandler: finish)
    } else {
      panel.begin(completionHandler: finish)
    }
  }

  func cancel() {
    panel.cancel(nil)
  }
}

final class MacFileBridge: NSObject, AppleFileHost {
  private final class Selection {
    let id: String
    let panel: MacBackupPanel
    let completion: (Result<AppleSelection, Error>) -> Void
    var cancelled = false
    var cancellationCompletions: [(Result<Void, Error>) -> Void] = []

    init(id: String, panel: MacBackupPanel, completion: @escaping (Result<AppleSelection, Error>) -> Void) {
      self.id = id
      self.panel = panel
      self.completion = completion
    }
  }

  private weak var window: NSWindow?
  private let messenger: FlutterBinaryMessenger?
  private let engine: AppleFileEngine
  private let panelFactory: () -> MacBackupPanel
  private let registerBackup: (URL) throws -> AppleSelection
  private var selection: Selection?
  private var retiredSelectionIds = Set<String>()
  private let maxSelectionIds = 10000
  private var disposed = false

  init(
    messenger: FlutterBinaryMessenger? = nil,
    window: NSWindow?,
    engine: AppleFileEngine = AppleFileEngine(),
    panelFactory: @escaping () -> MacBackupPanel = { NativeMacBackupPanel() },
    registerBackup: ((URL) throws -> AppleSelection)? = nil
  ) {
    self.messenger = messenger
    self.window = window
    self.engine = engine
    self.panelFactory = panelFactory
    // NSOpenPanel grants the macOS Powerbox selection access. The engine still
    // balances any successful scope start and coordinates actual reads; no
    // external path or persistent bookmark crosses the Dart boundary.
    self.registerBackup = registerBackup ?? { try engine.registerBackup($0, requireSecurityScope: false) }
    super.init()
    if let messenger = messenger {
      AppleFileHostSetup.setUp(binaryMessenger: messenger, api: self)
    }
  }

  func pickBackup(selectionId: String, completion: @escaping (Result<AppleSelection, Error>) -> Void) {
    onMain {
      guard Self.isOperationId(selectionId) else {
        completion(.failure(Self.error(.invalidInput)))
        return
      }
      let id = selectionId.lowercased()
      guard !self.disposed, self.selection == nil,
            !self.retiredSelectionIds.contains(id),
            self.retiredSelectionIds.count < self.maxSelectionIds else {
        completion(.failure(Self.error(.unavailable)))
        return
      }
      let pending = Selection(id: id, panel: self.panelFactory(), completion: completion)
      self.selection = pending
      // Retain the bridge until the real panel callback. Window close may drop
      // its bridge reference while cancellation is still finishing.
      pending.panel.present(for: self.window) { [self, weak pending] response, url in
        self.onMain {
          guard let pending = pending, self.selection === pending else { return }
          self.finish(pending, response: response, url: url)
        }
      }
    }
  }

  func cancelSelection(selectionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    onMain {
      guard Self.isOperationId(selectionId) else {
        completion(.failure(Self.error(.invalidInput)))
        return
      }
      guard let pending = self.selection, pending.id == selectionId.lowercased() else {
        completion(.success(()))
        return
      }
      pending.cancellationCompletions.append(completion)
      self.cancel(pending)
    }
  }

  func readResource(handle: String, completion: @escaping (Result<AppleReadReply, Error>) -> Void) {
    engine.readResource(handle: handle) { result in
      self.onMain { completion(result.mapError(Self.safeError)) }
    }
  }

  func closeResource(handle: String, completion: @escaping (Result<Void, Error>) -> Void) {
    engine.closeResource(handle: handle) { result in
      self.onMain { completion(result.mapError(Self.safeError)) }
    }
  }

  func pickDirectory(selectionId: String, operationIds: [String], completion: @escaping (Result<AppleDestination, Error>) -> Void) {
    // Desktop exports retain the existing file_selector/FileExporter path.
    onMain { completion(.failure(Self.error(.unsupported))) }
  }

  func closeDestination(handle: String, completion: @escaping (Result<Void, Error>) -> Void) {
    engine.closeDestination(handle: handle) { result in
      self.onMain { completion(result.mapError(Self.safeError)) }
    }
  }

  func exportFile(request: AppleExportRequest, completion: @escaping (Result<AppleExportReply, Error>) -> Void) {
    onMain { completion(.success(AppleExportReply(code: .unsupported, cleanupPending: false))) }
  }

  func cancelExport(operationId: String) throws {
    guard Self.isOperationId(operationId) else { throw Self.error(.invalidInput) }
    engine.cancelExport(operationId: operationId)
  }

  func dispose() {
    onMain {
      guard !self.disposed else { return }
      self.disposed = true
      if let pending = self.selection { self.cancel(pending) }
      if let messenger = self.messenger {
        AppleFileHostSetup.setUp(binaryMessenger: messenger, api: nil)
      }
      self.engine.dispose()
    }
  }

  private func cancel(_ pending: Selection) {
    guard !pending.cancelled else { return }
    pending.cancelled = true
    // Never use application-wide abortModal, endSheet, or another window.
    pending.panel.cancel()
  }

  private func finish(_ pending: Selection, response: NSApplication.ModalResponse, url: URL?) {
    let result: Result<AppleSelection, Error>
    if pending.cancelled || disposed || response != .OK {
      result = .success(AppleSelection(cancelled: true, resources: []))
    } else if let url = url {
      do {
        result = .success(try registerBackup(url))
      } catch {
        result = .failure(Self.safeError(error))
      }
    } else {
      result = .failure(Self.error(.invalidInput))
    }
    retiredSelectionIds.insert(pending.id)
    selection = nil
    pending.completion(result)
    for completion in pending.cancellationCompletions { completion(.success(())) }
    pending.cancellationCompletions.removeAll()
  }

  private func onMain(_ body: @escaping () -> Void) {
    if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
  }

  private static func isOperationId(_ value: String) -> Bool {
    value.utf8.count == 36 && value.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil
  }

  private static func safeError(_ failure: Error) -> Error {
    error((failure as? AppleFileFailure)?.code ?? .unavailable)
  }

  private static func error(_ code: AppleIoCode) -> Error {
    let name: String
    switch code {
    case .cancelled: name = "cancelled"
    case .permissionDenied: name = "permissionDenied"
    case .sourceMissing: name = "sourceMissing"
    case .cloudPending: name = "cloudPending"
    case .invalidInput: name = "invalidInput"
    case .inputChanged: name = "inputChanged"
    case .unsupported: name = "unsupported"
    case .storage: name = "storage"
    case .cleanupPending: name = "cleanupPending"
    case .unconfirmed: name = "unconfirmed"
    case .ok, .unavailable: name = "unavailable"
    }
    return PigeonError(code: name, message: "Unable to complete the file operation.", details: nil)
  }
}
