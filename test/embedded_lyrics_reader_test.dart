import 'package:flutter_test/flutter_test.dart';
import 'package:metadata_audio/metadata_audio.dart' as audio;
import 'package:himusic/lyrics/embedded_lyrics_reader.dart';
import 'package:himusic/lyrics/lyrics_document.dart';

void main() {
  test('maps synchronized and plain embedded lyrics', () {
    final metadata = audio.AudioMetadata(
      format: const audio.Format(),
      native: const {},
      common: const audio.CommonTags(
        track: audio.TrackNo(),
        disk: audio.TrackNo(),
        movementIndex: audio.TrackNo(),
        lyrics: [
          audio.LyricsTag(
            contentType: 'lyrics',
            timeStampFormat: 'milliseconds',
            syncText: [
              audio.LyricsText(text: '第二句', timestamp: 2000),
              audio.LyricsText(text: '第一句', timestamp: 1000),
            ],
          ),
          audio.LyricsTag(
            contentType: 'lyrics',
            timeStampFormat: 'none',
            syncText: [],
            text: '整段歌词',
          ),
        ],
      ),
      quality: const audio.QualityInformation(),
    );

    final result = EmbeddedLyricsReader().fromMetadata(metadata);
    expect(result.synchronized!.source, LyricsSource.embeddedSynced);
    expect(result.synchronized!.lines.map((line) => line.text), ['第一句', '第二句']);
    expect(result.plain!.plainText, '整段歌词');
  });
}
