import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/lyric_models.dart';
import 'package:verse/lyrics/timed_lyric_text.dart';

void main() {
  const firstWord = LyricWord(
    start: Duration.zero,
    end: Duration(seconds: 1),
    text: 'hello ',
  );
  const secondWord = LyricWord(
    start: Duration(seconds: 1),
    end: Duration(seconds: 2),
    text: 'world',
  );
  const line = LyricLine(
    start: Duration.zero,
    end: Duration(seconds: 2),
    text: 'hello world',
    words: [firstWord, secondWord],
  );

  group('lyricHighlightAt', () {
    test('advances the active word fill with playback time', () {
      final firstHalf = lyricHighlightAt(
        line,
        const Duration(milliseconds: 500),
      );
      final secondHalf = lyricHighlightAt(
        line,
        const Duration(milliseconds: 1500),
      );

      expect(firstHalf.completedTextEnd, 0);
      expect(firstHalf.activeWordRange, const TextRange(start: 0, end: 6));
      expect(firstHalf.activeWordProgress, closeTo(0.5, 0.001));
      expect(secondHalf.completedTextEnd, 6);
      expect(secondHalf.activeWordRange, const TextRange(start: 6, end: 11));
      expect(secondHalf.activeWordProgress, closeTo(0.5, 0.001));
    });

    test('does not include future glyphs in the highlighted range', () {
      final state = lyricHighlightAt(line, const Duration(milliseconds: 500));

      expect(state.completedTextEnd, lessThan(firstWord.text.length));
      expect(state.activeWordRange!.end, firstWord.text.length);
      expect(state.activeWordRange!.end, lessThan(line.text.length));
    });

    test('keeps a Unicode grapheme sequence inside one timed word range', () {
      const astronaut = '👩‍🚀';
      const unicodeLine = LyricLine(
        start: Duration.zero,
        end: Duration(seconds: 2),
        text: '$astronaut 出発',
        words: [
          LyricWord(
            start: Duration.zero,
            end: Duration(seconds: 1),
            text: astronaut,
          ),
          LyricWord(
            start: Duration(seconds: 1),
            end: Duration(seconds: 2),
            text: ' 出発',
          ),
        ],
      );

      final state = lyricHighlightAt(
        unicodeLine,
        const Duration(milliseconds: 500),
      );

      expect(state.activeWordRange, TextRange(start: 0, end: astronaut.length));
    });

    test('renders an LRC-only line as a static current line', () {
      const lrcLine = LyricLine(
        start: Duration(seconds: 1),
        end: Duration(seconds: 5),
        text: 'line timed only',
      );

      final early = lyricHighlightAt(lrcLine, const Duration(seconds: 2));
      final late = lyricHighlightAt(lrcLine, const Duration(seconds: 4));

      expect(early.hasWordTiming, isFalse);
      expect(early.paintWholeLine, isTrue);
      expect(late.hasWordTiming, isFalse);
      expect(late.paintWholeLine, isTrue);
      expect(late, early);
    });
  });

  group('lyricWordGlowAt', () {
    test('rises while the word is sung and fades after it', () {
      Duration ms(int value) => Duration(milliseconds: value);
      final lineEnd = line.end;

      expect(lyricWordGlowAt(Duration.zero, firstWord, lineEnd), 0);
      final rising = lyricWordGlowAt(ms(500), firstWord, lineEnd);
      final peak = lyricWordGlowAt(ms(1180), firstWord, lineEnd);
      final fading = lyricWordGlowAt(ms(1800), firstWord, lineEnd);

      expect(rising, inExclusiveRange(0, 1));
      expect(peak, closeTo(1, 0.001));
      expect(fading, inExclusiveRange(0, peak));
      expect(lyricWordGlowAt(ms(4000), firstWord, lineEnd), 0);
    });
  });

  testWidgets('clock changes repaint without rebuilding the parent', (
    tester,
  ) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    var parentBuildCount = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            parentBuildCount++;
            return SizedBox(
              width: 300,
              child: TimedLyricText(
                line: line,
                position: position,
                style: const TextStyle(fontSize: 30),
                baseColor: Colors.white38,
                highlightColor: Colors.white,
                glowColor: Colors.amber,
              ),
            );
          },
        ),
      ),
    );

    expect(parentBuildCount, 1);

    position.value = const Duration(milliseconds: 500);
    await tester.pump();

    expect(parentBuildCount, 1);
    expect(tester.takeException(), isNull);

    position.dispose();
  });
}
