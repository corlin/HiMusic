import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_codec/charset_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/lyrics/lrc_parser.dart';

void main() {
  test('解析多时间标签、精度并应用偏移', () {
    final document = LrcParser().parse(
      Uint8List.fromList(
        utf8.encode(
          '\u{feff}[ar:歌手]\n[offset:-500]\n[00:01][00:02.34]你好\n[01:02.345]世界',
        ),
      ),
    );
    expect(document.lines.map((line) => line.timestamp), [
      const Duration(milliseconds: 500),
      const Duration(milliseconds: 1840),
      const Duration(milliseconds: 61845),
    ]);
    expect(document.lines.map((line) => line.text), ['你好', '你好', '世界']);
  });

  test('负时间截断为零且相同时间保持原顺序', () {
    final document = LrcParser().parse(
      Uint8List.fromList(
        utf8.encode('[offset:-2000]\n[00:01]甲\n[00:01]乙'),
      ),
    );
    expect(document.lines.map((line) => line.timestamp), [
      Duration.zero,
      Duration.zero,
    ]);
    expect(document.lines.map((line) => line.text), ['甲', '乙']);
  });

  test('无时间标签时返回纯文本并移除信息标签', () {
    final document = LrcParser().parse(
      Uint8List.fromList(utf8.encode('[ti:夜航]\n第一句\n\n第二句')),
    );
    expect(document.lines, isEmpty);
    expect(document.plainText, '第一句\n\n第二句');
  });

  test('严格 UTF-8 失败后以 GB18030 解码', () {
    final bytes = Uint8List.fromList(
      encodeString('[00:01]中文歌词', encoding: 'gb18030'),
    );
    expect(LrcParser().parse(bytes).lines.single.text, '中文歌词');
  });

  test('空文件和只有信息标签均拒绝', () {
    expect(() => LrcParser().parse(Uint8List(0)), throwsFormatException);
    expect(
      () => LrcParser().parse(Uint8List.fromList(utf8.encode('[ar:歌手]'))),
      throwsFormatException,
    );
  });
}
