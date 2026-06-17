List<int> upcomingTrackIndices({
  required int currentIndex,
  required int trackCount,
  required int count,
  List<int>? shuffleOrder,
}) {
  if (currentIndex < 0 || trackCount < 2 || count < 1) return const [];

  final limit = count < trackCount - 1 ? count : trackCount - 1;
  final indices = <int>[];

  if (shuffleOrder != null) {
    if (shuffleOrder.length != trackCount ||
        currentIndex >= shuffleOrder.length) {
      return const [];
    }

    for (var offset = 1; offset <= limit; offset++) {
      final queueIndex = (currentIndex + offset) % shuffleOrder.length;
      final trackIndex = shuffleOrder[queueIndex];
      if (trackIndex >= 0 && trackIndex < trackCount) {
        indices.add(trackIndex);
      }
    }
    return indices;
  }

  if (currentIndex >= trackCount) return const [];
  for (var offset = 1; offset <= limit; offset++) {
    indices.add((currentIndex + offset) % trackCount);
  }
  return indices;
}
