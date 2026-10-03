import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/lyric_resolver.dart';
import 'package:verse/lyrics/lyric_models.dart';
import 'package:verse/lyrics/timed_lyric_text.dart';
import 'package:verse/lyrics_view.dart';
import 'package:verse/netease_api/netease_music_api.dart';

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

Widget _app({
  required String songId,
  required ValueNotifier<Duration> position,
  required LyricsLoader loader,
  AmllLyricsLoader? amllLoader,
  QqLyricsLoader? qqLoader,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 620,
        height: 700,
        child: LyricsView(
          songId: songId,
          position: position,
          lyricsLoader: loader,
          amllLyricsLoader: amllLoader ?? (_) async => null,
          qqLyricsLoader: qqLoader ?? (_) async => null,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the active YRC line with timed word painting', (
    tester,
  ) async {
    final position = ValueNotifier<Duration>(const Duration(milliseconds: 500));

    await tester.pumpWidget(
      _app(
        songId: '1',
        position: position,
        loader:
            (_) async =>
                _response(yrc: '[0,2000](0,1000,0)hello (1000,1000,0)world'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimedLyricText), findsOneWidget);
    expect(
      tester.widget<TimedLyricText>(find.byType(TimedLyricText)).line.text,
      'hello world',
    );

    position.dispose();
  });

  testWidgets('renders AMLLDB word timing when NetEase only has LRC', (
    tester,
  ) async {
    final position = ValueNotifier<Duration>(
      const Duration(milliseconds: 1500),
    );

    await tester.pumpWidget(
      _app(
        songId: '1472480890',
        position: position,
        loader: (_) async => _response(lrc: '[00:01.00]普通歌词'),
        amllLoader:
            (_) async => '''
<tt xmlns="http://www.w3.org/ns/ttml"><body><div>
  <p begin="00:01.000" end="00:02.000">
    <span begin="00:01.000" end="00:01.500">群</span>
    <span begin="00:01.500" end="00:02.000">青</span>
  </p>
</div></body></tt>
''',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimedLyricText), findsOneWidget);
    expect(
      tester.widget<TimedLyricText>(find.byType(TimedLyricText)).line.text,
      '群青',
    );

    position.dispose();
  });

  testWidgets('renders QQ QRC word timing after higher-priority misses', (
    tester,
  ) async {
    final position = ValueNotifier<Duration>(
      const Duration(milliseconds: 1500),
    );
    const qqDocument = LyricDocument(
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

    await tester.pumpWidget(
      _app(
        songId: '1500151581',
        position: position,
        loader: (_) async => _response(lrc: '[00:01.00]普通歌词'),
        qqLoader: (_) async => qqDocument,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimedLyricText), findsOneWidget);
    expect(
      tester.widget<TimedLyricText>(find.byType(TimedLyricText)).line.text,
      'QQ群青',
    );

    position.dispose();
  });

  testWidgets('ignores an older lyric response after a rapid song change', (
    tester,
  ) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    final firstResponse = Completer<SongLyricWrap>();
    final secondResponse = Completer<SongLyricWrap>();
    Future<SongLyricWrap> loader(String songId) {
      return songId == 'first' ? firstResponse.future : secondResponse.future;
    }

    await tester.pumpWidget(
      _app(songId: 'first', position: position, loader: loader),
    );
    await tester.pumpWidget(
      _app(songId: 'second', position: position, loader: loader),
    );

    firstResponse.complete(_response(yrc: '[0,1000](0,1000,0)obsolete lyric'));
    await tester.pump();
    expect(find.text('obsolete lyric'), findsNothing);

    secondResponse.complete(_response(yrc: '[0,1000](0,1000,0)current lyric'));
    await tester.pumpAndSettle();

    expect(find.text('obsolete lyric'), findsNothing);
    expect(find.text('current lyric'), findsOneWidget);

    position.dispose();
  });

  testWidgets('keeps the existing animated transition when the line changes', (
    tester,
  ) async {
    final position = ValueNotifier<Duration>(const Duration(milliseconds: 500));

    await tester.pumpWidget(
      _app(
        songId: '1',
        position: position,
        loader:
            (_) async => _response(
              yrc:
                  '[0,1500](0,1500,0)first line\n'
                  '[2000,1500](2000,1500,0)second line',
            ),
      ),
    );
    await tester.pumpAndSettle();

    position.value = const Duration(milliseconds: 2500);
    await tester.pump();

    final transitions = tester.widgetList<TweenAnimationBuilder<double>>(
      find.byWidgetPredicate(
        (widget) => widget is TweenAnimationBuilder<double>,
      ),
    );
    expect(
      transitions.any(
        (widget) => widget.duration == const Duration(milliseconds: 500),
      ),
      isTrue,
    );

    position.dispose();
  });

  testWidgets(
    'shows romanization then translation only under the current line',
    (tester) async {
      final position = ValueNotifier<Duration>(
        const Duration(milliseconds: 2500),
      );
      const document = LyricDocument(
        lines: [
          LyricLine(
            start: Duration(seconds: 0),
            end: Duration(seconds: 2),
            text: '前の歌詞',
            romanization: 'mae no kashi',
            translation: '上一句',
          ),
          LyricLine(
            start: Duration(seconds: 2),
            end: Duration(seconds: 4),
            text: '今の歌詞',
            romanization: 'ima no kashi',
            translation: '当前句',
          ),
          LyricLine(
            start: Duration(seconds: 4),
            end: Duration(seconds: 6),
            text: '次の歌詞',
            romanization: 'tsugi no kashi',
            translation: '下一句',
          ),
        ],
        isWordTimed: false,
      );

      await tester.pumpWidget(
        _app(
          songId: 'monet',
          position: position,
          loader: (_) async => _response(),
          qqLoader:
              (_) async =>
                  LyricDocument(lines: document.lines, isWordTimed: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ima no kashi'), findsOneWidget);
      expect(find.text('当前句'), findsOneWidget);
      expect(find.text('mae no kashi'), findsNothing);
      expect(find.text('上一句'), findsNothing);
      expect(find.text('tsugi no kashi'), findsNothing);
      expect(find.text('下一句'), findsNothing);
      expect(find.text('前の歌詞'), findsOneWidget);
      expect(find.text('次の歌詞'), findsOneWidget);

      final romanTop = tester.getTopLeft(find.text('ima no kashi')).dy;
      final translationTop = tester.getTopLeft(find.text('当前句')).dy;
      expect(romanTop, lessThan(translationTop));

      position.value = const Duration(milliseconds: 4500);
      await tester.pumpAndSettle();
      expect(find.text('ima no kashi'), findsNothing);
      expect(find.text('tsugi no kashi'), findsOneWidget);
      expect(find.text('下一句'), findsOneWidget);

      position.dispose();
    },
  );
}
