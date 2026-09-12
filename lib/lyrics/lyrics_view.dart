import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../metadata/track_metadata.dart';
import '../theme.dart';
import '../util/format.dart';
import 'lrclib_client.dart';
import 'lyrics_controller.dart';
import 'lyrics_document.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.controller,
    required this.onSeek,
    this.onFetchLyrics,
  });

  final LyricsController controller;
  final ValueChanged<TimedLyricLine> onSeek;

  /// 点击「获取歌词」时调用，返回当前歌曲的元数据。
  /// 返回 null 表示无法获取（如未播放）。
  final Future<TrackMetadata?> Function()? onFetchLyrics;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const _lineExtent = 64.0;
  final _scrollController = ScrollController();
  Timer? _resumeTimer;
  bool _following = true;
  int _lastLine = -2;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final line = widget.controller.currentLineIndex;
    if (_following && line >= 0 && line != _lastLine) {
      _lastLine = line;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(line));
    }
  }

  void _scrollTo(int index) {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final target = (index * _lineExtent - viewport / 2 + _lineExtent / 2).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _userScrolled() {
    _following = false;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _following = true);
      final line = widget.controller.currentLineIndex;
      if (line >= 0) _scrollTo(line);
    });
    setState(() {});
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    widget.controller.removeListener(_changed);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    // 有候选歌词时弹出选择器
    final choices = controller.pendingChoices;
    if (choices != null && choices.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showChoices(choices));
    }
    return switch (controller.status) {
      LyricsStatus.idle || LyricsStatus.loading => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在读取歌词…'),
          ],
        ),
      ),
      LyricsStatus.fetching => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在联网获取歌词…'),
          ],
        ),
      ),
      LyricsStatus.empty => _Message(
        icon: Icons.lyrics_outlined,
        text: '这首歌没有本地歌词',
        action: widget.onFetchLyrics != null
            ? TextButton.icon(
          onPressed: _handleFetch,
          icon: const Icon(Icons.cloud_download_rounded, size: 18),
          label: const Text('联网获取'),
        )
            : null,
      ),
      LyricsStatus.error => _Message(
        icon: Icons.error_outline_rounded,
        text: '歌词读取失败',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: controller.retry, child: const Text('重试')),
            if (widget.onFetchLyrics != null)
              TextButton.icon(
                onPressed: _handleFetch,
                icon: const Icon(Icons.cloud_download_rounded, size: 18),
                label: const Text('联网获取'),
              ),
          ],
        ),
      ),
      LyricsStatus.ready => _content(controller.document!),
    };
  }

  Future<void> _handleFetch() async {
    final metadata = await widget.onFetchLyrics?.call();
    if (metadata == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法获取歌曲信息，请先播放歌曲')),
        );
      }
      return;
    }
    await widget.controller.fetchOnline(metadata);
  }

  void _showChoices(List<LrclibLyrics> choices) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '选择匹配的歌词',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: choices.length,
                itemBuilder: (context, index) {
                  final item = choices[index];
                  return ListTile(
                    leading: const Icon(Icons.music_note_rounded),
                    title: Text(item.name ?? '未知歌曲'),
                    subtitle: Text(
                      [item.artistName, item.albumName]
                          .where((s) => s != null && s.isNotEmpty)
                          .join(' · '),
                    ),
                    trailing: item.hasSynced
                        ? const Icon(Icons.timer_rounded, size: 16, color: Colors.green)
                        : const Icon(Icons.article_rounded, size: 16, color: Colors.grey),
                    onTap: () {
                      Navigator.pop(context);
                      widget.controller.applyChoice(item);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(LyricsDocument document) {
    if (!document.hasTimedLines) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: SelectableText(
          document.plainText ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            height: 1.9,
            color: Colors.white70,
          ),
        ),
      );
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle) {
              _userScrolled();
            }
            return false;
          },
          child: ListView.builder(
            key: const Key('timed-lyrics-list'),
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 80),
            itemExtent: _lineExtent,
            itemCount: document.lines.length,
            itemBuilder: (context, index) {
              final line = document.lines[index];
              final active = index == widget.controller.currentLineIndex;
              return Semantics(
                label: active
                    ? '当前歌词：${line.text}'
                    : '跳转到 ${formatDuration(line.timestamp)}',
                button: true,
                excludeSemantics: true,
                child: InkWell(
                  key: ValueKey('lyric-line-$index'),
                  onTap: () => widget.onSeek(line),
                  child: Center(
                    child: Text(
                      line.text,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: active ? 23 : 17,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? AppColors.accent : Colors.white54,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (!_following)
          Positioned(
            right: 12,
            bottom: 12,
            child: FilledButton.tonalIcon(
              onPressed: () {
                setState(() => _following = true);
                _scrollTo(widget.controller.currentLineIndex);
              },
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('回到当前歌词'),
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: Colors.white38),
        const SizedBox(height: 12),
        Text(text),
        ?action,
      ],
    ),
  );
}
