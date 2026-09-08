import 'package:metadata_audio/metadata_audio.dart' as audio;

import '../playback/audio_bridge.dart';
import '../sources/music_source.dart';

abstract interface class AudioMetadataLoader {
  Future<audio.AudioMetadata> read(MusicSource source, MusicEntry entry);
}

class AudioMetadataReader implements AudioMetadataLoader {
  @override
  Future<audio.AudioMetadata> read(MusicSource source, MusicEntry entry) async {
    final bridge = await AudioBridge.start(source);
    try {
      return await audio.parseUrl(
        bridge.register(entry).toString(),
        options: audio.ParseOptions.metadataOnly(),
        timeout: const Duration(seconds: 15),
      );
    } finally {
      await bridge.close();
    }
  }
}
