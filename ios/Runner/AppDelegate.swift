import Flutter
import UIKit
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HiMusicAudioOutput") {
      registrar.register(RoutePickerFactory(), withId: "app.himusic/route-picker")
    }
  }
}

private class RoutePickerFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    RoutePicker(frame: frame)
  }
}
private class RoutePicker: NSObject, FlutterPlatformView {
  private let picker: AVRoutePickerView
  init(frame: CGRect) {
    picker = AVRoutePickerView(frame: frame)
    picker.tintColor = .systemGreen
    picker.activeTintColor = .systemGreen
    picker.accessibilityLabel = "选择音频输出设备"
    super.init()
  }
  func view() -> UIView { picker }
}
