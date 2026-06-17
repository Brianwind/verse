import 'package:flutter_test/flutter_test.dart';
import 'package:verse/utils/play_queue.dart';

void main() {
  group('upcomingTrackIndices', () {
    test('returns the next track indices in order mode', () {
      expect(upcomingTrackIndices(currentIndex: 2, trackCount: 5, count: 2), [
        3,
        4,
      ]);
    });

    test('wraps in order mode without returning the current track', () {
      expect(upcomingTrackIndices(currentIndex: 4, trackCount: 5, count: 2), [
        0,
        1,
      ]);
    });

    test('uses shuffle queue indices when a shuffle order is provided', () {
      expect(
        upcomingTrackIndices(
          currentIndex: 1,
          trackCount: 5,
          count: 2,
          shuffleOrder: [2, 4, 1, 3, 0],
        ),
        [1, 3],
      );
    });

    test('does not return the current track for a single-song queue', () {
      expect(
        upcomingTrackIndices(currentIndex: 0, trackCount: 1, count: 2),
        isEmpty,
      );
    });
  });
}
