import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'playback/audio_handler.dart';
import 'playback/player_controller.dart';
import 'theme.dart';
import 'ui/library_page.dart';

export 'ui/library_page.dart' show ConnectionDialog, LibraryPage, PlayerBar;
export 'ui/now_playing_page.dart' show NowPlayingPage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
  final controller = await _initBackgroundPlayback();
  runApp(HiMusicApp(controller: controller));
}

/// 在支持系统媒体控制的平台启用 audio_service（Android/iOS/macOS）；
/// Windows 无平台实现、Web 无后台语义，保持现有播放行为。
Future<PlayerController?> _initBackgroundPlayback() async {
  if (kIsWeb || Platform.isWindows) return null;
  try {
    final controller = PlayerController();
    final handler = await AudioService.init(
      builder: () => HiMusicAudioHandler(controller),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.himusic.channel.audio',
        androidNotificationChannelName: '音乐播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    unawaited(handler.loadFallbackArt());
    return controller;
  } catch (_) {
    // 平台原生不可用时回退：由 LibraryPage 自行创建控制器。
    return null;
  }
}

class HiMusicApp extends StatelessWidget {
  const HiMusicApp({super.key, this.home, this.controller});

  final Widget? home;
  final PlayerController? controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HiMusic',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: home ?? LibraryPage(controller: controller),
  );
}
