import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/lyric_source.dart';
import 'package:verse/lyrics/qq_lyric_client.dart';

const _context = LyricSongContext(
  neteaseId: '1500151581',
  title: '群青',
  artists: ['YOASOBI'],
  album: 'THE BOOK',
  duration: Duration(seconds: 248),
);

Map<String, dynamic> _searchData() {
  return {
    'body': {
      'item_song': [
        {
          'id': 1,
          'mid': 'wrong-version',
          'title': '群青 (Live)',
          'interval': 248,
          'singer': [
            {'name': 'YOASOBI'},
          ],
          'album': {'name': 'THE BOOK'},
        },
        {
          'id': 287838659,
          'mid': '0035UDLu1yiTvO',
          'title': '群青',
          'interval': 248,
          'singer': [
            {'name': 'YOASOBI'},
          ],
          'album': {'name': 'THE BOOK'},
        },
      ],
    },
  };
}

void main() {
  group('QqLyricClient', () {
    test(
      'searches top candidates and fetches only the best reliable match',
      () async {
        final calls = <String>[];
        Map<String, dynamic>? lyricParameters;
        final client = QqLyricClient(
          request: ({
            required method,
            required module,
            required parameters,
          }) async {
            calls.add(method);
            if (method == 'DoSearchForQQMusicLite') {
              expect(module, 'music.search.SearchCgiService');
              expect(parameters['num_per_page'], 10);
              return _searchData();
            }
            lyricParameters = parameters;
            return {'lyric': 'encrypted'};
          },
          decoder:
              (_) async => const QqDecryptedTracks(
                lyric: '[1000,800](1000,400)群(1400,400)青',
              ),
        );

        final document = await client.fetch(_context);

        expect(calls, ['DoSearchForQQMusicLite', 'GetPlayLyricInfo']);
        expect(lyricParameters?['songID'], 287838659);
        expect(lyricParameters?['qrc'], 1);
        expect(document?.lines.single.text, '群青');
        expect(document?.isWordTimed, isTrue);
      },
    );

    test('decodes translation and romanization tracks', () async {
      final client = QqLyricClient(
        request: ({
          required method,
          required module,
          required parameters,
        }) async {
          return method == 'DoSearchForQQMusicLite'
              ? _searchData()
              : {'lyric': 'main', 'trans': 'translated', 'roma': 'romanized'};
        },
        decoder: (tracks) async {
          expect(tracks.translation, 'translated');
          expect(tracks.romanization, 'romanized');
          return const QqDecryptedTracks(
            lyric: '[1000,800](1000,400)群(1400,400)青',
            translation: '[00:01.00]蓝色',
            romanization: '[00:01.00]gunjou',
          );
        },
      );

      final document = await client.fetch(_context);

      expect(document?.lines.single.translation, '蓝色');
      expect(document?.lines.single.romanization, 'gunjou');
    });

    test('caches successful documents', () async {
      var requestCount = 0;
      final client = QqLyricClient(
        request: ({
          required method,
          required module,
          required parameters,
        }) async {
          requestCount++;
          return method == 'DoSearchForQQMusicLite'
              ? _searchData()
              : {'lyric': 'encrypted'};
        },
        decoder:
            (_) async => const QqDecryptedTracks(
              lyric: '[1000,800](1000,400)群(1400,400)青',
            ),
      );

      final first = await client.fetch(_context);
      final second = await client.fetch(_context);

      expect(identical(first, second), isTrue);
      expect(requestCount, 2);
    });

    test('coalesces concurrent lookups for the same song', () async {
      final search = Completer<Map<String, dynamic>>();
      var searchCount = 0;
      final client = QqLyricClient(
        request: ({
          required method,
          required module,
          required parameters,
        }) async {
          if (method == 'DoSearchForQQMusicLite') {
            searchCount++;
            return search.future;
          }
          return {'lyric': 'encrypted'};
        },
        decoder:
            (_) async => const QqDecryptedTracks(
              lyric: '[1000,800](1000,400)群(1400,400)青',
            ),
      );

      final first = client.fetch(_context);
      final second = client.fetch(_context);
      search.complete(_searchData());

      expect(await first, isNotNull);
      expect(await second, isNotNull);
      expect(searchCount, 1);
    });

    test(
      'falls back to a short query when the precise search misses',
      () async {
        final queries = <String>[];
        final client = QqLyricClient(
          request: ({
            required method,
            required module,
            required parameters,
          }) async {
            if (method == 'DoSearchForQQMusicLite') {
              queries.add(parameters['query'] as String);
              return queries.length == 1
                  ? {
                    'body': {'item_song': <Object>[]},
                  }
                  : _searchData();
            }
            return {'lyric': 'encrypted'};
          },
          decoder:
              (_) async => const QqDecryptedTracks(
                lyric: '[1000,800](1000,400)群(1400,400)青',
              ),
        );

        final document = await client.fetch(
          const LyricSongContext(
            neteaseId: '1',
            title: '群青 (feat. Someone)',
            artists: ['YOASOBI', 'Someone'],
            album: 'THE BOOK',
            duration: Duration(seconds: 248),
          ),
        );

        expect(queries, [
          '群青 (feat. Someone) YOASOBI Someone THE BOOK',
          '群青 YOASOBI',
        ]);
        expect(document?.lines.single.text, '群青');
      },
    );

    test('tries the next candidate when the best one has no QRC', () async {
      final fetchedIds = <Object?>[];
      final client = QqLyricClient(
        request: ({
          required method,
          required module,
          required parameters,
        }) async {
          if (method == 'DoSearchForQQMusicLite') {
            return {
              'body': {
                'item_song': [
                  for (final (id, mid) in [(10, 'plain'), (11, 'timed')])
                    {
                      'id': id,
                      'mid': mid,
                      'title': '群青',
                      'interval': 248,
                      'singer': [
                        {'name': 'YOASOBI'},
                      ],
                      'album': {'name': 'THE BOOK'},
                    },
                ],
              },
            };
          }
          fetchedIds.add(parameters['songID']);
          return {'lyric': 'song-${parameters['songID']}'};
        },
        decoder:
            (tracks) async => QqDecryptedTracks(
              lyric:
                  tracks.lyric == 'song-10'
                      ? '[00:01.00]群青'
                      : '[1000,800](1000,400)群(1400,400)青',
            ),
      );

      final document = await client.fetch(_context);

      expect(fetchedIds, [10, 11]);
      expect(document?.isWordTimed, isTrue);
    });

    test('returns null when the source budget expires', () async {
      final never = Completer<Map<String, dynamic>>();
      final client = QqLyricClient(
        request: ({required method, required module, required parameters}) {
          return never.future;
        },
        sourceTimeout: const Duration(milliseconds: 20),
      );

      expect(await client.fetch(_context), isNull);
    });
  });
}
