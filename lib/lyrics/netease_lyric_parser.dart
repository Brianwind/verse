import '../netease_api/netease_music_api.dart';
import 'lyric_models.dart';

class NeteaseLyricParser {
  static final RegExp _yrcLinePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  static final RegExp _yrcWordPattern = RegExp(
    r'\((\d+),(\d+),[^)]*\)([^\(]*)',
  );
  static final RegExp _lrcTimePattern = RegExp(
    r'\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]',
  );

  static LyricDocument parse(SongLyricWrap response) {
    final yrcText = _nonEmpty(response.yrc.lyric);
    if (yrcText != null) {
      final yrcLines = _parseYrc(yrcText);
      if (yrcLines.isNotEmpty) {
        final translations = _parseTimedText(
          _nonEmpty(response.ytlrc.lyric) ?? response.tlyric.lyric,
        );
        final romanizations = _parseTimedText(
          _nonEmpty(response.yromalrc.lyric) ?? response.romalrc.lyric,
        );
        return LyricDocument(
          lines: _attachAlternateTracks(yrcLines, translations, romanizations),
          isWordTimed: true,
        );
      }
    }

    final lrcText = _nonEmpty(response.lrc.lyric);
    if (lrcText == null) {
      return LyricDocument.empty;
    }

    final lines = _parseLrc(lrcText);
    if (lines.isEmpty) {
      return LyricDocument.empty;
    }

    return LyricDocument(
      lines: _attachAlternateTracks(
        lines,
        _parseTimedText(response.tlyric.lyric),
        _parseTimedText(response.romalrc.lyric),
      ),
      isWordTimed: false,
    );
  }

  static List<LyricLine> _parseYrc(String source) {
    final lines = <LyricLine>[];

    for (final rawLine in source.replaceFirst('\uFEFF', '').split('\n')) {
      final lineMatch = _yrcLinePattern.firstMatch(rawLine.trimRight());
      if (lineMatch == null) continue;

      final lineStartMs = int.tryParse(lineMatch.group(1)!);
      final lineDurationMs = int.tryParse(lineMatch.group(2)!);
      if (lineStartMs == null || lineDurationMs == null) continue;

      final words = <LyricWord>[];
      for (final wordMatch in _yrcWordPattern.allMatches(lineMatch.group(3)!)) {
        final wordStartMs = int.tryParse(wordMatch.group(1)!);
        final wordDurationMs = int.tryParse(wordMatch.group(2)!);
        final text = wordMatch.group(3) ?? '';
        if (wordStartMs == null || wordDurationMs == null || text.isEmpty) {
          continue;
        }

        words.add(
          LyricWord(
            start: Duration(milliseconds: wordStartMs),
            end: Duration(milliseconds: wordStartMs + wordDurationMs),
            text: text,
          ),
        );
      }

      final text = words.map((word) => word.text).join();
      if (words.isEmpty || text.trim().isEmpty) continue;

      lines.add(
        LyricLine(
          start: Duration(milliseconds: lineStartMs),
          end: Duration(milliseconds: lineStartMs + lineDurationMs),
          text: text,
          words: List.unmodifiable(words),
        ),
      );
    }

    lines.sort((left, right) => left.start.compareTo(right.start));
    return lines;
  }

  static List<LyricLine> _parseLrc(String source) {
    final entries = _parseTimedText(source);
    final lines = <LyricLine>[];

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final nextStart =
          index + 1 < entries.length ? entries[index + 1].start : null;
      final end =
          nextStart != null && nextStart > entry.start
              ? nextStart
              : entry.start + const Duration(seconds: 5);
      lines.add(LyricLine(start: entry.start, end: end, text: entry.text));
    }

    return lines;
  }

  static List<_TimedText> _parseTimedText(String? source) {
    if (source == null || source.trim().isEmpty) return const [];

    final entries = <_TimedText>[];
    for (final rawLine in source.replaceFirst('\uFEFF', '').split('\n')) {
      final line = rawLine.trimRight();
      final yrcMatch = _yrcLinePattern.firstMatch(line);
      if (yrcMatch != null) {
        final startMs = int.tryParse(yrcMatch.group(1)!);
        final text = yrcMatch.group(3)?.trim() ?? '';
        if (startMs != null && text.isNotEmpty) {
          entries.add(_TimedText(Duration(milliseconds: startMs), text));
        }
        continue;
      }

      final matches = _lrcTimePattern.allMatches(line).toList();
      if (matches.isEmpty) continue;

      final text = line.substring(matches.last.end).trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final milliseconds = _fractionToMilliseconds(match.group(3));
        entries.add(
          _TimedText(
            Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: milliseconds,
            ),
            text,
          ),
        );
      }
    }

    entries.sort((left, right) => left.start.compareTo(right.start));
    return entries;
  }

  static int _fractionToMilliseconds(String? fraction) {
    if (fraction == null || fraction.isEmpty) return 0;
    if (fraction.length == 1) return int.parse(fraction) * 100;
    if (fraction.length == 2) return int.parse(fraction) * 10;
    return int.parse(fraction.substring(0, 3));
  }

  static List<LyricLine> _attachAlternateTracks(
    List<LyricLine> lines,
    List<_TimedText> translations,
    List<_TimedText> romanizations,
  ) {
    return List.unmodifiable(
      lines.map(
        (line) => LyricLine(
          start: line.start,
          end: line.end,
          text: line.text,
          words: line.words,
          translation: _textNear(line.start, translations),
          romanization: _textNear(line.start, romanizations),
        ),
      ),
    );
  }

  static String? _textNear(Duration start, List<_TimedText> entries) {
    _TimedText? best;
    var bestDifference = const Duration(milliseconds: 251);

    for (final entry in entries) {
      final difference = (entry.start - start).abs();
      if (difference < bestDifference) {
        best = entry;
        bestDifference = difference;
      }
      if (entry.start > start + bestDifference) break;
    }

    return best?.text;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : value;
  }
}

class _TimedText {
  final Duration start;
  final String text;

  const _TimedText(this.start, this.text);
}
