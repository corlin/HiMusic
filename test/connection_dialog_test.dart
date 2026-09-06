import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/main.dart';
import 'package:himusic/sources/smb_source.dart';

void main() {
  testWidgets('连接表单返回具名配置并支持键盘确认', (tester) async {
    SmbConnectionRequest? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            autofocus: true,
            onPressed: () async {
              result = await showDialog<SmbConnectionRequest>(
                context: context,
                builder: (_) => const ConnectionDialog(),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '192.168.1.1');
    await tester.enterText(fields.at(1), 'Music');
    await tester.enterText(fields.at(2), '音乐/专辑');
    await tester.enterText(fields.at(3), 'listener');
    await tester.enterText(fields.at(4), 'test-only-secret');
    await tester.ensureVisible(find.text('连接'));
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(result?.host, '192.168.1.1');
    expect(result?.share, 'Music');
    expect(result?.directory, '音乐/专辑');
    expect(result?.user, 'listener');
    expect(result?.password, 'test-only-secret');
  });
}
