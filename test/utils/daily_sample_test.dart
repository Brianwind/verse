import 'package:flutter_test/flutter_test.dart';
import 'package:verse/utils/daily_sample.dart';

void main() {
  group('stableDailySample', () {
    test('selects a stable daily sample instead of the leading items', () {
      final items = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      final sample = stableDailySample(
        items,
        count: 4,
        date: DateTime(2026, 6, 18),
      );

      expect(sample.length, 4);
      expect(sample, isNot(['a', 'b', 'c', 'd']));
      expect(
        stableDailySample(items, count: 4, date: DateTime(2026, 6, 18)),
        sample,
      );
    });

    test(
      'returns every item when the list is shorter than the sample size',
      () {
        expect(
          stableDailySample(['a', 'b'], count: 4, date: DateTime(2026, 6, 18)),
          ['a', 'b'],
        );
      },
    );
  });
}
