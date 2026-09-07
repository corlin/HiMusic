import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/main.dart';

void main() {
  testWidgets('手机首页无溢出并提供本地音乐入口', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const HiMusicApp());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('选择本地音乐'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
