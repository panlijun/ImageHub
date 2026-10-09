import Flutter
import Photos
import UIKit
import UniformTypeIdentifiers

/// UIKit owns only the chooser and Photos transaction. All byte IO and scoped
/// resource ownership belongs to the shared engine.
final class IOSFileBridge: NSObject, AppleFileHost, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  typealias Presenter = (UIDocumentPickerViewController, @escaping (Bool) -> Void) -> Void
  typealias Dismisser = (UIDocumentPickerViewController, @escaping () -> Void) -> Void

  private enum SelectionReply {
    case backup((Result<AppleSelection, Error>) -> Void)
    case directory([String], (Result<AppleDestination, Error>) -> Void)
  }

  private final class SelectionSession {
    let id: String
    let picker: UIDocumentPickerViewController
    let reply: SelectionReply
    var presented = false
    var cancelled = false
    var ending = false
    var dismissing = false
    var urls: [URL] = []
    var cancellationReplies: [(Result<Void, Error>) -> Void] = []

    init(id: String, picker: UIDocumentPickerViewController, reply: SelectionReply) {
      self.id = id
      self.picker = picker
      self.reply = reply
    }
  }

  private let engine: AppleFileEngine
  private let presenter: Presenter
  private let dismisser: Dismisser
  private var selection: SelectionSession?
  private var retiredSelectionIds = Set<String>()
  private let maxSelectionIds = 10000
  private var disposed = false

  init(engine: AppleFileEngine = AppleFileEngine(),
       presenter: @escaping Presenter = IOSFileBridge.present,
       dismisser: @escaping Dismisser = IOSFileBridge.dismiss) {
    self.engine = engine
    self.presenter = presenter
    self.dismisser = dismisser
    super.init()
  }

  func pickBackup(selectionId: String, completion: @escaping (Result<AppleSelection, Error>) -> Void) {
    onMain {
      self.beginSelection(id: selectionId, types: [.zip], reply: .backup(completion))
    }
  }

  func pickDirectory(selectionId: String, operationIds: [String],
                     completion: @escaping (Result<AppleDestination, Error>) -> Void) {
    onMain {
      guard !operationIds.isEmpty, operationIds.count <= 1000, Set(operationIds).count == operationIds.count,
            operationIds.allSatisfy(Self.isV4UUID) else {
        completion(.failure(Self.failure(.invalidInput)))
        return
      }
      self.beginSelection(id: selectionId, types: [.folder], reply: .directory(operationIds, completion))
    }
  }

  func cancelSelection(selectionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    onMain {
      guard Self.isV4UUID(selectionId) else {
        completion(.failure(Self.failure(.invalidInput)))
        return
      }
      let canonicalId = selectionId.lowercased()
      guard let current = self.selection, current.id == canonicalId else {
        completion(.success(()))
        return
      }
      current.cancelled = true
      current.cancellationReplies.append(completion)
      self.endSelection(current, urls: [])
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let current = selection, current.picker === controller, !current.ending else { return }
    endSelection(current, urls: urls)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let current = selection, current.picker === controller else { return }
    current.cancelled = true
    endSelection(current, urls: [])
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard let current = selection,
          presentationController.presentedViewController === current.picker else { return }
    current.cancelled = true
    endSelection(current, urls: [])
  }

  func readResource(handle: String, completion: @escaping (Result<AppleReadReply, Error>) -> Void) {
    engine.readResource(handle: handle) { result in self.deliver(result, completion) }
  }

  func closeResource(handle: String, completion: @escaping (Result<Void, Error>) -> Void) {
    engine.closeResource(handle: handle) { result in self.deliver(result, completion) }
  }

  func closeDestination(handle: String, completion: @escaping (Result<Void, Error>) -> Void) {
    engine.closeDestination(handle: handle) { result in self.deliver(result, completion) }
  }

  func exportFile(request: AppleExportRequest, completion: @escaping (Result<AppleExportReply, Error>) -> Void) {
    if request.kind == .photos {
      savePhoto(request: request, completion: completion)
    } else {
      engine.exportFile(request: request) { result in self.deliver(result, completion) }
    }
  }

  func cancelExport(operationId: String) throws {
    engine.cancelExport(operationId: operationId)
  }

  /// Callable by XCTest with a real engine and real add-only Photos grant.
  func savePhoto(request: AppleExportRequest, completion: @escaping (Result<AppleExportReply, Error>) -> Void) {
    onMain {
      guard !self.disposed, request.kind == .photos else {
        completion(.failure(Self.failure(self.disposed ? .unavailable : .invalidInput)))
        return
      }
      self.engine.preparePhoto(request: request) { result in
        self.onMain {
          switch result {
          case .failure(let error):
            completion(.failure(Self.safeError(error)))
          case .success(let stage):
            self.authorizePhoto(stage: stage, completion: completion)
          }
        }
      }
    }
  }

  func dispose() {
    onMain {
      guard !self.disposed else { return }
      self.disposed = true
      if let current = self.selection {
        current.cancelled = true
        self.endSelection(current, urls: [])
      }
      // Existing Photos callbacks retain this bridge until actual work and
      // stage retirement finish; disposing never reports a premature result.
      self.engine.dispose()
    }
  }

  private func authorizePhoto(stage: ApplePhotoStage,
                              completion: @escaping (Result<AppleExportReply, Error>) -> Void) {
    guard !engine.isCancelled(operationId: stage.operationId), !disposed else {
      finishPhoto(stage, code: .cancelled, uri: nil, completion: completion)
      return
    }
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    if status == .notDetermined {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        self.onMain { self.commitPhoto(stage: stage, authorization: status, completion: completion) }
      }
    } else {
      commitPhoto(stage: stage, authorization: status, completion: completion)
    }
  }

  private func commitPhoto(stage: ApplePhotoStage, authorization: PHAuthorizationStatus,
                           completion: @escaping (Result<AppleExportReply, Error>) -> Void) {
    guard !engine.isCancelled(operationId: stage.operationId), !disposed else {
      finishPhoto(stage, code: .cancelled, uri: nil, completion: completion)
      return
    }
    guard authorization == .authorized else {
      finishPhoto(stage, code: .permissionDenied, uri: nil, completion: completion)
      return
    }
    var identifier: String?
    PHPhotoLibrary.shared().performChanges({
      let creation = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      options.shouldMoveFile = false
      options.originalFilename = stage.displayName
      creation.addResource(with: .photo, fileURL: stage.file, options: options)
      identifier = creation.placeholderForCreatedAsset?.localIdentifier
    }, completionHandler: { success, error in
      self.onMain {
        if success, let id = identifier, let uri = Self.photoURI(id) {
          // Cancellation after Photos has committed cannot erase saved evidence.
          self.finishPhoto(stage, code: .ok, uri: uri, completion: completion)
        } else {
          let nsError = error as NSError?
          let denied = nsError?.domain == PHPhotosErrorDomain &&
            nsError?.code == PHPhotosError.Code.accessUserDenied.rawValue
          self.finishPhoto(stage, code: denied ? .permissionDenied : .unconfirmed,
                           uri: nil, completion: completion)
        }
      }
    })
  }

  private func finishPhoto(_ stage: ApplePhotoStage, code: AppleIoCode, uri: String?,
                           completion: @escaping (Result<AppleExportReply, Error>) -> Void) {
    engine.finishPhoto(stage, code: code, uri: uri) { result in self.deliver(result, completion) }
  }

  private func beginSelection(id: String, types: [UTType], reply: SelectionReply) {
    guard Self.isV4UUID(id) else { reject(reply, code: .invalidInput); return }
    let canonicalId = id.lowercased()
    guard !disposed, selection == nil, retiredSelectionIds.count < maxSelectionIds,
          !retiredSelectionIds.contains(canonicalId) else {
      reject(reply, code: .unavailable)
      return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    let current = SelectionSession(id: canonicalId, picker: picker, reply: reply)
    selection = current
    presenter(picker) { presented in
      self.onMain {
        guard self.selection === current else { return }
        if presented {
          current.presented = true
          current.picker.presentationController?.delegate = self
          if current.ending { self.dismissSelection(current) }
        } else {
          self.selection = nil
          self.retiredSelectionIds.insert(current.id)
          current.picker.delegate = nil
          self.reject(current.reply, code: .unavailable)
          current.cancellationReplies.forEach { $0(.success(())) }
        }
      }
    }
  }

  private func endSelection(_ current: SelectionSession, urls: [URL]) {
    guard selection === current else { return }
    if !current.ending {
      current.ending = true
      current.urls = urls
    }
    if current.presented { dismissSelection(current) }
  }

  private func dismissSelection(_ current: SelectionSession) {
    guard !current.dismissing else { return }
    current.dismissing = true
    dismisser(current.picker) {
      self.onMain {
        guard self.selection === current else { return }
        self.selection = nil
        self.retiredSelectionIds.insert(current.id)
        current.picker.delegate = nil
        if current.cancelled {
          switch current.reply {
          case .backup(let completion): completion(.success(AppleSelection(cancelled: true, resources: [])))
          case .directory(_, let completion): completion(.success(AppleDestination(cancelled: true)))
          }
        } else if current.urls.count != 1 {
          self.reject(current.reply, code: .invalidInput)
        } else {
          do {
            switch current.reply {
            case .backup(let completion):
              completion(.success(try self.engine.registerBackup(current.urls[0], requireSecurityScope: true)))
            case .directory(let ids, let completion):
              completion(.success(try self.engine.registerDirectory(current.urls[0], operationIds: ids,
                                                                    requireSecurityScope: true)))
            }
          } catch { self.reject(current.reply, error: error) }
        }
        current.cancellationReplies.forEach { $0(.success(())) }
      }
    }
  }

  private func reject(_ reply: SelectionReply, code: AppleIoCode) {
    reject(reply, error: Self.failure(code))
  }

  private func reject(_ reply: SelectionReply, error: Error) {
    switch reply {
    case .backup(let completion): completion(.failure(Self.safeError(error)))
    case .directory(_, let completion): completion(.failure(Self.safeError(error)))
    }
  }

  private func deliver<T>(_ result: Result<T, Error>, _ completion: @escaping (Result<T, Error>) -> Void) {
    onMain { completion(result.mapError(Self.safeError)) }
  }

  private func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
  }

  private static func failure(_ code: AppleIoCode) -> Error {
    let name: String
    switch code {
    case .ok: name = "ok"
    case .cancelled: name = "cancelled"
    case .permissionDenied: name = "permissionDenied"
    case .sourceMissing: name = "sourceMissing"
    case .cloudPending: name = "cloudPending"
    case .unavailable: name = "unavailable"
    case .invalidInput: name = "invalidInput"
    case .inputChanged: name = "inputChanged"
    case .unsupported: name = "unsupported"
    case .storage: name = "storage"
    case .cleanupPending: name = "cleanupPending"
    case .unconfirmed: name = "unconfirmed"
    }
    return PigeonError(code: name, message: "Unable to complete the file operation.", details: nil)
  }

  private static func safeError(_ error: Error) -> Error {
    if let failure = error as? AppleFileFailure { return Self.failure(failure.code) }
    if let failure = error as? PigeonError,
       ["ok", "cancelled", "permissionDenied", "sourceMissing", "cloudPending", "unavailable",
        "invalidInput", "inputChanged", "unsupported", "storage", "cleanupPending", "unconfirmed"]
        .contains(failure.code) {
      return PigeonError(code: failure.code, message: "Unable to complete the file operation.", details: nil)
    }
    return Self.failure(.unavailable)
  }

  private static func isV4UUID(_ value: String) -> Bool {
    guard value.utf8.count == 36, let uuid = UUID(uuidString: value),
          uuid.uuidString.lowercased() == value.lowercased() else { return false }
    let bytes = Array(value.utf8)
    return bytes[14] == 52 && [56, 57, 65, 66, 97, 98].contains(bytes[19])
  }

  static func photoURI(_ identifier: String) -> String? {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.~")
    let bytes = Array(identifier.utf8)
    guard !bytes.isEmpty, bytes.count <= 256,
          bytes.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
            (48...57).contains($0) || $0 == 47 || $0 == 95 || $0 == 45 }),
          let encoded = identifier.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
    return "ph://asset/\(encoded)"
  }

  static func present(_ picker: UIDocumentPickerViewController,
                              completion: @escaping (Bool) -> Void) {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
    let candidates = scenes.flatMap { $0.windows }.filter { $0.isKeyWindow && !$0.isHidden }
    guard candidates.count == 1, let root = candidates[0].rootViewController,
          let flutter = findFlutterController(root), flutter.viewIfLoaded?.window != nil,
          flutter.presentedViewController == nil, !flutter.isBeingDismissed else {
      completion(false)
      return
    }
    picker.modalPresentationStyle = .formSheet
    if let popover = picker.popoverPresentationController {
      popover.sourceView = flutter.view
      popover.sourceRect = CGRect(x: flutter.view.bounds.midX, y: flutter.view.bounds.midY, width: 1, height: 1)
      popover.permittedArrowDirections = []
    }
    flutter.present(picker, animated: true) { completion(picker.presentingViewController != nil) }
  }

  private static func findFlutterController(_ root: UIViewController) -> FlutterViewController? {
    if let flutter = root as? FlutterViewController { return flutter }
    if let navigation = root as? UINavigationController, let visible = navigation.visibleViewController {
      return findFlutterController(visible)
    }
    if let tabs = root as? UITabBarController, let selected = tabs.selectedViewController {
      return findFlutterController(selected)
    }
    for child in root.children {
      if let flutter = findFlutterController(child) { return flutter }
    }
    return nil
  }

  static func dismiss(_ picker: UIDocumentPickerViewController, completion: @escaping () -> Void) {
    if picker.isBeingDismissed, let transition = picker.transitionCoordinator,
       transition.animate(alongsideTransition: nil, completion: { context in
         if context.isCancelled {
           picker.dismiss(animated: true, completion: completion)
         } else { completion() }
       }) { return }
    if picker.presentingViewController == nil, picker.viewIfLoaded?.window == nil {
      completion()
    } else {
      picker.dismiss(animated: true, completion: completion)
    }
  }
}
