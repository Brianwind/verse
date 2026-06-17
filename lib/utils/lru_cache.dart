import 'dart:collection';

class LruCache<K, V> {
  final int capacity;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  LruCache({required this.capacity}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  bool containsKey(K key) => _entries.containsKey(key);

  V? operator [](K key) {
    if (!_entries.containsKey(key)) return null;
    final value = _entries.remove(key) as V;
    _entries[key] = value;
    return value;
  }

  void operator []=(K key, V value) {
    if (_entries.containsKey(key)) {
      _entries.remove(key);
    } else if (_entries.length >= capacity) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = value;
  }

  void remove(K key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }
}
