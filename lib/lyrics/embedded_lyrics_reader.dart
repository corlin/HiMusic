import 'package:metadata_audio/metadata_audio.dart' as audio;

import '../metadata/audio_metadata_reader.dart';
import '../sources/music_source.dart';
import 'lyrics_document.dart';

class EmbeddedLyricsCandidates {
  const EmbeddedLyricsCandidates({this.synchronized, this.plain});

  final LyricsDocument? synchronized;
  final LyricsDocument? plain;
}

abstract interface class EmbeddedLyricsLoader {
  Future<EmbeddedLyricsCandidates> read(MusicSource source, MusicEntry entry);
}

class EmbeddedLyricsReader implements EmbeddedLyricsLoader {
  EmbeddedLyricsReader({AudioMetadataLoader? audioReader})
    : _audioReader = audioReader ?? AudioMetadataReader();

  final AudioMetadataLoader _audioReader;

  @override
  Future<EmbeddedLyricsCandidates> read(
    MusicSource source,
    MusicEntry entry,
  ) async {
    final metadata = await _audioReader.read(source, entry);
    return fromMetadata(metadata);
  }

  EmbeddedLyricsCandidates fromMetadata(audio.AudioMetadata metadata) {
    LyricsDocument? synchronized;
    String? plain;
    for (final lyric in metadata.common.lyrics ?? const <audio.LyricsTag>[]) {
      final timed =
          lyric.syncText
              .where(
                (line) => line.timestamp != null && line.text.trim().isNotEmpty,
              )
              .map(
                (line) => TimedLyricLine(
                  timestamp: Duration(milliseconds: line.timestamp!),
                  text: line.text.trim(),
                ),
              )
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (synchronized == null && timed.isNotEmpty) {
        synchronized = LyricsDocument(
          source: LyricsSource.embeddedSynced,
          lines: timed,
        );
      }
      final text = lyric.text?.trim();
      if (plain == null && text != null && text.isNotEmpty) plain = text;
    }
    return EmbeddedLyricsCandidates(
      synchronized: synchronized,
      plain: plain == null
          ? null
          : LyricsDocument(
              source: LyricsSource.embeddedPlain,
              plainText: plain,
            ),
    );
  }
}
