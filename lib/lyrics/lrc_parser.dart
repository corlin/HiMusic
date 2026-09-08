import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_codec/charset_codec.dart';

import 'lyrics_document.dart';

class LrcParser {
  static final _timestamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _info = RegExp(
    r'^\[(?:ar|ti|al|by|re|ve|length):.*\]\s*$',
    caseSensitive: false,
  );
  static final _offset = RegExp(
    r'^\[offset:([+-]?\d+)\]\s*$',
    caseSensitive: false,
  );

  LyricsDocument parse(Uint8List bytes) {
    if (bytes.isEmpty) throw const FormatException('没有可显示的歌词');
    var text = _decode(bytes);
    if (text.startsWith('\ufeff')) text = text.substring(1);
    final sourceLines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    var offsetMs = 0;
    for (final line in sourceLines) {
      final match = _offset.firstMatch(line.trim());
      if (match != null) offsetMs = int.parse(match.group(1)!);
    }

    final timed = <({TimedLyricLine line, int order})>[];
    final plain = <String>[];
    var order = 0;
    for (final raw in sourceLines) {
      final trimmed = raw.trim();
      if (_info.hasMatch(trimmed) || _offset.hasMatch(trimmed)) continue;
      final matches = _timestamp.allMatches(raw).toList();
      if (matches.isEmpty) {
        plain.add(raw);
        continue;
      }
      final lyric = raw.replaceAll(_timestamp, '').trim();
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fraction = match.group(3);
        final fractionMs = fraction == null
            ? 0
            : int.parse(fraction.padRight(3, '0').substring(0, 3));
        final rawMs = (minutes * 60 + seconds) * 1000 + fractionMs + offsetMs;
        timed.add((
          line: TimedLyricLine(
            timestamp: Duration(milliseconds: rawMs < 0 ? 0 : rawMs),
            text: lyric,
          ),
          order: order++,
        ));
      }
    }
    timed.sort((a, b) {
      final byTime = a.line.timestamp.compareTo(b.line.timestamp);
      return byTime != 0 ? byTime : a.order.compareTo(b.order);
    });
    if (timed.isNotEmpty) {
      return LyricsDocument(
        source: LyricsSource.sidecarLrc,
        lines: List.unmodifiable(timed.map((item) => item.line)),
        offset: Duration(milliseconds: offsetMs),
      );
    }
    final plainText = _trimBlankEdges(plain).join('\n');
    if (plainText.trim().isEmpty) {
      throw const FormatException('没有可显示的歌词');
    }
    return LyricsDocument(
      source: LyricsSource.sidecarLrc,
      plainText: plainText,
      offset: Duration(milliseconds: offsetMs),
    );
  }

  String _decode(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return decodeBytes(bytes, encoding: 'gb18030');
    }
  }

  List<String> _trimBlankEdges(List<String> lines) {
    var start = 0;
    var end = lines.length;
    while (start < end && lines[start].trim().isEmpty) {
      start++;
    }
    while (end > start && lines[end - 1].trim().isEmpty) {
      end--;
    }
    return lines.sublist(start, end);
  }
}
