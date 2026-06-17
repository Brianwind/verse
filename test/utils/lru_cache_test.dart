import 'package:flutter_test/flutter_test.dart';
import 'package:verse/utils/lru_cache.dart';

void main() {
  group('LruCache', () {
    test('evicts the least recently used entry when capacity is exceeded', () {
      final cache = LruCache<String, int>(capacity: 2);

      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;

      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.containsKey('c'), isTrue);
    });

    test('reading an entry makes it recent', () {
      final cache = LruCache<String, int>(capacity: 2);

      cache['a'] = 1;
      cache['b'] = 2;
      expect(cache['a'], 1);
      cache['c'] = 3;

      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('c'), isTrue);
    });

    test('clear removes every entry', () {
      final cache = LruCache<String, int>(capacity: 2);

      cache['a'] = 1;
      cache['b'] = 2;
      cache.clear();

      expect(cache.isEmpty, isTrue);
      expect(cache.length, 0);
    });
  });
}
