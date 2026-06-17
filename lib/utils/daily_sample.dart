List<T> stableDailySample<T>(
  List<T> items, {
  required int count,
  required DateTime date,
  String Function(T item)? keyOf,
}) {
  if (count < 1 || items.isEmpty) return const [];
  if (items.length <= count) return List<T>.of(items);

  final seed =
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  final scored = <_ScoredItem<T>>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final key = keyOf?.call(item) ?? item.toString();
    scored.add(_ScoredItem(_stableHash('$seed:$i:$key'), item));
  }

  scored.sort((a, b) => a.score.compareTo(b.score));
  return scored.take(count).map((entry) => entry.item).toList();
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

class _ScoredItem<T> {
  final int score;
  final T item;

  const _ScoredItem(this.score, this.item);
}
