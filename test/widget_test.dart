import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himusic/main.dart';

void main() {
  testWidgets('连接表单要求主机和共享名称，密码不明文展示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ConnectionDialog(),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(find.text('请填写此项'), findsNWidgets(2));
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.last.obscureText, isTrue);
  });
}
