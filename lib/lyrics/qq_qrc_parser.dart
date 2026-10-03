import 'package:xml/xml.dart';

import 'lyric_models.dart';

class QqQrcParser {
  static final RegExp _linePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  static final RegExp _wordPattern = RegExp(r'\((\d+),(\d+)(?:,[^)]*)?\)');
  static final RegExp _lrcTimePattern = RegExp(
    r'\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]',
  );

  static LyricDocument parse(
    String source, {
    String? translation,
    String? romanization,
  }) {
    final mainText = _extractLyricContent(source);
    if (mainText == null) return LyricDocument.empty;

    final translations = _parseTimedText(translation);
    final romanizations = _parseTimedText(romanization);
    final lines = <LyricLine>[];

    for (final rawLine in mainText.replaceFirst('\uFEFF', '').split('\n')) {
      final match = _linePattern.firstMatch(rawLine.trimRight());
      if (match == null) continue;

      final lineStartMs = int.tryParse(match.group(1)!);
      final lineDurationMs = int.tryParse(match.group(2)!);
      if (lineStartMs == null ||
          lineDurationMs == null ||
          lineStartMs < 0 ||
          lineDurationMs <= 0) {
        continue;
      }

      final words = _parseWords(match.group(3) ?? '');
      final text = words.map((word) => word.text).join();
      if (words.isEmpty || text.trim().isEmpty) continue;

      final lineStart = Duration(milliseconds: lineStartMs);
      final declaredEnd = Duration(milliseconds: lineStartMs + lineDurationMs);
      final end = words.last.end > declaredEnd ? words.last.end : declaredEnd;
      lines.add(
        LyricLine(
          start: lineStart,
          end: end,
          text: text,
          words: List.unmodifiable(words),
          translation: _textNear(lineStart, translations),
          romanization: _textNear(lineStart, romanizations),
        ),
      );
    }

    if (lines.isEmpty) return LyricDocument.empty;
    lines.sort((left, right) => left.start.compareTo(right.start));
    return LyricDocument(lines: List.unmodifiable(lines), isWordTimed: true);
  }

  static List<LyricWord> _parseWords(String body) {
    final matches = _wordPattern.allMatches(body).toList();
    if (matches.isEmpty) return const [];

    final hasLeadingText = body.substring(0, matches.first.start).isNotEmpty;
    final words = <LyricWord>[];
    var previousStart = -1;

    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final startMs = int.tryParse(match.group(1)!);
      final durationMs = int.tryParse(match.group(2)!);
      if (startMs == null ||
          durationMs == null ||
          startMs < previousStart ||
          // Zero-length tokens are common (`？(12846,0)`, a space between
          // phrases); they still carry text and must not drop the line.
          durationMs < 0) {
        return const [];
      }

      final int textStart;
      final int textEnd;
      if (hasLeadingText) {
        textStart = index == 0 ? 0 : matches[index - 1].end;
        textEnd = match.start;
      } else {
        textStart = match.end;
        textEnd =
            index + 1 < matches.length ? matches[index + 1].start : body.length;
      }

      final text = body.substring(textStart, textEnd);
      if (text.isNotEmpty) {
        words.add(
          LyricWord(
            start: Duration(milliseconds: startMs),
            end: Duration(milliseconds: startMs + durationMs),
            text: text,
          ),
        );
      }
      previousStart = startMs;
    }

    return words;
  }

  static List<_TimedText> _parseTimedText(String? source) {
    final text = _extractLyricContent(source);
    if (text == null) return const [];

    final entries = <_TimedText>[];
    for (final rawLine in text.replaceFirst('\uFEFF', '').split('\n')) {
      final line = rawLine.trimRight();
      final qrcMatch = _linePattern.firstMatch(line);
      if (qrcMatch != null) {
        final startMs = int.tryParse(qrcMatch.group(1)!);
        final value = (qrcMatch.group(3) ?? '').replaceAll(_wordPattern, '');
        if (startMs != null && value.trim().isNotEmpty) {
          entries.add(_TimedText(Duration(milliseconds: startMs), value));
        }
        continue;
      }

      final timeMatches = _lrcTimePattern.allMatches(line).toList();
      if (timeMatches.isEmpty) continue;
      final value = line.substring(timeMatches.last.end).trim();
      if (value.isEmpty) continue;

      for (final timeMatch in timeMatches) {
        final minutes = int.parse(timeMatch.group(1)!);
        final seconds = int.parse(timeMatch.group(2)!);
        entries.add(
          _TimedText(
            Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: _fractionToMilliseconds(timeMatch.group(3)),
            ),
            value,
          ),
        );
      }
    }

    entries.sort((left, right) => left.start.compareTo(right.start));
    return entries;
  }

  static String? _extractLyricContent(String? source) {
    final trimmed = source?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (!trimmed.startsWith('<')) return trimmed;

    try {
      final document = XmlDocument.parse(trimmed);
      for (final element in document.descendants.whereType<XmlElement>()) {
        for (final attribute in element.attributes) {
          if (attribute.name.local.toLowerCase() == 'lyriccontent') {
            final content = attribute.value.trim();
            if (content.isNotEmpty) return content;
          }
        }
      }
    } catch (_) {
      // QQ does not escape quotes inside LyricContent, so lyrics such as
      // `"Hello"` make the payload malformed XML. Fall back to a lenient scan.
      return _extractLyricContentLeniently(trimmed);
    }
    return null;
  }

  static final RegExp _lenientContentPattern = RegExp(
    r'LyricContent="([\s\S]*?)"\s*/?>',
    caseSensitive: false,
  );
  static final RegExp _xmlEntityPattern = RegExp(
    r'&(?:#(\d+)|#x([0-9a-fA-F]+)|(amp|lt|gt|quot|apos));',
  );

  static String? _extractLyricContentLeniently(String source) {
    final match = _lenientContentPattern.firstMatch(source);
    final content = match?.group(1)?.trim();
    if (content == null || content.isEmpty) return null;
    return content.replaceAllMapped(_xmlEntityPattern, (entity) {
      final decimal = entity.group(1);
      if (decimal != null) return String.fromCharCode(int.parse(decimal));
      final hex = entity.group(2);
      if (hex != null) return String.fromCharCode(int.parse(hex, radix: 16));
      return const {
        'amp': '&',
        'lt': '<',
        'gt': '>',
        'quot': '"',
        'apos': "'",
      }[entity.group(3)]!;
    });
  }

  static String? _textNear(Duration start, List<_TimedText> entries) {
    _TimedText? best;
    var bestDifference = const Duration(milliseconds: 301);

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

  static int _fractionToMilliseconds(String? fraction) {
    if (fraction == null || fraction.isEmpty) return 0;
    if (fraction.length == 1) return int.parse(fraction) * 100;
    if (fraction.length == 2) return int.parse(fraction) * 10;
    return int.parse(fraction.substring(0, 3));
  }
}

class _TimedText {
  const _TimedText(this.start, this.text);

  final Duration start;
  final String text;
}
