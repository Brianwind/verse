import 'package:xml/xml.dart';

import 'lyric_models.dart';

class AmllTtmlParser {
  static LyricDocument parse(String source) {
    if (source.trim().isEmpty) return LyricDocument.empty;

    try {
      final document = XmlDocument.parse(source);
      if (document.rootElement.name.local != 'tt') {
        return LyricDocument.empty;
      }

      final lines = <LyricLine>[];
      for (final paragraph in document.descendants.whereType<XmlElement>()) {
        if (paragraph.name.local != 'p') continue;

        final start = _parseTime(_attribute(paragraph, 'begin'));
        final end = _parseTime(_attribute(paragraph, 'end'));
        if (start == null || end == null || end <= start) continue;

        final words = _parseWords(paragraph);
        final text =
            words.isNotEmpty
                ? words.map((word) => word.text).join()
                : _mainText(paragraph).trim();
        if (text.trim().isEmpty) continue;

        lines.add(
          LyricLine(
            start: start,
            end: end,
            text: text,
            words: List.unmodifiable(words),
            translation: _alternateText(paragraph, 'x-translation'),
            romanization: _alternateText(paragraph, 'x-roman'),
          ),
        );
      }

      if (lines.isEmpty) return LyricDocument.empty;
      lines.sort((left, right) => left.start.compareTo(right.start));
      return LyricDocument(
        lines: List.unmodifiable(lines),
        isWordTimed: lines.any((line) => line.words.isNotEmpty),
      );
    } catch (_) {
      return LyricDocument.empty;
    }
  }

  static List<LyricWord> _parseWords(XmlElement paragraph) {
    final words = <LyricWord>[];

    for (final span in paragraph.descendants.whereType<XmlElement>()) {
      if (span.name.local != 'span' || _isExcluded(span, paragraph)) continue;

      final hasTimedChild = span.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'span')
          .any(_hasTiming);
      if (hasTimedChild) continue;

      final start = _parseTime(_attribute(span, 'begin'));
      final end = _parseTime(_attribute(span, 'end'));
      final text = span.innerText;
      if (start == null || end == null || end <= start || text.isEmpty) {
        continue;
      }

      words.add(LyricWord(start: start, end: end, text: text));
    }

    words.sort((left, right) => left.start.compareTo(right.start));
    return words;
  }

  static bool _hasTiming(XmlElement element) {
    return _attribute(element, 'begin') != null &&
        _attribute(element, 'end') != null;
  }

  static bool _isExcluded(XmlElement element, XmlElement paragraph) {
    XmlNode? current = element;
    while (current is XmlElement && !identical(current, paragraph)) {
      final role = _attribute(current, 'role');
      if (role == 'x-translation' ||
          role == 'x-roman' ||
          role == 'x-bg' ||
          role == 'x-background') {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  static String _mainText(XmlElement paragraph) {
    final buffer = StringBuffer();

    void visit(XmlNode node) {
      if (node is XmlText) {
        buffer.write(node.value);
        return;
      }
      if (node is! XmlElement || _isExcluded(node, paragraph)) return;
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final child in paragraph.children) {
      visit(child);
    }
    return buffer.toString();
  }

  static String? _alternateText(XmlElement paragraph, String expectedRole) {
    final parts = <String>[];
    for (final element in paragraph.descendants.whereType<XmlElement>()) {
      if (_attribute(element, 'role') != expectedRole) continue;
      final text = element.innerText.trim();
      if (text.isNotEmpty) parts.add(text);
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  static String? _attribute(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static Duration? _parseTime(String? source) {
    if (source == null) return null;
    final value = source.trim();
    if (value.isEmpty) return null;

    if (value.endsWith('ms')) {
      final milliseconds = double.tryParse(
        value.substring(0, value.length - 2),
      );
      return milliseconds == null || milliseconds < 0
          ? null
          : Duration(microseconds: (milliseconds * 1000).round());
    }

    if (value.endsWith('s')) {
      final seconds = double.tryParse(value.substring(0, value.length - 1));
      return seconds == null || seconds < 0
          ? null
          : Duration(
            microseconds: (seconds * Duration.microsecondsPerSecond).round(),
          );
    }

    final parts = value.split(':');
    if (parts.length != 2 && parts.length != 3) return null;

    final seconds = double.tryParse(parts.last);
    final minutes = int.tryParse(parts[parts.length - 2]);
    final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
    if (seconds == null ||
        minutes == null ||
        hours == null ||
        seconds < 0 ||
        minutes < 0 ||
        hours < 0) {
      return null;
    }

    final totalSeconds = hours * 3600 + minutes * 60 + seconds;
    return Duration(
      microseconds: (totalSeconds * Duration.microsecondsPerSecond).round(),
    );
  }
}
