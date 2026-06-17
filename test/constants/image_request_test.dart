import 'package:flutter_test/flutter_test.dart';
import 'package:verse/constants/image_request.dart';

void main() {
  group('normalizeImageUrl', () {
    test('adds a size parameter to NetEase image urls without one', () {
      final url = normalizeImageUrl(
        'https://p1.music.126.net/byLZvZCKEjy_1-mSpbdxIg==/109951164683822178.jpg',
      );

      expect(
        url,
        'https://p1.music.126.net/byLZvZCKEjy_1-mSpbdxIg==/109951164683822178.jpg?param=512y512',
      );
    });

    test('keeps existing NetEase image size parameters', () {
      final url = normalizeImageUrl(
        'http://p1.music.126.net/image.jpg?param=160y160',
      );

      expect(url, 'https://p1.music.126.net/image.jpg?param=160y160');
    });
  });
}
