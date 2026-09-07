import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/metadata/track_metadata.dart';
import 'package:metadata_audio/metadata_audio.dart' as audio;

void main() {
  test('归一化常见创作者标签并忽略空值', () {
    final metadata = TrackMetadata.fromTags(const {
      'TITLE': ['  夜曲  '],
      'ARTIST': ['周杰伦'],
      'ALBUMARTIST': ['周杰伦'],
      'COMPOSER': ['周杰伦'],
      'ARRANGER': ['林迈可'],
      'LYRICIST': ['方文山'],
      'ALBUM': ['十一月的萧邦'],
      'GENRE': ['Pop', ''],
    });

    expect(metadata.title, '夜曲');
    expect(metadata.performers, ['周杰伦']);
    expect(metadata.albumArtist, '周杰伦');
    expect(metadata.composers, ['周杰伦']);
    expect(metadata.arrangers, ['林迈可']);
    expect(metadata.lyricists, ['方文山']);
    expect(metadata.album, '十一月的萧邦');
    expect(metadata.genres, ['Pop']);
  });

  test('兼容不同格式的编曲和作词标签名称', () {
    final metadata = TrackMetadata.fromTags(const {
      'TPE1': ['歌手甲'],
      'TCOM': ['作曲甲'],
      'TEXT': ['作词甲'],
      'ARRANGEMENT': ['编曲甲'],
    });

    expect(metadata.performers, ['歌手甲']);
    expect(metadata.composers, ['作曲甲']);
    expect(metadata.lyricists, ['作词甲']);
    expect(metadata.arrangers, ['编曲甲']);
  });

  test('缺少标题和歌手时回退到文件名且不制造未知字段', () {
    const metadata = TrackMetadata();

    expect(metadata.displayTitle('01 - Intro.flac'), '01 - Intro');
    expect(metadata.credits, isEmpty);
    expect(metadata.artistLine, isNull);
  });

  test('把解析器结果转换成展示模型并保留封面和音频规格', () {
    final parsed = audio.AudioMetadata(
      format: const audio.Format(
        duration: 185.25,
        bitrate: 921600,
        sampleRate: 96000,
        bitsPerSample: 24,
        numberOfChannels: 2,
      ),
      native: const {},
      common: const audio.CommonTags(
        track: audio.TrackNo(no: 3, of: 12),
        disk: audio.TrackNo(no: 1, of: 1),
        movementIndex: audio.TrackNo(),
        title: '星空',
        artists: ['歌手甲', '歌手乙'],
        album: '夜航',
        albumartist: '歌手甲',
        composer: ['作曲甲'],
        arranger: ['编曲甲'],
        lyricist: ['作词甲'],
        year: 2026,
        genre: ['流行'],
        picture: [
          audio.Picture(format: 'image/jpeg', data: [1, 2, 3]),
        ],
      ),
      quality: const audio.QualityInformation(),
    );

    final metadata = TrackMetadata.fromAudioMetadata(parsed);

    expect(metadata.title, '星空');
    expect(metadata.performers, ['歌手甲', '歌手乙']);
    expect(metadata.trackNumber, 3);
    expect(metadata.duration, const Duration(milliseconds: 185250));
    expect(metadata.sampleRate, 96000);
    expect(metadata.bitRate, 921600);
    expect(metadata.bitDepth, 24);
    expect(metadata.channels, 2);
    expect(metadata.artwork, [1, 2, 3]);
    expect(metadata.artworkMimeType, 'image/jpeg');
  });

  test('公共字段缺失时从原始标签补齐编曲和作词', () {
    const parsed = audio.AudioMetadata(
      format: audio.Format(),
      native: {
        'vorbis': [
          audio.Tag(id: 'ARRANGEMENT', value: '编曲乙'),
          audio.Tag(id: 'WRITER', value: '作词乙'),
        ],
      },
      common: audio.CommonTags(
        track: audio.TrackNo(),
        disk: audio.TrackNo(),
        movementIndex: audio.TrackNo(),
      ),
      quality: audio.QualityInformation(),
    );

    final metadata = TrackMetadata.fromAudioMetadata(parsed);

    expect(metadata.arrangers, ['编曲乙']);
    expect(metadata.lyricists, ['作词乙']);
  });
}
