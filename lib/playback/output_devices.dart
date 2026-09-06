import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OutputDevice {
  const OutputDevice(this.id, this.name, this.selected);
  final int id;
  final String name;
  final bool selected;
}

class OutputDevices {
  static const channel = MethodChannel('app.himusic/output');
  static Future<List<OutputDevice>> list() async {
    final values = await channel.invokeListMethod<dynamic>('list');
    return (values ?? [])
        .map(
          (v) => OutputDevice(
            v['id'] as int,
            v['name'] as String,
            v['selected'] as bool,
          ),
        )
        .toList();
  }

  static Future<void> select(int id) =>
      channel.invokeMethod<void>('select', id);
  static Future<void> showSystemPicker() async {
    if (Platform.isWindows) {
      final result = await Process.run('explorer.exe', ['ms-settings:sound']);
      if (result.exitCode != 0) {
        throw PlatformException(
          code: 'settings',
          message: '请在 Windows 设置中选择音频输出。',
        );
      }
    } else {
      await channel.invokeMethod<void>('showPicker');
    }
  }
}

class OutputDeviceDialog extends StatefulWidget {
  const OutputDeviceDialog({super.key});
  @override
  State<OutputDeviceDialog> createState() => _OutputDeviceDialogState();
}

class _OutputDeviceDialogState extends State<OutputDeviceDialog> {
  List<OutputDevice> devices = [];
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await OutputDevices.list();
      if (mounted) setState(() => devices = result);
    } catch (_) {
      if (mounted) setState(() => error = '无法读取输出设备，请重试。');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> select(OutputDevice device) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await OutputDevices.select(device.id);
      await refresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '切换失败，设备可能已断开，请刷新后重试。';
        });
      }
    }
  }

  Future<void> systemPicker() async {
    try {
      await OutputDevices.showSystemPicker();
    } catch (_) {
      if (mounted) setState(() => error = '系统暂不支持此入口，请到声音或蓝牙设置中选择输出设备。');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('音频输出设备'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Platform.isMacOS || Platform.isWindows
                  ? '选择系统音频输出，会影响其他应用的声音。'
                  : '选择系统可用的扬声器、耳机或无线音频设备。',
            ),
            const SizedBox(height: 16),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (Platform.isMacOS) ...[
              if (!loading && devices.isEmpty) const Text('未发现输出设备'),
              for (final device in devices)
                ListTile(
                  title: Text(device.name),
                  leading: Icon(
                    device.selected ? Icons.check_circle : Icons.speaker,
                  ),
                  selected: device.selected,
                  onTap: loading ? null : () => select(device),
                ),
            ] else if (Platform.isIOS)
              const SizedBox(
                height: 64,
                width: 360,
                child: UiKitView(viewType: 'app.himusic/route-picker'),
              )
            else
              FilledButton.icon(
                onPressed: systemPicker,
                icon: const Icon(Icons.speaker_group),
                label: Text(Platform.isWindows ? '打开系统声音设置' : '选择系统输出'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (Platform.isMacOS)
        TextButton(
          onPressed: loading ? null : refresh,
          child: const Text('刷新'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('完成'),
      ),
    ],
  );
}
