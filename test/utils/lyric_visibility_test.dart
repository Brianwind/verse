import 'package:flutter_test/flutter_test.dart';
import 'package:verse/utils/lyric_visibility.dart';

void main() {
  group('isLyricLineVisible', () {
    test(
      'keeps only the current lyric and three nearby lines on each side',
      () {
        final visible = [
          for (var i = 0; i < 12; i++)
            if (isLyricLineVisible(index: i, currentIndex: 6, lineCount: 12)) i,
        ];

        expect(visible, [3, 4, 5, 6, 7, 8, 9]);
      },
    );

    test(
      'uses the first lyric as the visible center before playback advances',
      () {
        final visible = [
          for (var i = 0; i < 8; i++)
            if (isLyricLineVisible(index: i, currentIndex: -1, lineCount: 8)) i,
        ];

        expect(visible, [0, 1, 2, 3]);
      },
    );
  });

  group('lyricLineVisibilityOpacity', () {
    test(
      'keeps nearby lyrics opaque and hides distant lyrics with opacity',
      () {
        expect(
          lyricLineVisibilityOpacity(index: 5, currentIndex: 5, lineCount: 12),
          1.0,
        );
        expect(
          lyricLineVisibilityOpacity(index: 8, currentIndex: 5, lineCount: 12),
          1.0,
        );
        expect(
          lyricLineVisibilityOpacity(index: 9, currentIndex: 5, lineCount: 12),
          0.0,
        );
      },
    );
  });
}
