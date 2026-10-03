class LyricDocument {
  final List<LyricLine> lines;
  final bool isWordTimed;

  const LyricDocument({required this.lines, required this.isWordTimed});

  static const empty = LyricDocument(lines: [], isWordTimed: false);

  bool get isEmpty => lines.isEmpty;

  int lineIndexAt(Duration position) {
    var low = 0;
    var high = lines.length - 1;
    var result = -1;

    while (low <= high) {
      final middle = low + ((high - low) ~/ 2);
      if (lines[middle].start <= position) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }

    return result;
  }
}

class LyricLine {
  final Duration start;
  final Duration end;
  final String text;
  final List<LyricWord> words;
  final String? translation;
  final String? romanization;

  const LyricLine({
    required this.start,
    required this.end,
    required this.text,
    this.words = const [],
    this.translation,
    this.romanization,
  });
}

class LyricWord {
  final Duration start;
  final Duration end;
  final String text;

  const LyricWord({required this.start, required this.end, required this.text});
}
