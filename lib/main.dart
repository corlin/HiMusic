import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'theme.dart';
import 'ui/library_page.dart';

export 'ui/library_page.dart' show ConnectionDialog, LibraryPage, PlayerBar;
export 'ui/now_playing_page.dart' show NowPlayingPage;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
  runApp(const HiMusicApp());
}

class HiMusicApp extends StatelessWidget {
  const HiMusicApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HiMusic',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: home ?? const LibraryPage(),
  );
}
