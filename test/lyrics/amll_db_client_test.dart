import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/amll_db_client.dart';

const _ttml = '<tt xmlns="http://www.w3.org/ns/ttml"><body/></tt>';

void main() {
  group('AmllDbClient', () {
    test(
      'deduplicates concurrent lookups and caches successful TTML',
      () async {
        final response = Completer<String?>();
        var requestCount = 0;
        final client = AmllDbClient(
          remoteLoader: (songId) {
            expect(songId, '1472480890');
            requestCount++;
            return response.future;
          },
        );

        final first = client.fetch('1472480890');
        final second = client.fetch('1472480890');
        expect(requestCount, 1);

        response.complete(_ttml);
        expect(await first, _ttml);
        expect(await second, _ttml);
        expect(await client.fetch('1472480890'), _ttml);
        expect(requestCount, 1);
      },
    );

    test('does not cache a failed lookup', () async {
      var requestCount = 0;
      final client = AmllDbClient(
        remoteLoader: (_) async {
          requestCount++;
          if (requestCount == 1) throw StateError('offline');
          return _ttml;
        },
      );

      expect(await client.fetch('1472480890'), isNull);
      expect(await client.fetch('1472480890'), _ttml);
      expect(requestCount, 2);
    });

    test('rejects a non-TTML response', () async {
      final client = AmllDbClient(
        remoteLoader: (_) async => '<html>not found</html>',
      );

      expect(await client.fetch('1472480890'), isNull);
    });
  });
}
