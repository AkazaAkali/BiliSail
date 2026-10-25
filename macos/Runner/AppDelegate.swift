import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var application: MacOSApplication?
  private var applicationStarted = false
  private let termination = ApplicationTerminationCoordinator()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let application = MacOSApplication()
    self.application = application
    applicationStarted = application.start()
    if !applicationStarted { NSApp.terminate(nil) }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    application?.shutDown()
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard applicationStarted, let application = application else { return .terminateNow }
    return termination.requestExit(using: application.requestExit) {
      sender.terminate(nil)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Hot restart temporarily closes every SDK-managed window. Normal main
    // window Close requests application exit through Flutter's lifecycle,
    // allowing playback/download/native resources to finish releasing first.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

// The pinned engine marks shouldTerminate before Dart cleanup completes. Own
// the pending/approved distinction so another Cmd+Q cannot bypass that cleanup.
final class ApplicationTerminationCoordinator {
  private var pending = false
  private var approved = false

  func requestExit(
    using request: (@escaping (Bool) -> Void) -> Void,
    terminate: @escaping () -> Void
  ) -> NSApplication.TerminateReply {
    if approved { return .terminateNow }
    if pending { return .terminateCancel }
    pending = true
    request { [weak self] approved in
      guard let self = self else { return }
      self.pending = false
      if approved {
        self.approved = true
        terminate()
      }
    }
    return .terminateCancel
  }
}
