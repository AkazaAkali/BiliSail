import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var application: MacOSApplication?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let application = MacOSApplication()
    self.application = application
    if !application.start() { NSApp.terminate(nil) }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    application?.shutDown()
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
