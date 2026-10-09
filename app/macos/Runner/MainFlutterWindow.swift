import Cocoa
import FlutterMacOS
import Darwin
import Network

class MainFlutterWindow: NSWindow {
  private var storageChannel: FlutterMethodChannel?
  private var networkBridge: NetworkTypeBridge?
  private var fileBridge: MacFileBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "io.imagehost/storage_capacity",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler(StorageCapacityBridge.handle)
    storageChannel = channel
    networkBridge?.dispose()
    networkBridge = NetworkTypeBridge(messenger: flutterViewController.engine.binaryMessenger)
    fileBridge?.dispose()
    fileBridge = MacFileBridge(messenger: flutterViewController.engine.binaryMessenger, window: self)

    super.awakeFromNib()
  }

  override func close() {
    fileBridge?.dispose()
    fileBridge = nil
    networkBridge?.dispose()
    networkBridge = nil
    super.close()
  }

  deinit {
    fileBridge?.dispose()
    networkBridge?.dispose()
  }
}

private final class NetworkTypeBridge: NSObject, FlutterStreamHandler {
  private struct Snapshot: Equatable {
    let status: String
    let transports: [String]

    var message: [String: Any] {
      return ["status": status, "transports": transports]
    }

    static let unknown = Snapshot(status: "unknown", transports: [])

    init(status: String, transports: [String]) {
      self.status = status
      self.transports = transports
    }

    init(path: NWPath) {
      switch path.status {
      case .satisfied:
        var types: [String] = []
        if path.usesInterfaceType(.wifi) { types.append("wifi") }
        if path.usesInterfaceType(.wiredEthernet) { types.append("ethernet") }
        if path.usesInterfaceType(.cellular) { types.append("cellular") }
        self.init(status: "connected", transports: types.isEmpty ? ["other"] : types)
      case .unsatisfied:
        self.init(status: "offline", transports: [])
      case .requiresConnection:
        // Do not initiate the connection to resolve this passive observation.
        self.init(status: "unknown", transports: [])
      @unknown default:
        self.init(status: "unknown", transports: [])
      }
    }
  }

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let monitorQueue = DispatchQueue(label: "io.imagehost.network_observer")
  private var monitor: NWPathMonitor?
  private var sink: FlutterEventSink?
  private var snapshot = Snapshot.unknown
  private var generation: UInt64 = 0
  private var disposed = false

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: "io.imagehost/network", binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: "io.imagehost/network_changes", binaryMessenger: messenger)
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, !self.disposed else {
        result(FlutterError(code: "network_error", message: "Network observer is closed.", details: nil))
        return
      }
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.ensureMonitoring()
      // Until NWPathMonitor delivers its first actual state, remain unknown.
      result(self.snapshot.message)
    }
    eventChannel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard !disposed else {
      return FlutterError(code: "network_error", message: "Network observer is closed.", details: nil)
    }
    sink = events
    ensureMonitoring()
    events(snapshot.message)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    stopMonitoring()
    return nil
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    sink = nil
    stopMonitoring()
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }

  private func ensureMonitoring() {
    guard monitor == nil, !disposed else { return }
    snapshot = .unknown
    generation &+= 1
    let listenerGeneration = generation
    let next = NWPathMonitor()
    next.pathUpdateHandler = { [weak self] path in
      let observed = Snapshot(path: path)
      DispatchQueue.main.async { [weak self] in
        guard let self = self, !self.disposed,
              self.generation == listenerGeneration, self.monitor != nil else { return }
        if self.snapshot != observed {
          self.snapshot = observed
          self.sink?(observed.message)
        }
      }
    }
    monitor = next
    next.start(queue: monitorQueue)
  }

  private func stopMonitoring() {
    generation &+= 1
    monitor?.pathUpdateHandler = nil
    monitor?.cancel()
    monitor = nil
    snapshot = .unknown
  }

  deinit {
    monitor?.pathUpdateHandler = nil
    monitor?.cancel()
  }
}

private enum StorageCapacityBridge {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availableBytes":
      guard let path = absolutePath(call.arguments), directoriesAreSafe(path) else {
        result(FlutterError(code: "read_error", message: "Unable to read available storage.", details: nil))
        return
      }
      var statistics = statfs()
      guard path.withCString({ statfs($0, &statistics) }) == 0,
            statistics.f_bsize > 0 else {
        result(FlutterError(code: "read_error", message: "Unable to read available storage.", details: nil))
        return
      }
      let (bytes, overflow) = statistics.f_bavail.multipliedReportingOverflow(by: UInt64(statistics.f_bsize))
      guard !overflow, bytes <= UInt64(Int64.max) else {
        result(FlutterError(code: "read_error", message: "Unable to read available storage.", details: nil))
        return
      }
      result(Int64(bytes))

    case "publishExclusive":
      guard let arguments = call.arguments as? [String: Any],
            let source = absolutePath(arguments["source"]),
            let destination = absolutePath(arguments["destination"]),
            isRegularFile(source),
            directoriesAreSafe((source as NSString).deletingLastPathComponent),
            directoriesAreSafe((destination as NSString).deletingLastPathComponent) else {
        result(FlutterError(code: "publish_error", message: "Unable to publish the backup file.", details: nil))
        return
      }
      // The upper layer owns a closed, immutable stage. link atomically creates
      // a new directory entry without replacement or a cross-volume copy.
      let linked = source.withCString { sourcePath in
        destination.withCString { destinationPath in
          Darwin.link(sourcePath, destinationPath)
        }
      }
      guard linked == 0 else {
        let failure = errno
        if failure == EEXIST {
          result(false)
        } else {
          result(FlutterError(code: "publish_error", message: "Unable to publish the backup file.", details: nil))
        }
        return
      }
      // Publication already committed. If unlink fails, keep both paths and
      // report true so recovery/owned-stage cleanup can retry the source only.
      _ = source.withCString { Darwin.unlink($0) }
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func absolutePath(_ value: Any?) -> String? {
    guard let path = value as? String, !path.isEmpty,
          (path as NSString).isAbsolutePath,
          !path.utf8.contains(0),
          !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
      return nil
    }
    return path
  }

  private static func isRegularFile(_ path: String) -> Bool {
    var attributes = stat()
    return path.withCString { Darwin.lstat($0, &attributes) } == 0 &&
      attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
  }

  private static func directoriesAreSafe(_ path: String) -> Bool {
    var current = path
    while true {
      var attributes = stat()
      guard current.withCString({ Darwin.lstat($0, &attributes) }) == 0,
            attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
        return false
      }
      let parent = (current as NSString).deletingLastPathComponent
      if parent == current { return true }
      current = parent
    }
  }
}

