import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

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
    theme: _theme,
    home: home ?? const LibraryPage(),
  );
}

final _theme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  fontFamily: '.AppleSystemUIFont',
  scaffoldBackgroundColor: const Color(0xff0f1512),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xffb7d89c),
    brightness: Brightness.dark,
    surface: const Color(0xff131a16),
  ),
  dividerColor: const Color(0xff273029),
  focusColor: const Color(0xff34432f),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xff1a211d),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  ),
  sliderTheme: const SliderThemeData(
    trackHeight: 2,
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
  ),
);
