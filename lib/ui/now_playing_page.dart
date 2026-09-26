import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

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
            : SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final features = MediaQuery.displayFeaturesOf(context);
                    final activeFold = features.where(
                      (feature) =>
                          (feature.type == DisplayFeatureType.fold ||
                              feature.type == DisplayFeatureType.hinge) &&
                          feature.state ==
                              DisplayFeatureState.postureHalfOpened,
                    );
                    final horizontalFold = activeFold.any(
                      (feature) => feature.bounds.width > feature.bounds.height,
                    );
                    final verticalFolds = activeFold
                        .where(
                          (feature) =>
                              feature.bounds.height > feature.bounds.width,
                        )
                        .toList();
                    final verticalFoldWidth = verticalFolds.fold<double>(
                      0,
                      (width, feature) => math.max(width, feature.bounds.width),
                    );
                    final lyrics = LyricsView(
                      controller: widget.controller.lyrics,
                      onSeek: widget.controller.seekToLyric,
                      onFetchLyrics: () async {
                        final entry = widget.controller.current;
                        if (entry == null) return null;
                        final meta = widget.controller.metadata.metadataFor(
                          entry,
                        );
                        return meta ??
                            TrackMetadata(title: stripExtension(entry.name));
                      },
                    );
                    final details = _ArtworkDetails(
                      entryName: current.name,
                      metadata: metadata,
                    );
                    if (verticalFolds.isNotEmpty &&
                        constraints.maxWidth >= 600 &&
                        constraints.maxHeight >= 460) {
                      return Row(
                        key: const Key('now-playing-book-pose'),
                        children: [
                          Expanded(
                            child: _BookPane(
                              paneKey: const Key('book-record-page'),
                              label: '唱片页',
                              icon: Icons.album_rounded,
                              footer: _TransportDock(
                                controller: widget.controller,
                              ),
                              child: details,
                            ),
                          ),
                          SizedBox(
                            width: math.max(32.0, verticalFoldWidth + 16),
                          ),
                          Expanded(
                            child: _BookPane(
                              paneKey: const Key('book-lyrics-page'),
                              label: '歌词页',
                              icon: Icons.lyrics_rounded,
                              child: lyrics,
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(
                          child:
                              constraints.maxWidth >= 600 &&
                                  constraints.maxHeight >= 460 &&
                                  !horizontalFold
                              ? Row(
                                  key: const Key('now-playing-dual-pane'),
                                  children: [
                                    Expanded(child: details),
                                    const SizedBox(width: 24),
                                    Expanded(child: lyrics),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8),
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
                                        onSelectionChanged: (value) => setState(
                                          () => showLyrics = value.first,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: showLyrics ? lyrics : details,
                                    ),
                                  ],
                                ),
                        ),
                        _TransportDock(controller: widget.controller),
                      ],
                    );
                  },
                ),
              ),
      );
    },
  );
}

class _BookPane extends StatelessWidget {
  const _BookPane({
    required this.paneKey,
    required this.label,
    required this.icon,
    required this.child,
    this.footer,
  });

  final Key paneKey;
  final String label;
  final IconData icon;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Container(
    key: paneKey,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.divider),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 0),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
        ?footer,
      ],
    ),
  );
}

class _ArtworkDetails extends StatelessWidget {
  const _ArtworkDetails({required this.entryName, required this.metadata});
  final String entryName;
  final TrackMetadata? metadata;

  @override
  Widget build(BuildContext context) => Center(
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: metadata?.artwork == null
                  ? Container(
                      width: math.min(
                        280,
                        math.max(120, constraints.maxWidth - 48),
                      ),
                      height: math.min(
                        280,
                        math.max(120, constraints.maxWidth - 48),
                      ),
                      color: AppColors.field,
                      child: const Icon(
                        Icons.album_rounded,
                        size: 110,
                        color: Colors.white38,
                      ),
                    )
                  : Image.memory(
                      metadata!.artwork!,
                      width: math.min(
                        280,
                        math.max(120, constraints.maxWidth - 48),
                      ),
                      height: math.min(
                        280,
                        math.max(120, constraints.maxWidth - 48),
                      ),
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
    ),
  );
}

class _TransportDock extends StatelessWidget {
  const _TransportDock({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('now-playing-transport-dock'),
    decoration: const BoxDecoration(
      color: AppColors.sidebar,
      border: Border(top: BorderSide(color: AppColors.divider)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: '上一首',
          onPressed: controller.busy || !controller.player.hasPrevious
              ? null
              : () => controller.skip(false),
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          tooltip: controller.player.playing ? '暂停' : '播放',
          onPressed: controller.busy ? null : controller.toggle,
          icon: Icon(
            controller.player.playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: '下一首',
          onPressed: controller.busy || !controller.player.hasNext
              ? null
              : () => controller.skip(true),
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    ),
  );
}
