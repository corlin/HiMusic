import 'package:flutter/foundation.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../metadata/track_metadata.dart';
import '../playback/output_devices.dart';
import '../playback/player_controller.dart';
import '../playback/volume_controls.dart';
import '../sources/ios_directory_picker.dart';
import '../sources/local_source.dart';
import '../sources/selected_files_source.dart';
import '../sources/music_source.dart';
import '../sources/smb_source.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/track_sort.dart';
import '../waveform/player_waveform.dart';
import 'now_playing_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.controller});

  final PlayerController? controller;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final PlayerController controller =
      widget.controller ?? PlayerController();
  final searchController = TextEditingController();
  final _iosDirectoryPicker = IosDirectoryPicker();
  bool tvMode = false;
  String section = '音乐';
  TrackSortField? _sortField;
  bool _sortAsc = true;
  String? _albumFilter;
  String? _artistFilter;

  void _handleSort(TrackSortField field) {
    setState(() {
      if (_sortField != field) {
        _sortField = field;
        _sortAsc = true;
      } else if (_sortAsc) {
        _sortAsc = false;
      } else {
        _sortField = null; // 再次点击回到自然顺序
      }
    });
  }

  void _openAlbum(String album) {
    setState(() {
      _albumFilter = album;
      _artistFilter = null;
      section = '音乐';
    });
  }

  void _openArtist(String artist) {
    setState(() {
      _artistFilter = artist;
      _albumFilter = null;
      section = '音乐';
    });
  }

  void _clearGroupFilter() {
    setState(() {
      _albumFilter = null;
      _artistFilter = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _restoreLastFolder();
  }

  Future<void> _restoreLastFolder() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final path = await _iosDirectoryPicker.restoreDirectory();
      if (path != null && mounted && controller.source == null) {
        await controller.connect(() => LocalSource.open(path), '');
      }
    } catch (_) {
      // 自动恢复失败时静默忽略，用户可手动选择。
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  Future<void> addSmb() async {
    final values = await showDialog<SmbConnectionRequest>(
      context: context,
      builder: (_) => const ConnectionDialog(),
    );
    if (values == null || !mounted) return;
    await controller.connect(
      () => SmbSource.connect(
        host: values.host,
        share: values.share,
        user: values.user,
        password: values.password,
      ),
      values.directory,
    );
  }

  Future<void> addLocal() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('打开音乐文件夹'),
                  subtitle: const Text('自动关联同名 .lrc 歌词，记住此文件夹'),
                  onTap: () => Navigator.pop(context, 'folder'),
                ),
                ListTile(
                  leading: const Icon(Icons.audio_file_rounded),
                  title: const Text('选择音乐文件'),
                  subtitle: const Text('手动多选音频和歌词文件'),
                  onTap: () => Navigator.pop(context, 'files'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (choice == 'folder') {
          final path = await _iosDirectoryPicker.pickDirectory();
          if (path != null && mounted) {
            await controller.connect(() => LocalSource.open(path), '');
          }
        } else if (choice == 'files') {
          await _pickAudioFiles();
        }
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _pickAudioFiles();
        return;
      }
      final path = await getDirectoryPath(confirmButtonText: '打开音乐目录');
      if (path != null) {
        await controller.connect(() => LocalSource.open(path), '');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开本地音乐：$e')),
        );
      }
    }
  }

  Future<void> _pickAudioFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '音乐与歌词',
          mimeTypes: ['audio/*', 'text/plain'],
          extensions: ['flac', 'mp3', 'm4a', 'aac', 'wav', 'alac', 'lrc'],
          uniformTypeIdentifiers: ['public.audio', 'public.text'],
        ),
      ],
    );
    if (files.isNotEmpty && mounted) {
      await controller.connect(() async => SelectedFilesSource(files), '');
    }
  }

  void chooseSection(String next) {
    setState(() {
      section = next;
      if (next != '音乐') {
        _albumFilter = null;
        _artistFilter = null;
      }
    });
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
        child: RepaintBoundary(
          key: const Key('library-capture-boundary'),
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                return SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (wide)
                              _Sidebar(
                                controller: c,
                                section: section,
                                onSection: chooseSection,
                                onSmb: addSmb,
                                onLocal: addLocal,
                              ),
                            Expanded(
                              child: _LibraryContent(
                                controller: c,
                                searchController: searchController,
                                tvMode: tvMode,
                                showCompactHeader: !wide,
                                onSmb: addSmb,
                                onLocal: addLocal,
                                onTvMode: () =>
                                    setState(() => tvMode = !tvMode),
                                onSearch: (_) => setState(() {}),
                                section: section,
                                sortField: _sortField,
                                sortAsc: _sortAsc,
                                onSort: _handleSort,
                                albumFilter: _albumFilter,
                                artistFilter: _artistFilter,
                                onClearGroupFilter: _clearGroupFilter,
                                onOpenAlbum: _openAlbum,
                                onOpenArtist: _openArtist,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PlayerBar(controller: c),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.section,
    required this.onSection,
    required this.onSmb,
    required this.onLocal,
  });

  final PlayerController controller;
  final String section;
  final ValueChanged<String> onSection;
  final VoidCallback onSmb;
  final VoidCallback onLocal;

  @override
  Widget build(BuildContext context) => Container(
    width: 232,
    decoration: const BoxDecoration(
      color: AppColors.sidebar,
      border: Border(right: BorderSide(color: AppColors.divider)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Brand(),
          const SizedBox(height: 26),
          for (final item in const [
            ('音乐', Icons.music_note_rounded),
            ('专辑', Icons.album_outlined),
            ('艺术家', Icons.person_outline_rounded),
            ('文件夹', Icons.folder_outlined),
            ('播放列表', Icons.queue_music_rounded),
          ])
            _NavigationItem(
              label: item.$1,
              icon: item.$2,
              selected: section == item.$1,
              onTap: () => onSection(item.$1),
            ),
          const SizedBox(height: 24),
          const _SectionLabel('来源'),
          const SizedBox(height: 8),
          _SourceItem(
            icon: Icons.computer_rounded,
            label: '本地音乐',
            active: controller.source is LocalSource,
            onTap: controller.busy ? null : onLocal,
          ),
          if (controller.source != null && controller.source is! LocalSource)
            _SourceItem(
              icon: Icons.router_outlined,
              label: controller.source!.label,
              active: true,
              onTap: controller.busy ? null : onSmb,
            ),
          _SourceItem(
            icon: Icons.add_link_rounded,
            label: '连接 SMB 共享硬盘',
            active: false,
            onTap: controller.busy ? null : onSmb,
          ),
          const Spacer(),
          _NavigationItem(
            label: '设置',
            icon: Icons.settings_outlined,
            selected: false,
            onTap: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('播放与音源设置会在这里集中管理'))),
          ),
        ],
      ),
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(BorderSide(color: AppColors.accent, width: 1.5)),
          borderRadius: BorderRadius.all(Radius.circular(9)),
        ),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.library_music_rounded, color: AppColors.accent, size: 22),
        ),
      ),
      SizedBox(width: 12),
      Flexible(
        child: Text(
          'HiMusic',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xff778078),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: .6,
    ),
  );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: selected ? AppColors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 13),
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.background : Colors.white70,
              ),
              const SizedBox(width: 13),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.background : Colors.white70,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SourceItem extends StatelessWidget {
  const _SourceItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? AppColors.surfaceRaised : Colors.transparent,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            const SizedBox(width: 13),
            Icon(icon, size: 19, color: active ? AppColors.accent : Colors.white60),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: active ? Colors.white : Colors.white60),
              ),
            ),
            if (active) ...[
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 7, height: 7),
              ),
              const SizedBox(width: 12),
            ],
          ],
        ),
      ),
    ),
  );
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({
    required this.controller,
    required this.searchController,
    required this.tvMode,
    required this.showCompactHeader,
    required this.onSmb,
    required this.onLocal,
    required this.onTvMode,
    required this.onSearch,
    required this.section,
    required this.sortField,
    required this.sortAsc,
    required this.onSort,
    required this.albumFilter,
    required this.artistFilter,
    required this.onClearGroupFilter,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  final PlayerController controller;
  final TextEditingController searchController;
  final bool tvMode;
  final bool showCompactHeader;
  final VoidCallback onSmb;
  final VoidCallback onLocal;
  final VoidCallback onTvMode;
  final ValueChanged<String> onSearch;
  final String section;
  final TrackSortField? sortField;
  final bool sortAsc;
  final ValueChanged<TrackSortField> onSort;
  final String? albumFilter;
  final String? artistFilter;
  final VoidCallback onClearGroupFilter;
  final ValueChanged<String> onOpenAlbum;
  final ValueChanged<String> onOpenArtist;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _TopBar(
        controller: controller,
        searchController: searchController,
        showBrand: showCompactHeader,
        onLocal: onLocal,
        tvMode: tvMode,
        onSmb: onSmb,
        onTvMode: onTvMode,
        onSearch: onSearch,
      ),
      if (controller.busy) const LinearProgressIndicator(minHeight: 2),
      if (controller.error != null)
        _ErrorBanner(controller: controller)
      else
        const SizedBox(height: 2),
      Expanded(
        child: controller.source == null
            ? _Welcome(onSmb: onSmb, onLocal: onLocal)
            : switch (section) {
                '专辑' => _AlbumSection(
                    controller: controller,
                    tvMode: tvMode,
                    onOpen: onOpenAlbum,
                  ),
                '艺术家' => _ArtistSection(
                    controller: controller,
                    onOpen: onOpenArtist,
                  ),
                '播放列表' => _QueueView(controller: controller),
                _ => _ConnectedLibrary(
                    controller: controller,
                    query: searchController.text,
                    tvMode: tvMode,
                    sortField: sortField,
                    sortAsc: sortAsc,
                    onSort: onSort,
                    albumFilter: albumFilter,
                    artistFilter: artistFilter,
                    onClearGroupFilter: onClearGroupFilter,
                  ),
              },
      ),
    ],
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onLocal,
    required this.controller,
    required this.searchController,
    required this.showBrand,
    required this.tvMode,
    required this.onSmb,
    required this.onTvMode,
    required this.onSearch,
  });

  final VoidCallback onLocal;
  final PlayerController controller;
  final TextEditingController searchController;
  final bool showBrand;
  final bool tvMode;
  final VoidCallback onSmb;
  final VoidCallback onTvMode;
  final ValueChanged<String> onSearch;

  InputDecoration _searchDecoration() => InputDecoration(
    hintText: '搜索当前目录',
    prefixIcon: const Icon(Icons.search_rounded, size: 20),
    contentPadding: EdgeInsets.zero,
    suffixIcon: searchController.text.isEmpty
        ? null
        : IconButton(
            tooltip: '清除搜索',
            onPressed: () {
              searchController.clear();
              onSearch('');
            },
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 700) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(child: _Brand()),
                  IconButton(
                    tooltip: '选择本地音乐',
                    onPressed: controller.busy ? null : onLocal,
                    icon: const Icon(Icons.folder_open_rounded),
                  ),
                  IconButton(
                    tooltip: '连接共享硬盘',
                    onPressed: controller.busy ? null : onSmb,
                    icon: const Icon(Icons.add_link_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: '上一级',
                    onPressed: controller.busy || controller.directory.isEmpty
                        ? null
                        : controller.up,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onChanged: onSearch,
                      decoration: _searchDecoration(),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新目录',
                    onPressed: controller.source == null || controller.busy
                        ? null
                        : () => controller.browse(controller.directory),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ],
          ),
        );
      }
      return Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            if (showBrand) ...[
              const Expanded(child: _Brand()),
              const SizedBox(width: 18),
            ],
            IconButton(
              tooltip: '上一级',
              onPressed: controller.busy || controller.directory.isEmpty
                  ? null
                  : controller.up,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            IconButton(
              tooltip: '刷新目录',
              onPressed: controller.source == null || controller.busy
                  ? null
                  : () => controller.browse(controller.directory),
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: searchController,
                  onChanged: onSearch,
                  decoration: _searchDecoration(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: tvMode ? '标准布局' : '电视布局',
              onPressed: onTvMode,
              icon: Icon(
                tvMode ? Icons.desktop_windows_outlined : Icons.tv_outlined,
              ),
            ),
            IconButton(
              tooltip: '连接共享硬盘',
              onPressed: controller.busy ? null : onSmb,
              icon: const Icon(Icons.add_link_rounded),
            ),
          ],
        ),
      );
    },
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .35),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    child: Row(
      children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 10),
        Expanded(child: Text(controller.error!)),
        TextButton(
          onPressed: controller.busy ? null : controller.retry,
          child: const Text('重试'),
        ),
      ],
    ),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onSmb, required this.onLocal});
  final VoidCallback onSmb;
  final VoidCallback onLocal;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_music_rounded, size: 66, color: AppColors.accent),
          const SizedBox(height: 24),
          const Text(
            '家里的音乐，随时听。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 9),
          const Text(
            '连接共享硬盘，或选择本地音乐',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            autofocus: true,
            onPressed: onSmb,
            icon: const Icon(Icons.router_outlined),
            label: const Text('连接 SMB 共享硬盘'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              onPressed: onLocal,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(
                defaultTargetPlatform == TargetPlatform.macOS ||
                        defaultTargetPlatform == TargetPlatform.windows ||
                        defaultTargetPlatform == TargetPlatform.linux
                    ? '打开本地目录'
                    : '选择本地音乐',
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '原文件播放 · 每台设备保留独立队列',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _ConnectedLibrary extends StatelessWidget {
  const _ConnectedLibrary({
    required this.controller,
    required this.query,
    required this.tvMode,
    required this.sortField,
    required this.sortAsc,
    required this.onSort,
    required this.albumFilter,
    required this.artistFilter,
    required this.onClearGroupFilter,
  });

  final PlayerController controller;
  final String query;
  final bool tvMode;
  final TrackSortField? sortField;
  final bool sortAsc;
  final ValueChanged<TrackSortField> onSort;
  final String? albumFilter;
  final String? artistFilter;
  final VoidCallback onClearGroupFilter;

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    var filtered = controller.entries.where((entry) {
      if (entry.name.toLowerCase().contains(normalized)) return true;
      final metadata = controller.metadata.metadataFor(entry);
      return [
        metadata?.title,
        metadata?.album,
        metadata?.albumArtist,
        ...?metadata?.performers,
        ...?metadata?.composers,
        ...?metadata?.arrangers,
        ...?metadata?.lyricists,
      ].whereType<String>().any(
        (value) => value.toLowerCase().contains(normalized),
      );
    }).toList();
    if (albumFilter != null || artistFilter != null) {
      filtered = filtered.where((entry) {
        if (entry.isDirectory) return false;
        final metadata = controller.metadata.metadataFor(entry);
        if (albumFilter != null) {
          final album = metadata?.album?.trim();
          return albumFilter == '未知专辑'
              ? album == null || album.isEmpty
              : album == albumFilter;
        }
        final artist = metadata?.artistLine;
        return artistFilter == '未知艺术家'
            ? artist == null || artist.isEmpty
            : artist == artistFilter;
      }).toList();
    }
    filtered = applyTrackSort(
      entries: filtered,
      field: sortField,
      ascending: sortAsc,
      metadataFor: controller.metadata.metadataFor,
    );
    final audio = filtered.where((entry) => entry.isAudio).toList();
    final metadataStatus = controller.metadata.isScanning
        ? '正在读取歌曲信息…'
        : controller.metadata.failedCount > 0
        ? '${controller.metadata.failedCount} 首歌曲信息无法读取'
        : '只读访问';
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            narrow ? 14 : 28,
            narrow ? 10 : 16,
            narrow ? 14 : 28,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: narrow
                        ? Text(
                            '${controller.source!.label}${controller.directory.isEmpty ? '' : '  /  ${controller.directory}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '当前目录',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${controller.source!.label}${controller.directory.isEmpty ? '' : '  /  ${controller.directory}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.muted, fontSize: 13),
                              ),
                            ],
                          ),
                  ),
                  if (!narrow) ...[
                    TextButton.icon(
                      onPressed: controller.busy ||
                              !controller.entries.any((e) => e.isAudio)
                          ? null
                          : () => controller.playAll(),
                      icon: const Icon(
                        Icons.play_circle_outline_rounded,
                        size: 17,
                      ),
                      label: const Text('播放全部'),
                    ),
                    TextButton.icon(
                      onPressed: controller.busy ||
                              !controller.entries.any((e) => e.isAudio)
                          ? null
                          : () => controller.playAll(shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded, size: 17),
                      label: const Text('随机播放'),
                    ),
                    TextButton.icon(
                      onPressed: controller.busy
                          ? null
                          : () => controller.browse(controller.directory),
                      icon: const Icon(Icons.sync_rounded, size: 17),
                      label: const Text('同步'),
                    ),
                  ],
                ],
              ),
              if (albumFilter != null || artistFilter != null) ...[
                const SizedBox(height: 14),
                Material(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: onClearGroupFilter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.filter_alt_rounded,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            albumFilter != null
                                ? '专辑：$albumFilter'
                                : '艺术家：$artistFilter',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (!narrow && audio.isNotEmpty) ...[
                const SizedBox(height: 16),
                _AlbumShelf(entries: audio, controller: controller, tvMode: tvMode),
                const SizedBox(height: 22),
              ],
              if (narrow && audio.isNotEmpty) const SizedBox(height: 8),
              _TableHeader(
                hasEntries: filtered.isNotEmpty,
                sortField: sortField,
                sortAsc: sortAsc,
                onSort: onSort,
              ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      normalized.isEmpty
                          ? '此目录暂无支持的音乐文件或子目录'
                          : '没有匹配的音乐或文件夹\n试试其他关键词，或清除搜索查看全部',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _TrackRow(
                      entry: filtered[index],
                      metadata: controller.metadata.metadataFor(
                        filtered[index],
                      ),
                      index: index,
                      selected:
                          controller.current?.path == filtered[index].path,
                      tvMode: tvMode,
                      onTap: controller.busy
                          ? null
                          : () => filtered[index].isDirectory
                                ? controller.browse(filtered[index].path)
                                : controller.playEntry(filtered[index]),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              normalized.isEmpty
                  ? '${filtered.length} 项 · $metadataStatus'
                  : '找到 ${filtered.length} 项 / 共 ${controller.entries.length} 项 · 只读访问',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  },
);
  }
}

class _AlbumSection extends StatelessWidget {
  const _AlbumSection({
    required this.controller,
    required this.tvMode,
    required this.onOpen,
  });

  final PlayerController controller;
  final bool tvMode;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final albums = <String, List<MusicEntry>>{};
    for (final entry in controller.entries.where((entry) => entry.isAudio)) {
      final album = controller.metadata.metadataFor(entry)?.album?.trim();
      albums
          .putIfAbsent(album == null || album.isEmpty ? '未知专辑' : album, () => [])
          .add(entry);
    }
    final names = albums.keys.toList()..sort();
    if (names.isEmpty) {
      return const Center(
        child: Text(
          '当前目录没有可浏览的音乐',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    final tileSize = tvMode ? 200.0 : 176.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 14),
          child: Text(
            '专辑 · ${names.length}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
            children: [
              Wrap(
                spacing: 18,
                runSpacing: 22,
                children: [
                  for (final name in names)
                    _AlbumBrowserTile(
                      name: name,
                      entries: albums[name]!,
                      controller: controller,
                      size: tileSize,
                      onTap: () => onOpen(name),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlbumBrowserTile extends StatelessWidget {
  const _AlbumBrowserTile({
    required this.name,
    required this.entries,
    required this.controller,
    required this.size,
    required this.onTap,
  });

  final String name;
  final List<MusicEntry> entries;
  final PlayerController controller;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Uint8List? cover;
    for (final entry in entries) {
      final artwork = controller.metadata.metadataFor(entry)?.artwork;
      if (artwork != null) {
        cover = artwork;
        break;
      }
    }
    final artist = _firstArtist(entries, controller);
    return SizedBox(
      width: size,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: cover == null
                    ? Container(
                        color: AppColors.surfaceRaised,
                        child: const Icon(
                          Icons.album_rounded,
                          size: 46,
                          color: Colors.white24,
                        ),
                      )
                    : Image.memory(cover, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              [
                ?artist,
                '${entries.length} 首',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistSection extends StatelessWidget {
  const _ArtistSection({
    required this.controller,
    required this.onOpen,
  });

  final PlayerController controller;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final artists = <String, List<MusicEntry>>{};
    for (final entry in controller.entries.where((entry) => entry.isAudio)) {
      final line = controller.metadata.metadataFor(entry)?.artistLine?.trim();
      artists
          .putIfAbsent(line == null || line.isEmpty ? '未知艺术家' : line, () => [])
          .add(entry);
    }
    final names = artists.keys.toList()..sort();
    if (names.isEmpty) {
      return const Center(
        child: Text(
          '当前目录没有可浏览的音乐',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 10),
          child: Text(
            '艺术家 · ${names.length}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
            itemCount: names.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final name = names[index];
              final count = artists[name]!.length;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const CircleAvatar(
                  backgroundColor: AppColors.surfaceRaised,
                  child: Icon(Icons.person_rounded, color: Colors.white54),
                ),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '$count 首',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted,
                ),
                onTap: () => onOpen(name),
              );
            },
          ),
        ),
      ],
    );
  }
}

String? _firstArtist(List<MusicEntry> entries, PlayerController controller) {
  for (final entry in entries) {
    final line = controller.metadata.metadataFor(entry)?.artistLine;
    if (line != null && line.isNotEmpty) return line;
  }
  return null;
}

class _QueueView extends StatelessWidget {
  const _QueueView({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
    final current = controller.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 10),
          child: Text(
            '播放队列 · ${queue.length}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: queue.isEmpty
              ? const Center(
                  child: Text(
                    '当前队列为空\n在音乐目录选择一首歌，或点击「播放全部」',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                  itemCount: queue.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = queue[index];
                    final metadata = controller.metadata.metadataFor(entry);
                    final selected = current?.path == entry.path;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                      ),
                      leading: Icon(
                        selected
                            ? Icons.graphic_eq_rounded
                            : Icons.music_note_rounded,
                        size: 20,
                        color: selected ? AppColors.accent : AppColors.muted,
                      ),
                      title: Text(
                        metadata?.displayTitle(entry.name) ??
                            stripExtension(entry.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? AppColors.accent : Colors.white,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      subtitle: Text(
                        metadata?.artistLine ??
                            '${entry.extension.toUpperCase()} · 原文件',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: '从队列移除',
                        onPressed: controller.busy
                            ? null
                            : () => controller.removeFromQueue(index),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.muted,
                        ),
                      ),
                      onTap: controller.busy
                          ? null
                          : () => controller.playAt(index),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AlbumShelf extends StatelessWidget {
  const _AlbumShelf({
    required this.entries,
    required this.controller,
    required this.tvMode,
  });

  final List<MusicEntry> entries;
  final PlayerController controller;
  final bool tvMode;

  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        (tvMode ? 148 : 120) + 12 + MediaQuery.textScalerOf(context).scale(36),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: entries.length > 6 ? 6 : entries.length,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final metadata = controller.metadata.metadataFor(entry);
        return _AlbumTile(
          entry: entry,
          metadata: metadata,
          size: tvMode ? 148 : 120,
          onTap: controller.busy ? null : () => controller.playEntry(entry),
        );
      },
    ),
  );
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.entry,
    required this.metadata,
    required this.size,
    required this.onTap,
  });

  final MusicEntry entry;
  final TrackMetadata? metadata;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: metadata?.artwork == null
                ? Container(
                    width: size,
                    height: size,
                    color: AppColors.surfaceRaised,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.album_rounded,
                      size: size * .36,
                      color: AppColors.muted,
                    ),
                  )
                : Image.memory(
                    metadata!.artwork!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Container(
                      color: AppColors.surfaceRaised,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.album_rounded,
                        size: size * .36,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 7),
          Text(
            metadata?.displayTitle(entry.name) ?? stripExtension(entry.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            metadata?.artistLine ??
                metadata?.album ??
                entry.extension.toUpperCase(),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.hasEntries,
    required this.sortField,
    required this.sortAsc,
    required this.onSort,
  });

  final bool hasEntries;
  final TrackSortField? sortField;
  final bool sortAsc;
  final ValueChanged<TrackSortField> onSort;

  Widget _label(String text, {TrackSortField? field}) {
    if (field == null) {
      return Text(text, style: const TextStyle(color: AppColors.muted));
    }
    final active = sortField == field;
    return InkWell(
      onTap: hasEntries ? () => onSort(field) : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                color: active ? AppColors.accent : AppColors.muted,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 3),
              Icon(
                sortAsc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 13,
                color: AppColors.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showDuration = width >= 840;
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text('#', style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            flex: 5,
            child: _label('标题', field: TrackSortField.title),
          ),
          if (width >= 700) ...[
            Expanded(
              flex: 2,
              child: _label('艺术家', field: TrackSortField.artist),
            ),
            Expanded(
              flex: 2,
              child: _label('专辑', field: TrackSortField.album),
            ),
          ],
          if (showDuration)
            SizedBox(
              width: 64,
              child: _label('时长', field: TrackSortField.duration),
            ),
          if (width >= 700)
            SizedBox(
              width: 150,
              child: _label('格式', field: TrackSortField.size),
            ),
          SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.entry,
    required this.metadata,
    required this.index,
    required this.selected,
    required this.tvMode,
    required this.onTap,
  });

  final MusicEntry entry;
  final TrackMetadata? metadata;
  final int index;
  final bool selected;
  final bool tvMode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.selectedRow : Colors.transparent,
    child: InkWell(
      autofocus: index == 0,
      focusColor: AppColors.rowFocus,
      onTap: onTap,
      child: MediaQuery.sizeOf(context).width < 700
          ? SizedBox(
              height: 68,
              child: Row(
                children: [
                  Icon(
                    entry.isDirectory
                        ? Icons.folder_outlined
                        : Icons.music_note_rounded,
                    size: 20,
                    color: selected ? AppColors.accent : AppColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metadata?.displayTitle(entry.name) ??
                              stripExtension(entry.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? AppColors.accent : Colors.white,
                          ),
                        ),
                        Text(
                          entry.isDirectory
                              ? '文件夹'
                              : metadata?.artistLine ??
                                    metadata?.album ??
                                    '${entry.extension.toUpperCase()} · ${(entry.size / 1048576).toStringAsFixed(1)} MB',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TrackAction(entry: entry, metadata: metadata),
                ],
              ),
            )
          : SizedBox(
              height: tvMode ? 62 : 48,
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: selected
                        ? const Icon(
                            Icons.graphic_eq_rounded,
                            size: 17,
                            color: AppColors.accent,
                          )
                        : Text(
                            '${index + 1}',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        Icon(
                          entry.isDirectory
                              ? Icons.folder_outlined
                              : Icons.music_note_rounded,
                          size: 18,
                          color: selected ? AppColors.accent : Colors.white54,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            metadata?.displayTitle(entry.name) ??
                                stripExtension(entry.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? AppColors.accent : Colors.white,
                              fontSize: tvMode ? 18 : 14,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.isDirectory ? '文件夹' : metadata?.artistLine ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.isDirectory ? '—' : metadata?.album ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                  if (MediaQuery.sizeOf(context).width >= 840)
                    SizedBox(
                      width: 64,
                      child: Text(
                        entry.isDirectory || metadata?.duration == null
                            ? '—'
                            : formatDuration(metadata!.duration!),
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  SizedBox(
                    width: 150,
                    child: Text(
                      entry.isDirectory
                          ? '—'
                          : '${entry.extension.toUpperCase()} · ${(entry.size / 1048576).toStringAsFixed(1)} MB',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: _TrackAction(entry: entry, metadata: metadata),
                  ),
                ],
              ),
            ),
    ),
  );
}

String _artistAlbum(TrackMetadata? metadata) {
  final value = [
    metadata?.artistLine,
    metadata?.album,
  ].whereType<String>().join(' · ');
  return value.isEmpty ? '—' : value;
}

class _TrackAction extends StatelessWidget {
  const _TrackAction({required this.entry, required this.metadata});

  final MusicEntry entry;
  final TrackMetadata? metadata;

  @override
  Widget build(BuildContext context) {
    if (entry.isDirectory) {
      return const Icon(Icons.chevron_right_rounded, color: Colors.white54);
    }
    if (metadata == null) {
      return const Icon(Icons.play_arrow_rounded, color: Colors.white54);
    }
    return IconButton(
      tooltip: '查看歌曲信息',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => _TrackDetails(entry: entry, metadata: metadata!),
      ),
      icon: const Icon(Icons.info_outline_rounded, color: Colors.white54),
    );
  }
}

class _TrackDetails extends StatelessWidget {
  const _TrackDetails({required this.entry, required this.metadata});

  final MusicEntry entry;
  final TrackMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final rows = <String, String>{
      ...metadata.credits,
      if (metadata.album != null) '专辑': metadata.album!,
      if (metadata.albumArtist != null) '专辑艺术家': metadata.albumArtist!,
      if (metadata.year != null) '年份': '${metadata.year}',
      if (metadata.trackNumber != null) '曲目': '${metadata.trackNumber}',
      if (metadata.discNumber != null) '唱片': '${metadata.discNumber}',
      if (metadata.genres.isNotEmpty) '流派': metadata.genres.join('、'),
      if (metadata.duration != null) '时长': formatDuration(metadata.duration!),
      if (metadata.sampleRate != null)
        '采样率': '${metadata.sampleRate! ~/ 1000} kHz',
      if (metadata.bitDepth != null) '位深': '${metadata.bitDepth} bit',
      if (metadata.bitRate != null)
        '码率': '${(metadata.bitRate! / 1000).round()} kbps',
      if (metadata.channels != null) '声道': '${metadata.channels}',
      '格式': entry.extension.toUpperCase(),
    };
    return AlertDialog(
      title: Text(metadata.displayTitle(entry.name)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (metadata.artwork != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    metadata.artwork!,
                    width: 180,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              for (final row in rows.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(
                          row.key,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      Expanded(child: Text(row.value)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final current = controller.current;
    if (current == null) return const SizedBox.shrink();
    final narrow = MediaQuery.sizeOf(context).width < 820;
    return Container(
      constraints: BoxConstraints(minHeight: narrow ? 64 : 180),
      padding: EdgeInsets.fromLTRB(18, narrow ? 8 : 10, 18, narrow ? 8 : 12),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 820;
          final info = _NowPlayingInfo(
            controller: controller,
            onTap: () => _openNowPlaying(context),
            compact: !horizontal,
          );
          final controls = _PlaybackControls(controller: controller);
          final waveform = PlayerWaveform(
            controller: controller,
            compact: true,
          );
          if (!horizontal) {
            return Row(
              children: [
                Expanded(child: info),
                IconButton(
                  tooltip: '歌词',
                  onPressed: () => _openNowPlaying(context, lyrics: true),
                  icon: const Icon(Icons.lyrics_rounded, size: 20),
                ),
                controls,
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 230, child: info),
              IconButton(
                tooltip: '歌词',
                onPressed: () => _openNowPlaying(context, lyrics: true),
                icon: const Icon(Icons.lyrics_rounded),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [controls, waveform],
                ),
              ),
              const SizedBox(width: 22),
              SizedBox(
                width: 248,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('output-device-button'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const OutputDeviceDialog(),
                      ),
                      icon: const Icon(Icons.speaker_group_outlined, size: 19),
                      label: const Text(
                        '本机音频输出',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    VolumeControls(controller: controller),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openNowPlaying(BuildContext context, {bool lyrics = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NowPlayingPage(controller: controller, showLyrics: lyrics),
      ),
    );
  }
}

class _NowPlayingInfo extends StatelessWidget {
  const _NowPlayingInfo({
    required this.controller,
    required this.onTap,
    this.compact = false,
  });
  final PlayerController controller;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final current = controller.current!;
    final metadata = controller.metadata.metadataFor(current);
    final coverSize = compact ? 44.0 : 72.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: metadata?.artwork == null
                ? Container(
                    width: coverSize,
                    height: coverSize,
                    color: AppColors.surfaceRaised,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.album_rounded,
                      size: compact ? 22 : 32,
                      color: AppColors.muted,
                    ),
                  )
                : Image.memory(
                    metadata!.artwork!,
                    width: coverSize,
                    height: coverSize,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Container(
                      color: AppColors.surfaceRaised,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.album_rounded,
                        size: compact ? 22 : 32,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata?.displayTitle(current.name) ??
                      stripExtension(current.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (metadata?.artistLine != null) ...[
                  Text(
                    _artistAlbum(metadata),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  '${current.extension.toUpperCase()} · 原文件',
                  style: const TextStyle(color: AppColors.accent, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.source?.label ?? '本地音乐',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: '上一首',
        onPressed: controller.busy || !controller.player.hasPrevious
            ? null
            : () => controller.skip(false),
        icon: const Icon(Icons.skip_previous_rounded),
      ),
      const SizedBox(width: 6),
      IconButton.filled(
        tooltip: controller.current == null
            ? '请先选择一首音乐'
            : controller.player.playing
            ? '暂停'
            : '播放',
        onPressed: controller.busy || controller.current == null
            ? null
            : controller.toggle,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background,
          minimumSize: const Size(46, 46),
        ),
        icon: Icon(
          controller.player.playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          size: 26,
        ),
      ),
      const SizedBox(width: 6),
      IconButton(
        tooltip: '下一首',
        onPressed: controller.busy || !controller.player.hasNext
            ? null
            : () => controller.skip(true),
        icon: const Icon(Icons.skip_next_rounded),
      ),
      IconButton(
        tooltip: controller.shuffleEnabled ? '随机播放 · 点击关闭' : '顺序播放 · 点击开启随机',
        onPressed: controller.busy ? null : controller.toggleShuffle,
        icon: Icon(
          Icons.shuffle_rounded,
          color: controller.shuffleEnabled ? AppColors.accent : Colors.white38,
        ),
      ),
      IconButton(
        tooltip: switch (controller.player.loopMode) {
          LoopMode.off => '顺序播放 · 点击切换列表循环',
          LoopMode.all => '列表循环 · 点击切换单曲循环',
          LoopMode.one => '单曲循环 · 点击切换顺序播放',
        },
        onPressed: controller.busy ? null : controller.cycleLoop,
        icon: Icon(
          controller.player.loopMode == LoopMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          color: controller.player.loopMode == LoopMode.off
              ? Colors.white38
              : AppColors.accent,
        ),
      ),
    ],
  );
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
                      labelText: const [
                        '主机 IP 或名称',
                        '共享名称',
                        '音乐目录（可选）',
                        '用户名（可选）',
                        '密码（可选）',
                      ][i],
                    ),
                    validator: (value) =>
                        i < 2 && (value == null || value.trim().isEmpty)
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
            Navigator.pop(
              context,
              SmbConnectionRequest(
                host: fields[0].text,
                share: fields[1].text,
                directory: fields[2].text,
                user: fields[3].text,
                password: fields[4].text,
              ),
            );
          }
        },
        child: const Text('连接'),
      ),
    ],
  );
}
