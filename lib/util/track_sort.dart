/// 曲目表排序：目录条目固定置顶，音频条目按字段排序。
library;

import '../metadata/track_metadata.dart';
import '../sources/music_source.dart';
import 'format.dart';

/// 可排序字段。
enum TrackSortField { name, title, artist, album, duration, size }

/// 应用排序并返回新列表；[field] 为 null 时保持传入顺序。
///
/// 规则：
/// - 目录条目永远排在音频之前（无论字段与方向）；
/// - 元数据缺失的音频条目按"空值排后"处理（两种方向都排后）；
/// - 排序不稳定时用原列表下标兜底，保证稳定。
List<MusicEntry> applyTrackSort({
  required List<MusicEntry> entries,
  required TrackSortField? field,
  required bool ascending,
  required TrackMetadata? Function(MusicEntry entry) metadataFor,
}) {
  if (field == null) return List.of(entries);
  final dirs = <MusicEntry>[];
  final audio = <MusicEntry>[];
  for (final entry in entries) {
    (entry.isDirectory ? dirs : audio).add(entry);
  }
  final indexed = <({MusicEntry entry, int index})>[
    for (var i = 0; i < audio.length; i++) (entry: audio[i], index: i),
  ];
  indexed.sort((a, b) {
    final result = _compare(field, a.entry, b.entry, metadataFor, ascending);
    if (result != 0) return result;
    return a.index.compareTo(b.index); // 排序前下标兜底，保证稳定
  });
  return [...dirs, ...indexed.map((item) => item.entry)];
}

int _compare(
  TrackSortField field,
  MusicEntry a,
  MusicEntry b,
  TrackMetadata? Function(MusicEntry) metadataFor,
  bool ascending,
) {
  final ma = metadataFor(a);
  final mb = metadataFor(b);
  switch (field) {
    case TrackSortField.name:
      return _dir(_textCompare(stripExtension(a.name), stripExtension(b.name)), ascending);
    case TrackSortField.title:
      return _nullableTextCompare(
        _titleOf(a, ma),
        _titleOf(b, mb),
        ascending,
      );
    case TrackSortField.artist:
      return _nullableTextCompare(ma?.artistLine, mb?.artistLine, ascending);
    case TrackSortField.album:
      return _nullableTextCompare(ma?.album, mb?.album, ascending);
    case TrackSortField.duration:
      return _nullableCompare(ma?.duration, mb?.duration, ascending);
    case TrackSortField.size:
      return _nullableCompare(a.size, b.size, ascending);
  }
}

int _dir(int value, bool ascending) => ascending ? value : -value;

String _titleOf(MusicEntry entry, TrackMetadata? metadata) =>
    metadata?.title?.trim().isNotEmpty == true
        ? metadata!.title!.trim()
        : stripExtension(entry.name);

int _textCompare(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

int _nullableTextCompare(String? a, String? b, bool ascending) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // 空值排后（与方向无关）
  if (b == null) return -1;
  return _dir(_textCompare(a, b), ascending);
}

int _nullableCompare<T extends Comparable<T>>(T? a, T? b, bool ascending) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // 空值排后（与方向无关）
  if (b == null) return -1;
  return _dir(a.compareTo(b), ascending);
}
