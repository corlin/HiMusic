import Flutter
import UIKit
import AVKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var directoryPicker: DirectoryPicker?

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HiMusicDirectoryPicker") {
      directoryPicker = DirectoryPicker(messenger: registrar.messenger())
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

// MARK: - Directory Picker

/// iOS 目录选择器：通过 UIDocumentPickerViewController 选择文件夹，
/// 并用安全范围书签持久化授权，下次启动可自动恢复访问。
private class DirectoryPicker: NSObject, UIDocumentPickerDelegate {
    private let channel: FlutterMethodChannel
    private var pendingResult: FlutterResult?
    private var activeURL: URL?
    private let bookmarkKey = "himusic_music_folder_bookmark"

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "app.himusic/directory_picker",
            binaryMessenger: messenger
        )
        super.init()
        channel.setMethodCallHandler(handle)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickDirectory":
            pickDirectory(result: result)
        case "restoreDirectory":
            restoreDirectory(result: result)
        case "clearDirectory":
            clearDirectory(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func pickDirectory(result: @escaping FlutterResult) {
        pendingResult = result
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.folder],
            asCopy: false
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        guard let presenter = Self.topViewController() else {
            result(FlutterError(
                code: "NO_VIEW_CONTROLLER",
                message: "无法显示目录选择器",
                details: nil
            ))
            return
        }
        presenter.present(picker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first else {
            pendingResult?(nil)
            pendingResult = nil
            return
        }
        let didStart = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            activeURL?.stopAccessingSecurityScopedResource()
            activeURL = url
            pendingResult?(url.path)
        } catch {
            if didStart { url.stopAccessingSecurityScopedResource() }
            pendingResult?(FlutterError(
                code: "BOOKMARK_FAILED",
                message: "无法保存文件夹授权",
                details: error.localizedDescription
            ))
        }
        pendingResult = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingResult?(nil)
        pendingResult = nil
    }

    private func restoreDirectory(result: @escaping FlutterResult) {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            result(nil)
            return
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                result(FlutterError(
                    code: "ACCESS_DENIED",
                    message: "无法访问已保存的文件夹，请重新选择",
                    details: nil
                ))
                return
            }
            activeURL?.stopAccessingSecurityScopedResource()
            activeURL = url
            if isStale {
                if let fresh = try? url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(fresh, forKey: bookmarkKey)
                }
            }
            result(url.path)
        } catch {
            result(FlutterError(
                code: "RESTORE_FAILED",
                message: "无法恢复文件夹访问",
                details: error.localizedDescription
            ))
        }
    }

    private func clearDirectory(result: @escaping FlutterResult) {
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        result(nil)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive }
            as? UIWindowScene
        let window = scene?.windows.first { $0.isKeyWindow }
            ?? scene?.windows.first
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }
}
