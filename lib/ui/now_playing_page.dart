import 'package:flutter/material.dart';

import '../lyrics/lyrics_view.dart';
import '../metadata/track_metadata.dart';
import '../playback/player_controller.dart';
import '../theme.dart';
import '../util/format.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({
    super.key,
    required this.controller,
    this.showLyrics = false,
  });
  final PlayerController controller;
  final bool showLyrics;

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  late bool showLyrics = widget.showLyrics;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final current = widget.controller.current;
      final metadata = current == null
          ? null
          : widget.controller.metadata.metadataFor(current);
      return Scaffold(
        appBar: AppBar(title: const Text('正在播放')),
        body: current == null
            ? const Center(child: Text('尚未播放音乐'))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final lyrics = LyricsView(
                    controller: widget.controller.lyrics,
                    onSeek: widget.controller.seekToLyric,
                    onFetchLyrics: () async {
                      final entry = widget.controller.current;
                      if (entry == null) return null;
                      final meta = widget.controller.metadata.metadataFor(entry);
                      if (meta != null) return meta;
                      // 元数据尚未扫描完成，用文件名构造基本信息
                      return TrackMetadata(title: stripExtension(entry.name));
                    },
                  );
                  final details = _ArtworkDetails(
                    entryName: current.name,
                    metadata: metadata,
                  );
                  if (constraints.maxWidth >= 980) {
                    return Row(
                      children: [
                        Expanded(child: details),
                        const VerticalDivider(width: 1),
                        Expanded(child: lyrics),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              icon: Icon(Icons.album_rounded),
                              label: Text('封面'),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.lyrics_rounded),
                              label: Text('歌词'),
                            ),
                          ],
                          selected: {showLyrics},
                          onSelectionChanged: (value) =>
                              setState(() => showLyrics = value.first),
                        ),
                      ),
                      Expanded(child: showLyrics ? lyrics : details),
                    ],
                  );
                },
              ),
      );
    },
  );
}

class _ArtworkDetails extends StatelessWidget {
  const _ArtworkDetails({required this.entryName, required this.metadata});
  final String entryName;
  final TrackMetadata? metadata;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: metadata?.artwork == null
                ? Container(
                    width: 280,
                    height: 280,
                    color: AppColors.field,
                    child: const Icon(
                      Icons.album_rounded,
                      size: 110,
                      color: Colors.white38,
                    ),
                  )
                : Image.memory(
                    metadata!.artwork!,
                    width: 280,
                    height: 280,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(height: 24),
          Text(
            metadata?.displayTitle(entryName) ?? stripExtension(entryName),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (metadata?.artistLine != null) ...[
            const SizedBox(height: 8),
            Text(
              metadata!.artistLine!,
              style: const TextStyle(color: Colors.white60, fontSize: 17),
            ),
          ],
          if (metadata?.album != null) ...[
            const SizedBox(height: 5),
            Text(
              metadata!.album!,
              style: const TextStyle(color: Colors.white38),
            ),
          ],
        ],
      ),
    ),
  );
}
