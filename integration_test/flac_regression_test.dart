import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:himusic/playback/player_controller.dart';
import 'package:himusic/sources/local_source.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const root = String.fromEnvironment('FLAC_TEST_DIRECTORY');
  const name = String.fromEnvironment('FLAC_TEST_FILE');
  testWidgets('真实曲目队列跨越原中断点并连续跳转', (tester) async {
    final controller = PlayerController();
    final errors = <PlayerException>[];
    final subscription = controller.player.errorStream.listen(errors.add);
    try {
      await controller.setVolume(0);
      await controller.connect(() => LocalSource.open(root), '');
      expect(controller.error, isNull);
      final entry = controller.entries.singleWhere((e) => e.name == name);
      await controller.playEntry(entry);
      expect(controller.error, isNull);
      for (final seconds in [170, 30, 250]) {
        await controller.seek(Duration(seconds: seconds));
        final duration = seconds == 170 ? 45 : 8;
        for (var i = 0; i < duration; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          expect(errors, isEmpty);
          expect(controller.error, isNull);
        }
        expect(
          controller.player.position.inSeconds,
          greaterThan(seconds + duration - 5),
        );
        expect(controller.player.processingState, ProcessingState.ready);
      }
    } finally {
      await subscription.cancel();
      await controller.shutdown();
    }
  }, skip: root.isEmpty || name.isEmpty);
}
