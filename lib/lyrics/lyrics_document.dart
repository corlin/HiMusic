enum LyricsSource { embeddedSynced, sidecarLrc, embeddedPlain }

class TimedLyricLine {
  const TimedLyricLine({required this.timestamp, required this.text});

  final Duration timestamp;
  final String text;
}

class LyricsDocument {
  const LyricsDocument({
    required this.source,
    this.lines = const [],
    this.plainText,
  });

  final LyricsSource source;
  final List<TimedLyricLine> lines;
  final String? plainText;

  bool get hasTimedLines => lines.isNotEmpty;
}
