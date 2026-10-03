import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/playback_clock.dart';

void main() {
  group('PlaybackPositionEstimator', () {
    test('keeps a paused position fixed', () {
      final estimator =
          PlaybackPositionEstimator()..synchronize(
            position: const Duration(seconds: 3),
            elapsed: const Duration(seconds: 10),
            playing: false,
            speed: 1,
            duration: const Duration(seconds: 20),
          );

      expect(
        estimator.positionAt(const Duration(seconds: 12)),
        const Duration(seconds: 3),
      );
    });

    test('advances a playing position using elapsed monotonic time', () {
      final estimator =
          PlaybackPositionEstimator()..synchronize(
            position: const Duration(seconds: 3),
            elapsed: const Duration(seconds: 10),
            playing: true,
            speed: 1,
            duration: const Duration(seconds: 20),
          );

      expect(
        estimator.positionAt(const Duration(milliseconds: 12500)),
        const Duration(milliseconds: 5500),
      );
    });

    test('respects playback speed', () {
      final estimator =
          PlaybackPositionEstimator()..synchronize(
            position: const Duration(seconds: 1),
            elapsed: Duration.zero,
            playing: true,
            speed: 1.5,
            duration: const Duration(seconds: 20),
          );

      expect(
        estimator.positionAt(const Duration(seconds: 2)),
        const Duration(seconds: 4),
      );
    });

    test('replaces the anchor after a seek', () {
      final estimator =
          PlaybackPositionEstimator()..synchronize(
            position: const Duration(seconds: 2),
            elapsed: Duration.zero,
            playing: true,
            speed: 1,
            duration: const Duration(seconds: 30),
          );

      estimator.synchronize(
        position: const Duration(seconds: 15),
        elapsed: const Duration(seconds: 3),
        playing: true,
        speed: 1,
        duration: const Duration(seconds: 30),
      );

      expect(
        estimator.positionAt(const Duration(seconds: 4)),
        const Duration(seconds: 16),
      );
    });

    test('clamps extrapolated positions to the media duration', () {
      final estimator =
          PlaybackPositionEstimator()..synchronize(
            position: const Duration(seconds: 9),
            elapsed: Duration.zero,
            playing: true,
            speed: 1,
            duration: const Duration(seconds: 10),
          );

      expect(
        estimator.positionAt(const Duration(seconds: 5)),
        const Duration(seconds: 10),
      );
    });
  });
}
