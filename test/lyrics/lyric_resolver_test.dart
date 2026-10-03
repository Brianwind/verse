import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/lyric_models.dart';
import 'package:verse/lyrics/lyric_resolver.dart';
import 'package:verse/lyrics/lyric_source.dart';
import 'package:verse/netease_api/netease_music_api.dart';

const _context = LyricSongContext(
  neteaseId: '1500151581',
  title: '群青',
  artists: ['YOASOBI'],
  album: 'THE BOOK',
  duration: Duration(seconds: 248),
);

const _amllTtml = '''
<tt xmlns="http://www.w3.org/ns/ttml"><body><div>
  <p begin="00:01.000" end="00:02.000">
    <span begin="00:01.000" end="00:01.500">群</span>
    <span begin="00:01.500" end="00:02.000">青</span>
  </p>
</div></body></tt>
''';

const _qqDocument = LyricDocument(
  lines: [
    LyricLine(
      start: Duration(seconds: 1),
      end: Duration(seconds: 2),
      text: 'QQ群青',
      words: [
        LyricWord(
          start: Duration(seconds: 1),
          end: Duration(milliseconds: 1500),
          text: 'QQ',
        ),
        LyricWord(
          start: Duration(milliseconds: 1500),
          end: Duration(seconds: 2),
          text: '群青',
        ),
      ],
    ),
  ],
  isWordTimed: true,
);

SongLyricWrap _response({String? lrc, String? yrc}) {
  return SongLyricWrap.fromJson({
    'code': 200,
    'lrc': {'lyric': lrc},
    'klyric': <String, dynamic>{},
    'tlyric': <String, dynamic>{},
    'yrc': {'lyric': yrc},
    'ytlrc': <String, dynamic>{},
    'romalrc': <String, dynamic>{},
    'yromalrc': <String, dynamic>{},
  });
}

void main() {
  group('LyricResolver', () {
    test('starts every provider before awaiting the first result', () async {
      final netease = Completer<SongLyricWrap>();
      final amll = Completer<String?>();
      final qq = Completer<LyricDocument?>();
      var neteaseStarted = false;
      var amllStarted = false;
      var qqStarted = false;
      final resolver = LyricResolver(
        neteaseLoader: (_) {
          neteaseStarted = true;
          return netease.future;
        },
        amllLoader: (_) {
          amllStarted = true;
          return amll.future;
        },
        qqLoader: (_) {
          qqStarted = true;
          return qq.future;
        },
      );

      final result = resolver.load(_context);
      await Future<void>.delayed(Duration.zero);

      expect(neteaseStarted, isTrue);
      expect(amllStarted, isTrue);
      expect(qqStarted, isTrue);

      netease.complete(_response(lrc: '[00:01.00]普通歌词'));
      amll.complete(null);
      qq.complete(_qqDocument);
      expect((await result).lines.single.text, 'QQ群青');
    });

    test(
      'prefers NetEase YRC while lower-priority requests still start',
      () async {
        final selected = <LyricSource>[];
        var amllRequestCount = 0;
        var qqRequestCount = 0;
        final resolver = LyricResolver(
          neteaseLoader:
              (_) async =>
                  _response(yrc: '[1000,1000](1000,500,0)群(1500,500,0)青'),
          amllLoader: (_) async {
            amllRequestCount++;
            return _amllTtml;
          },
          qqLoader: (_) async {
            qqRequestCount++;
            return _qqDocument;
          },
          sourceReporter: selected.add,
        );

        final document = await resolver.load(_context);

        expect(document.lines.single.text, '群青');
        expect(document.isWordTimed, isTrue);
        expect(amllRequestCount, 1);
        expect(qqRequestCount, 1);
        expect(selected, [LyricSource.netease]);
      },
    );

    test('prefers AMLLDB over QQ when NetEase only has LRC', () async {
      final selected = <LyricSource>[];
      final resolver = LyricResolver(
        neteaseLoader: (_) async => _response(lrc: '[00:00.90]普通歌词'),
        amllLoader: (_) async => _amllTtml,
        qqLoader: (_) async => _qqDocument,
        sourceReporter: selected.add,
      );

      final document = await resolver.load(_context);

      expect(document.isWordTimed, isTrue);
      expect(document.lines.single.text, '群青');
      expect(selected, [LyricSource.amllDb]);
    });

    test('uses QQ QRC after NetEase and AMLLDB word timing miss', () async {
      final selected = <LyricSource>[];
      final resolver = LyricResolver(
        neteaseLoader: (_) async => _response(lrc: '[00:00.90]普通歌词'),
        amllLoader: (_) async => null,
        qqLoader: (context) async {
          expect(context.title, '群青');
          return _qqDocument;
        },
        sourceReporter: selected.add,
      );

      final document = await resolver.load(_context);

      expect(document.lines.single.text, 'QQ群青');
      expect(selected, [LyricSource.qqMusic]);
    });

    test('falls back to NetEase LRC when word-timed sources miss', () async {
      final selected = <LyricSource>[];
      final resolver = LyricResolver(
        neteaseLoader: (_) async => _response(lrc: '[00:00.90]普通歌词'),
        amllLoader: (_) async => null,
        qqLoader: (_) async => null,
        sourceReporter: selected.add,
      );

      final document = await resolver.load(_context);

      expect(document.isWordTimed, isFalse);
      expect(document.lines.single.text, '普通歌词');
      expect(selected, [LyricSource.netease]);
    });

    test('isolates provider failures', () async {
      final resolver = LyricResolver(
        neteaseLoader: (_) async => throw StateError('NetEase offline'),
        amllLoader: (_) async => throw StateError('AMLLDB offline'),
        qqLoader: (_) async => _qqDocument,
        sourceReporter: (_) {},
      );

      expect((await resolver.load(_context)).lines.single.text, 'QQ群青');
    });
  });
}
