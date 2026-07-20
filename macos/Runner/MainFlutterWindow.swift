import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = NSSize(width: 520, height: 600)

    // Dart drives the window title with the currents: profile · provider ·
    // model · tier (chat_screen updates it on ready/route events).
    let titleChannel = FlutterMethodChannel(
      name: "al.basecode.harness/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    titleChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "setTitle", let title = call.arguments as? String {
        self?.title = title
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
