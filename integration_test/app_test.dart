import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:himusic/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('正常入口显示音乐库并支持键盘打开共享表单', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('家里的音乐，随时听。'), findsOneWidget);
    expect(find.text('连接 SMB 共享硬盘'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('主机 IP 或名称'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('电视布局'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('标准布局'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
