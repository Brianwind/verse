int effectiveLyricIndex({required int currentIndex, required int lineCount}) {
  if (lineCount <= 0) return -1;
  return currentIndex.clamp(0, lineCount - 1);
}

bool isLyricLineVisible({
  required int index,
  required int currentIndex,
  required int lineCount,
  int radius = 3,
}) {
  if (lineCount <= 0 || index < 0 || index >= lineCount || radius < 0) {
    return false;
  }

  final center = effectiveLyricIndex(
    currentIndex: currentIndex,
    lineCount: lineCount,
  );
  return (index - center).abs() <= radius;
}

double lyricLineVisibilityOpacity({
  required int index,
  required int currentIndex,
  required int lineCount,
  int radius = 3,
}) {
  return isLyricLineVisible(
        index: index,
        currentIndex: currentIndex,
        lineCount: lineCount,
        radius: radius,
      )
      ? 1.0
      : 0.0;
}
