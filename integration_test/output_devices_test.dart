import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:himusic/playback/output_devices.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('读取实际 macOS 输出设备并确认当前输出，不切换到其他设备', (tester) async {
    final devices = await OutputDevices.list();
    expect(devices, isNotEmpty);
    final current = devices.singleWhere((device) => device.selected);
    expect(current.name, isNotEmpty);
    await OutputDevices.select(current.id);
    expect(
      (await OutputDevices.list()).singleWhere((device) => device.selected).id,
      current.id,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OutputDeviceDialog())),
    );
    await tester.pumpAndSettle();
    expect(find.text(current.name), findsOneWidget);
    expect(find.text('选择系统音频输出，会影响其他应用的声音。'), findsOneWidget);
  });
}
