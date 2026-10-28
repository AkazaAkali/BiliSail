import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceOrientation: DeviceOrientationHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    deviceOrientation?.close()
    deviceOrientation = DeviceOrientationHandler(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}

// Keep this small app-owned adapter alongside registration so no generated Xcode
// project files or third-party sensor dependency are needed.
private final class DeviceOrientationHandler: NSObject, FlutterStreamHandler {
  private let channel: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []
  private var generating = false
  private var lastOrientation: String?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterEventChannel(
      name: "bilisail/device_orientation", binaryMessenger: messenger
    )
    super.init()
    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError? {
    stop()
    sink = events
    let center = NotificationCenter.default
    observers = [
      center.addObserver(
        forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.publish() },
      center.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.setActive(true) },
      center.addObserver(
        forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.setActive(false) },
    ]
    setActive(UIApplication.shared.applicationState == .active)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stop()
    return nil
  }

  private func setActive(_ active: Bool) {
    let enabled = active && sink != nil && UIDevice.current.userInterfaceIdiom == .phone
    if enabled != generating {
      generating = enabled
      if enabled {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
      } else {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
      }
    }
    publish()
  }

  private func publish() {
    guard let sink else { return }
    var orientation = "unknown"
    if generating {
      switch UIDevice.current.orientation {
      case .portrait, .portraitUpsideDown: orientation = "portrait"
      case .landscapeLeft, .landscapeRight: orientation = "landscape"
      default: break // Flat and indeterminate readings are not physical turns.
      }
    }
    guard orientation != lastOrientation else { return }
    lastOrientation = orientation
    // iOS exposes no public rotation-lock query. Dart must gate automatic entry
    // on the unlocked interface orientation; physical readings still drive exit.
    sink([
      "orientation": orientation,
      "autoRotate": true,
      "supported": UIDevice.current.userInterfaceIdiom == .phone,
    ])
  }

  private func stop() {
    sink = nil
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
    if generating {
      UIDevice.current.endGeneratingDeviceOrientationNotifications()
      generating = false
    }
    lastOrientation = nil
  }

  func close() {
    stop()
    channel.setStreamHandler(nil)
  }
}
