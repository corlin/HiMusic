import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:himusic/playback/audio_bridge.dart';
import 'package:himusic/sources/smb_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实 SMB2 认证、目录、范围读取和 FLAC 解码', (tester) async {
    final source = await SmbSource.connect(
      host: '127.0.0.1:1445',
      share: 'Music',
      user: 'himusic-test',
      password: 'fixture-only',
    );
    final bridge = await AudioBridge.start(source);
    final player = AudioPlayer();
    try {
      final files = await source.list('');
      expect(files.where((e) => e.extension == 'flac').length, 3);
      final file = files.firstWhere((e) => e.name == 'tone-24-96000.flac');
      expect(await source.read(file.path, 0, 4), [102, 76, 97, 67]);
      await player.setVolume(0);
      await player
          .setUrl(bridge.register(file).toString())
          .timeout(const Duration(seconds: 25));
      expect(player.duration?.inMilliseconds, closeTo(4000, 100));
      unawaited(player.play());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await player.pause();
      expect(player.position.inMilliseconds, greaterThan(100));
      await player.seek(const Duration(seconds: 2));
      expect(player.position.inMilliseconds, closeTo(2000, 200));
    } finally {
      await player.dispose();
      await bridge.close();
      await source.close();
    }
  });
}
