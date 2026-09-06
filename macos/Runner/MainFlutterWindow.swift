import Cocoa
import FlutterMacOS
import CoreAudio

class MainFlutterWindow: NSWindow {
  private var outputChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(name: "app.himusic/output", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      do {
        switch call.method {
        case "list": result(try AudioOutputs.list())
        case "select":
          guard let id = call.arguments as? NSNumber else {
            result(FlutterError(code: "argument", message: "Missing device", details: nil)); return
          }
          try AudioOutputs.select(id.uint32Value)
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "audio_output", message: "Audio output unavailable", details: nil))
      }
    }
    outputChannel = channel

    super.awakeFromNib()
  }
}

private enum AudioOutputs {
  enum Failure: Error { case unavailable }
  static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }
  static func current() throws -> AudioDeviceID {
    var property = address(kAudioHardwarePropertyDefaultOutputDevice)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &id) == noErr else { throw Failure.unavailable }
    return id
  }
  static func list() throws -> [[String: Any]] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var property = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { throw Failure.unavailable }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &ids) == noErr else { throw Failure.unavailable }
    let selected = try current()
    return ids.compactMap { id in
      var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
      var streamSize: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
      var nameProperty = address(kAudioObjectPropertyName)
      var name: Unmanaged<CFString>?
      var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
      guard AudioObjectGetPropertyData(id, &nameProperty, 0, nil, &nameSize, &name) == noErr else { return nil }
      return ["id": Int(id), "name": name?.takeRetainedValue() as String? ?? "Audio output", "selected": id == selected]
    }
  }
  static func select(_ id: AudioDeviceID) throws {
    guard try list().contains(where: { ($0["id"] as? Int) == Int(id) }) else { throw Failure.unavailable }
    var device = id
    var property = address(kAudioHardwarePropertyDefaultOutputDevice)
    let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
    guard status == noErr, try current() == id else { throw Failure.unavailable }
  }
}
