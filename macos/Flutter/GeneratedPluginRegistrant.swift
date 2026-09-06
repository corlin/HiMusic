//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import audio_session
import dart_smb2
import file_selector_macos
import just_audio
import just_waveform

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AudioSessionPlugin.register(with: registry.registrar(forPlugin: "AudioSessionPlugin"))
  DartSmb2Plugin.register(with: registry.registrar(forPlugin: "DartSmb2Plugin"))
  FileSelectorPlugin.register(with: registry.registrar(forPlugin: "FileSelectorPlugin"))
  JustAudioPlugin.register(with: registry.registrar(forPlugin: "JustAudioPlugin"))
  JustWaveformPlugin.register(with: registry.registrar(forPlugin: "JustWaveformPlugin"))
}
