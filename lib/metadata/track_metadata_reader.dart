import 'package:metadata_audio/metadata_audio.dart' as audio;

import '../playback/audio_bridge.dart';
import '../sources/music_source.dart';
import 'track_metadata.dart';

abstract interface class TrackMetadataLoader {
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry);
}

class TrackMetadataReader implements TrackMetadataLoader {
  @override
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry) async {
    final bridge = await AudioBridge.start(source);
    try {
      final parsed = await audio.parseUrl(
        bridge.register(entry).toString(),
        options: audio.ParseOptions.metadataOnly(),
        timeout: const Duration(seconds: 15),
      );
      return TrackMetadata.fromAudioMetadata(parsed);
    } finally {
      await bridge.close();
    }
  }
}
