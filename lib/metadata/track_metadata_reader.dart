import '../sources/music_source.dart';
import 'audio_metadata_reader.dart';
import 'track_metadata.dart';

abstract interface class TrackMetadataLoader {
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry);
}

class TrackMetadataReader implements TrackMetadataLoader {
  TrackMetadataReader({AudioMetadataLoader? audioReader})
    : _audioReader = audioReader ?? AudioMetadataReader();

  final AudioMetadataLoader _audioReader;

  @override
  Future<TrackMetadata> read(MusicSource source, MusicEntry entry) async {
    final parsed = await _audioReader.read(source, entry);
    return TrackMetadata.fromAudioMetadata(parsed);
  }
}
