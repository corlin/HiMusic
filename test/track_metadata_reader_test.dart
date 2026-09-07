import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/metadata/track_metadata_reader.dart';
import 'package:himusic/sources/local_source.dart';

void main() {
  test('通过音乐来源按需读取 FLAC 元数据', () async {
    final fixture = File('test/fixtures/tone-24-96000.flac');
    final source = await LocalSource.open(fixture.parent.path);
    addTearDown(source.close);
    final entry = (await source.list(''))
        .singleWhere((item) => item.name == fixture.uri.pathSegments.last);
    final reader = TrackMetadataReader();

    final metadata = await reader.read(source, entry);

    expect(metadata.sampleRate, 96000);
    expect(metadata.bitDepth, 24);
    expect(metadata.channels, 2);
    expect(metadata.duration, greaterThan(Duration.zero));
  });
}
