import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/util/queue_math.dart';

void main() {
  test('未在播放时移除返回 null', () {
    expect(mapIndexAfterRemoval(2, null), isNull);
  });

  test('移除项在当前播放项之后，索引不变', () {
    expect(mapIndexAfterRemoval(3, 2), 2);
  });

  test('移除当前播放项，原位置变为下一首', () {
    expect(mapIndexAfterRemoval(2, 2), 2);
  });

  test('移除当前播放项之前的项，索引减一', () {
    expect(mapIndexAfterRemoval(1, 3), 2);
    expect(mapIndexAfterRemoval(0, 1), 0);
  });

  test('移除第一项且正播放第一项', () {
    expect(mapIndexAfterRemoval(0, 0), 0);
  });
}
