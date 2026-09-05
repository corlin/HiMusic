import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'playback/player_controller.dart';
import 'sources/local_source.dart';
import 'sources/smb_source.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
  runApp(const HiMusicApp());
}

class HiMusicApp extends StatelessWidget {
  const HiMusicApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HiMusic',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffb7d89c),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff141916),
      useMaterial3: true,
    ),
    home: const LibraryPage(),
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final controller = PlayerController();
  bool tvMode = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> addSmb() async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => const ConnectionDialog(),
    );
    if (values == null || !mounted) return;
    await controller.connect(
      () => SmbSource.connect(
        host: values[0],
        share: values[1],
        user: values[3],
        password: values[4],
      ),
      values[2],
    );
  }

  Future<void> addLocal() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '打开音乐目录');
      if (path != null) {
        await controller.connect(() => LocalSource.open(path), '');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('此平台暂不能选择目录，请使用 SMB 共享。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      return PopScope(
        canPop: c.directory.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !c.busy) c.up();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('HiMusic'),
            actions: [
              IconButton(
                tooltip: tvMode ? '标准布局' : '电视布局',
                onPressed: () => setState(() => tvMode = !tvMode),
                icon: Icon(tvMode ? Icons.desktop_windows : Icons.tv),
              ),
              IconButton(
                tooltip: '连接共享硬盘',
                onPressed: c.busy ? null : addSmb,
                icon: const Icon(Icons.add_link),
              ),
            ],
          ),
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: tvMode ? 40 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  '家里的音乐，随时听。',
                  style: TextStyle(
                    fontSize: tvMode ? 36 : 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  c.source?.label ?? '连接共享硬盘，或打开本地音乐目录',
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 20),
                if (c.busy) const LinearProgressIndicator(),
                if (c.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(
                          c.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: c.busy ? null : c.retry,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                if (c.source != null)
                  Row(
                    children: [
                      IconButton(
                        tooltip: '上一级',
                        onPressed: c.busy || c.directory.isEmpty ? null : c.up,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      Expanded(
                        child: Text(
                          c.directory.isEmpty ? '共享根目录' : c.directory,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: '刷新目录',
                        onPressed: c.busy ? null : () => c.browse(c.directory),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                Expanded(
                  child: c.source == null
                      ? Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.library_music_outlined,
                                  size: 72,
                                  color: Color(0xffb7d89c),
                                ),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  autofocus: true,
                                  onPressed: c.busy ? null : addSmb,
                                  icon: const Icon(Icons.router_outlined),
                                  label: const Text('连接 SMB 共享硬盘'),
                                ),
                                if (Platform.isMacOS ||
                                    Platform.isWindows ||
                                    Platform.isLinux)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: OutlinedButton.icon(
                                      onPressed: c.busy ? null : addLocal,
                                      icon: const Icon(Icons.folder_open),
                                      label: const Text('打开本地目录'),
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                const Text(
                                  '原文件播放 · 个人设备独立队列',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                        )
                      : c.entries.isEmpty
                      ? const Center(child: Text('此目录暂无支持的音乐文件或子目录'))
                      : ListView.builder(
                          itemCount: c.entries.length,
                          itemBuilder: (context, index) {
                            final entry = c.entries[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: ListTile(
                                autofocus: index == 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusColor: const Color(0xff42543b),
                                selectedTileColor: const Color(0xff253223),
                                selected: c.current?.path == entry.path,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: tvMode ? 12 : 3,
                                ),
                                leading: Icon(
                                  entry.isDirectory
                                      ? Icons.folder_outlined
                                      : Icons.music_note,
                                ),
                                title: Text(
                                  entry.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: tvMode ? 22 : 16),
                                ),
                                subtitle: entry.isDirectory
                                    ? null
                                    : Text(
                                        '${entry.extension.toUpperCase()} · ${(entry.size / 1048576).toStringAsFixed(1)} MB',
                                      ),
                                trailing: Icon(
                                  entry.isDirectory
                                      ? Icons.chevron_right
                                      : Icons.play_arrow,
                                ),
                                onTap: c.busy
                                    ? null
                                    : () => entry.isDirectory
                                          ? c.browse(entry.path)
                                          : c.playEntry(entry),
                              ),
                            );
                          },
                        ),
                ),
                PlayerBar(controller: c),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.controller});
  final PlayerController controller;
  String time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.current == null) return const SizedBox(height: 20);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xff222b24),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.current!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            const Text(
              '原文件 · 设备输出规格未知',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            StreamBuilder<Duration?>(
              stream: c.player.durationStream,
              builder: (context, duration) => StreamBuilder<Duration>(
                stream: c.player.positionStream,
                builder: (context, position) {
                  final total = duration.data ?? Duration.zero;
                  final current = position.data ?? Duration.zero;
                  return Row(
                    children: [
                      Text(time(current)),
                      Expanded(
                        child: Slider(
                          value: current.inMilliseconds.toDouble().clamp(
                            0,
                            total.inMilliseconds.toDouble(),
                          ),
                          max: total.inMilliseconds > 0
                              ? total.inMilliseconds.toDouble()
                              : 1,
                          onChanged: c.busy || total == Duration.zero
                              ? null
                              : (v) =>
                                    c.seek(Duration(milliseconds: v.round())),
                        ),
                      ),
                      Text(time(total)),
                    ],
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '上一首',
                  onPressed: c.busy || !c.player.hasPrevious
                      ? null
                      : () => c.skip(false),
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton.filled(
                  tooltip: c.player.playing ? '暂停' : '播放',
                  onPressed: c.busy ? null : c.toggle,
                  icon: Icon(c.player.playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: '下一首',
                  onPressed: c.busy || !c.player.hasNext
                      ? null
                      : () => c.skip(true),
                  icon: const Icon(Icons.skip_next),
                ),
                IconButton(
                  tooltip: '循环：${c.player.loopMode.name}',
                  onPressed: c.busy ? null : c.cycleLoop,
                  icon: Icon(
                    c.player.loopMode == LoopMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color: c.player.loopMode == LoopMode.off
                        ? Colors.white38
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});
  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final fields = List.generate(5, (_) => TextEditingController());
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    for (final field in fields) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('连接共享硬盘'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('填写路由器文件共享页面中的地址和名称。密码仅用于本次连接。'),
              const SizedBox(height: 16),
              for (var i = 0; i < fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: fields[i],
                    autofocus: i == 0,
                    obscureText: i == 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: [
                        '主机 IP 或名称',
                        '共享名称',
                        '音乐目录（可选）',
                        '用户名（可选）',
                        '密码（可选）',
                      ][i],
                    ),
                    validator: (v) => i < 2 && (v == null || v.trim().isEmpty)
                        ? '请填写此项'
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, fields.map((f) => f.text).toList());
          }
        },
        child: const Text('连接'),
      ),
    ],
  );
}
