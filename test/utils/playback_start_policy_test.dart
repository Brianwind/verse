import 'package:flutter_test/flutter_test.dart';
import 'package:verse/utils/playback_start_policy.dart';

void main() {
  group('isPlaybackStartConfirmed', () {
    test(
      'does not trust immediate Dart playing state before plugin settles',
      () {
        expect(
          isPlaybackStartConfirmed(
            requestActive: true,
            playerPlaying: true,
            processingReady: true,
            elapsedSinceCommand: Duration.zero,
          ),
          isFalse,
        );
      },
    );

    test(
      'confirms playback after ready playing state survives the settle window',
      () {
        expect(
          isPlaybackStartConfirmed(
            requestActive: true,
            playerPlaying: true,
            processingReady: true,
            elapsedSinceCommand: playbackCommandSettleDuration,
          ),
          isTrue,
        );
      },
    );
  });
}
