import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/metadata/track_metadata.dart';
import 'package:himusic/sources/music_source.dart';
import 'package:himusic/util/track_sort.dart';

const _a = MusicEntry(
  path: 'a.flac',
  name: 'a.flac',
  isDirectory: false,
  size: 100,
);
const _b = MusicEntry(
  path: 'b.flac',
  name: 'b.flac',
  isDirectory: false,
  size: 300,
);
const _c = MusicEntry(
  path: 'c.flac',
  name: 'c.flac',
  isDirectory: false,
  size: 200,
);
const _dir = MusicEntry(
  path: 'sub',
  name: 'sub',
  isDirectory: true,
  size: 0,
);

TrackMetadata? _meta(MusicEntry entry) => switch (entry.path) {
  'a.flac' => const TrackMetadata(
    title: '甲',
    performers: ['张三'],
    album: '专辑A',
    duration: Duration(minutes: 3),
  ),
  'b.flac' => const TrackMetadata(
    title: '乙',
    performers: ['李四'],
    album: '专辑B',
    duration: Duration(minutes: 5),
  ),
  'c.flac' => const TrackMetadata(
    title: '丙',
    performers: ['张三'],
    album: '专辑A',
    duration: Duration(minutes: 4),
  ),
  _ => null,
};

void main() {
  test('字段为 null 时保持原顺序（返回副本）', () {
    final result = applyTrackSort(
      entries: const [_b, _a, _c],
      field: null,
      ascending: true,
      metadataFor: _meta,
    );
    expect(result, const [_b, _a, _c]);
    expect(identical(result, const [_b, _a, _c]), isFalse);
  });

  test('目录条目固定置顶，不参与排序', () {
    final result = applyTrackSort(
      entries: const [_b, _dir, _a],
      field: TrackSortField.name,
      ascending: true,
      metadataFor: _meta,
    );
    expect(result.first, _dir);
    expect(result.sublist(1), const [_a, _b]);
  });

  test('按文件名排序（忽略大小写与扩展名）', () {
    const zeta = MusicEntry(
      path: 'Z.flac',
      name: 'Z.flac',
      isDirectory: false,
      size: 1,
    );
    final result = applyTrackSort(
      entries: const [zeta, _a],
      field: TrackSortField.name,
      ascending: true,
      metadataFor: _meta,
    );
    expect(result, const [_a, zeta]);
  });

  test('按标题排序，元数据缺失时回退文件名', () {
    final result = applyTrackSort(
      entries: const [_b, _a, _c],
      field: TrackSortField.title,
      ascending: true,
      metadataFor: _meta,
    );
    expect(result, const [_c, _b, _a]); // 丙 < 乙 < 甲（Unicode 码点）
    expect(
      applyTrackSort(
        entries: const [_b, _c],
        field: TrackSortField.title,
        ascending: true,
        metadataFor: (entry) => null,
      ),
      const [_b, _c], // 无标签时按文件名
    );
  });

  test('按艺术家排序，缺失艺术家排后（升序与降序一致）', () {
    final asc = applyTrackSort(
      entries: const [_b, _a, _c],
      field: TrackSortField.artist,
      ascending: true,
      metadataFor: _meta,
    );
    // 张三（a、c）在前，李四（b）在后
    expect(asc, const [_a, _c, _b]);

    final desc = applyTrackSort(
      entries: const [_b, _a, _c],
      field: TrackSortField.artist,
      ascending: false,
      metadataFor: _meta,
    );
    expect(desc, const [_b, _a, _c]); // 李四在前，张三组内保持原相对顺序

    final missing = applyTrackSort(
      entries: const [_b, _c],
      field: TrackSortField.artist,
      ascending: true,
      metadataFor: (entry) => null,
    );
    expect(missing, const [_b, _c]); // 无艺术家保持原相对顺序，不抛错
  });

  test('按专辑排序', () {
    final result = applyTrackSort(
      entries: const [_b, _a, _c],
      field: TrackSortField.album,
      ascending: true,
      metadataFor: _meta,
    );
    expect(result, const [_a, _c, _b]); // 专辑A（a、c）在专辑B（b）前
  });

  test('按时长排序，缺失时长排后（两种方向都排后）', () {
    const noDuration = MusicEntry(
      path: 'd.flac',
      name: 'd.flac',
      isDirectory: false,
      size: 10,
    );
    final asc = applyTrackSort(
      entries: const [noDuration, _c, _a, _b],
      field: TrackSortField.duration,
      ascending: true,
      metadataFor: (entry) => entry.path == 'd.flac' ? null : _meta(entry),
    );
    expect(asc, const [_a, _c, _b, noDuration]);

    final desc = applyTrackSort(
      entries: const [noDuration, _c, _a, _b],
      field: TrackSortField.duration,
      ascending: false,
      metadataFor: (entry) => entry.path == 'd.flac' ? null : _meta(entry),
    );
    expect(desc, const [_b, _c, _a, noDuration]);
  });

  test('按大小排序', () {
    final result = applyTrackSort(
      entries: const [_b, _a, _c],
      field: TrackSortField.size,
      ascending: true,
      metadataFor: _meta,
    );
    expect(result, const [_a, _c, _b]);
    expect(
      applyTrackSort(
        entries: const [_b, _a, _c],
        field: TrackSortField.size,
        ascending: false,
        metadataFor: _meta,
      ),
      const [_b, _c, _a],
    );
  });

  test('排序稳定：同键条目保持原相对顺序', () {
    final result = applyTrackSort(
      entries: const [_a, _c], // 同为张三/专辑A，但时长不同
      field: TrackSortField.artist,
      ascending: true,
      metadataFor: _meta,
    );
    expect(result, const [_a, _c]);
  });
}
