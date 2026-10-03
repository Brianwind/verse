import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'lyric_models.dart';

@immutable
class LyricHighlightState {
  const LyricHighlightState({
    required this.hasWordTiming,
    required this.paintWholeLine,
    required this.completedTextEnd,
    this.activeWordRange,
    this.activeWordProgress = 0,
  });

  final bool hasWordTiming;
  final bool paintWholeLine;
  final int completedTextEnd;
  final TextRange? activeWordRange;
  final double activeWordProgress;

  @override
  bool operator ==(Object other) {
    return other is LyricHighlightState &&
        other.hasWordTiming == hasWordTiming &&
        other.paintWholeLine == paintWholeLine &&
        other.completedTextEnd == completedTextEnd &&
        other.activeWordRange == activeWordRange &&
        other.activeWordProgress == activeWordProgress;
  }

  @override
  int get hashCode => Object.hash(
    hasWordTiming,
    paintWholeLine,
    completedTextEnd,
    activeWordRange,
    activeWordProgress,
  );
}

/// Character range of each timed word inside [LyricLine.text], in word order.
List<TextRange> lyricWordRanges(LyricLine line) {
  final ranges = <TextRange>[];
  var searchOffset = 0;
  for (final word in line.words) {
    var wordStart = line.text.indexOf(word.text, searchOffset);
    if (wordStart < 0) {
      wordStart = searchOffset;
    }
    final wordEnd = (wordStart + word.text.length).clamp(
      wordStart,
      line.text.length,
    );
    searchOffset = wordEnd;
    ranges.add(TextRange(start: wordStart, end: wordEnd));
  }
  return ranges;
}

/// folia Monet's word glow envelope: rises over the word's duration, then
/// lingers and fades out by the end of the line (smoothstep on both sides).
double lyricWordGlowAt(Duration position, LyricWord word, Duration lineEnd) {
  final time = position.inMicroseconds / 1e6;
  final start = word.start.inMicroseconds / 1e6;
  final end = word.end.inMicroseconds / 1e6;
  if (time <= start) return 0;

  double smoothstep(double value) {
    final t = value.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  final rise = math.max(0.001, end - start) * 1.18;
  final peak = start + rise;
  if (time <= peak) return smoothstep((time - start) / rise);
  final tail = math.max(lineEnd.inMicroseconds / 1e6, end + 1.05);
  return smoothstep(1 - (time - peak) / math.max(0.18, tail - peak));
}

LyricHighlightState lyricHighlightAt(LyricLine line, Duration position) {
  if (line.words.isEmpty) {
    return const LyricHighlightState(
      hasWordTiming: false,
      paintWholeLine: true,
      completedTextEnd: 0,
    );
  }

  var searchOffset = 0;
  var completedTextEnd = 0;
  for (final word in line.words) {
    var wordStart = line.text.indexOf(word.text, searchOffset);
    if (wordStart < 0) {
      wordStart = searchOffset;
    }
    final wordEnd = (wordStart + word.text.length).clamp(
      wordStart,
      line.text.length,
    );
    searchOffset = wordEnd;

    if (position >= word.end) {
      completedTextEnd = wordEnd;
      continue;
    }
    if (position < word.start) {
      break;
    }

    final wordDuration = word.end - word.start;
    final progress =
        wordDuration <= Duration.zero
            ? 1.0
            : ((position - word.start).inMicroseconds /
                    wordDuration.inMicroseconds)
                .clamp(0.0, 1.0);
    return LyricHighlightState(
      hasWordTiming: true,
      paintWholeLine: false,
      completedTextEnd: completedTextEnd,
      activeWordRange: TextRange(start: wordStart, end: wordEnd),
      activeWordProgress: progress,
    );
  }

  return LyricHighlightState(
    hasWordTiming: true,
    paintWholeLine: false,
    completedTextEnd: completedTextEnd,
  );
}

class TimedLyricText extends StatelessWidget {
  const TimedLyricText({
    super.key,
    required this.line,
    required this.position,
    required this.style,
    required this.baseColor,
    required this.highlightColor,
    this.glowColor,
    this.textAlign = TextAlign.left,
  });

  final LyricLine line;
  final ValueListenable<Duration> position;
  final TextStyle style;
  final Color baseColor;
  final Color highlightColor;

  /// Halo around words as they are sung; null disables the glow.
  final Color? glowColor;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final textScaler =
        MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling;

    return CustomPaint(
      painter: TimedLyricPainter(
        line: line,
        position: position,
        style: style,
        baseColor: baseColor,
        highlightColor: highlightColor,
        glowColor: glowColor,
        textAlign: textAlign,
        textDirection: textDirection,
        textScaler: textScaler,
      ),
      child: Text(
        line.text,
        style: style.copyWith(color: Colors.transparent),
        textAlign: textAlign,
      ),
    );
  }
}

class TimedLyricPainter extends CustomPainter {
  TimedLyricPainter({
    required this.line,
    required this.position,
    required this.style,
    required this.baseColor,
    required this.highlightColor,
    this.glowColor,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
  }) : super(repaint: position);

  final LyricLine line;
  final ValueListenable<Duration> position;
  final TextStyle style;
  final Color baseColor;
  final Color highlightColor;
  final Color? glowColor;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final basePainter = _textPainter(baseColor)..layout(maxWidth: size.width);
    final highlightPainter = _textPainter(highlightColor)
      ..layout(maxWidth: size.width);

    _paintGlow(canvas, size);
    basePainter.paint(canvas, Offset.zero);

    final highlight = lyricHighlightAt(line, position.value);
    if (highlight.paintWholeLine) {
      highlightPainter.paint(canvas, Offset.zero);
      return;
    }

    final clipPath = Path();
    if (highlight.completedTextEnd > 0) {
      _addSelectionToPath(
        clipPath,
        highlightPainter,
        TextRange(start: 0, end: highlight.completedTextEnd),
      );
    }

    final activeWordRange = highlight.activeWordRange;
    if (activeWordRange != null && highlight.activeWordProgress > 0) {
      _addPartialSelectionToPath(
        clipPath,
        highlightPainter,
        activeWordRange,
        highlight.activeWordProgress,
      );
    }

    if (clipPath.getBounds().isEmpty) return;
    canvas.save();
    canvas.clipPath(clipPath);
    highlightPainter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  /// Paints only the halos (the glyphs stay transparent) under the fill.
  void _paintGlow(Canvas canvas, Size size) {
    final glowColor = this.glowColor;
    if (glowColor == null || line.words.isEmpty) return;

    final now = position.value;
    final ranges = lyricWordRanges(line);
    final fontSize = style.fontSize ?? 14;
    final spans = <TextSpan>[];
    var cursor = 0;
    var glowing = false;
    for (var index = 0; index < line.words.length; index++) {
      final range = ranges[index];
      if (range.start < cursor) continue;
      if (range.start > cursor) {
        spans.add(TextSpan(text: line.text.substring(cursor, range.start)));
      }
      final intensity = lyricWordGlowAt(now, line.words[index], line.end);
      final color = glowColor.withValues(alpha: glowColor.a * intensity);
      glowing |= intensity > 0;
      spans.add(
        TextSpan(
          text: line.text.substring(range.start, range.end),
          style:
              intensity <= 0
                  ? null
                  : TextStyle(
                    shadows: [
                      Shadow(color: color, blurRadius: fontSize * 0.28),
                      Shadow(color: color, blurRadius: fontSize * 0.65),
                    ],
                  ),
        ),
      );
      cursor = range.end;
    }
    if (!glowing) return;
    if (cursor < line.text.length) {
      spans.add(TextSpan(text: line.text.substring(cursor)));
    }

    TextPainter(
        text: TextSpan(
          style: style.copyWith(color: const Color(0x00000000)),
          children: spans,
        ),
        textAlign: textAlign,
        textDirection: textDirection,
        textScaler: textScaler,
      )
      ..layout(maxWidth: size.width)
      ..paint(canvas, Offset.zero);
  }

  TextPainter _textPainter(Color color) {
    return TextPainter(
      text: TextSpan(text: line.text, style: style.copyWith(color: color)),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
    );
  }

  void _addSelectionToPath(Path path, TextPainter painter, TextRange range) {
    for (final box in painter.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
      boxHeightStyle: BoxHeightStyle.tight,
      boxWidthStyle: BoxWidthStyle.tight,
    )) {
      path.addRect(box.toRect());
    }
  }

  void _addPartialSelectionToPath(
    Path path,
    TextPainter painter,
    TextRange range,
    double progress,
  ) {
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
      boxHeightStyle: BoxHeightStyle.tight,
      boxWidthStyle: BoxWidthStyle.tight,
    );
    var remainingWidth =
        boxes.fold<double>(0, (sum, box) => sum + box.toRect().width) *
        progress.clamp(0.0, 1.0);

    for (final box in boxes) {
      if (remainingWidth <= 0) break;
      final rect = box.toRect();
      final paintedWidth = remainingWidth.clamp(0.0, rect.width);
      final paintedRect =
          box.direction == TextDirection.rtl
              ? Rect.fromLTRB(
                rect.right - paintedWidth,
                rect.top,
                rect.right,
                rect.bottom,
              )
              : Rect.fromLTRB(
                rect.left,
                rect.top,
                rect.left + paintedWidth,
                rect.bottom,
              );
      path.addRect(paintedRect);
      remainingWidth -= rect.width;
    }
  }

  @override
  bool shouldRepaint(covariant TimedLyricPainter oldDelegate) {
    return oldDelegate.line != line ||
        oldDelegate.position != position ||
        oldDelegate.style != style ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler;
  }
}
