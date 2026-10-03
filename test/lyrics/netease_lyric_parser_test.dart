import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/netease_lyric_parser.dart';
import 'package:verse/netease_api/netease_music_api.dart';

SongLyricWrap _response({
  String? lrc,
  String? yrc,
  String? tlyric,
  String? ytlrc,
  String? romalrc,
  String? yromalrc,
}) {
  return SongLyricWrap.fromJson({
    'code': 200,
    'lrc': {'lyric': lrc},
    'klyric': <String, dynamic>{},
    'tlyric': {'lyric': tlyric},
    'yrc': {'lyric': yrc},
    'ytlrc': {'lyric': ytlrc},
    'romalrc': {'lyric': romalrc},
    'yromalrc': {'lyric': yromalrc},
  });
}

void main() {
  group('NeteaseLyricParser', () {
    test('preserves YRC line and word timing', () {
      final document = NeteaseLyricParser.parse(
        _response(
          lrc: '[00:01.00]夢から覚める',
          yrc:
              '[1000,1200](1000,400,0)夢(1400,300,0)から'
              '(1700,500,0)覚める\n'
              '[2500,500](2500,500,0)時',
        ),
      );

      expect(document.isWordTimed, isTrue);
      expect(document.lines, hasLength(2));
      expect(document.lines.first.start, const Duration(milliseconds: 1000));
      expect(document.lines.first.end, const Duration(milliseconds: 2200));
      expect(document.lines.first.text, '夢から覚める');
      expect(document.lines.first.words.map((word) => word.text), [
        '夢',
        'から',
        '覚める',
      ]);
      expect(
        document.lines.first.words[1].start,
        const Duration(milliseconds: 1400),
      );
      expect(
        document.lines.first.words[1].end,
        const Duration(milliseconds: 1700),
      );
    });

    test('sorts YRC lines and aligns word translation and romanization', () {
      final document = NeteaseLyricParser.parse(
        _response(
          yrc:
              '[2500,500](2500,500,0)時\n'
              '[1000,1200](1000,1200,0)夢から覚める',
          tlyric: '[00:01.00]fallback translation',
          ytlrc:
              '[00:02.50]time\n'
              '[00:01.00]wake from the dream',
          romalrc: '[00:01.00]fallback romanization',
          yromalrc:
              '[00:02.50]toki\n'
              '[00:01.00]yume kara sameru',
        ),
      );

      expect(document.lines.first.text, '夢から覚める');
      expect(document.lines.first.translation, 'wake from the dream');
      expect(document.lines.first.romanization, 'yume kara sameru');
      expect(document.lines.last.translation, 'time');
      expect(document.lines.last.romanization, 'toki');
    });

    test('falls back to line-timed LRC without fake word timing', () {
      final document = NeteaseLyricParser.parse(
        _response(
          lrc:
              '[00:03.000]first line\n'
              '[00:05.50]second line',
          tlyric:
              '[00:03.00]第一行\n'
              '[00:05.50]第二行',
        ),
      );

      expect(document.isWordTimed, isFalse);
      expect(document.lines, hasLength(2));
      expect(document.lines.first.words, isEmpty);
      expect(document.lines.first.end, const Duration(milliseconds: 5500));
      expect(document.lines.first.translation, '第一行');
      expect(document.lines.last.end, const Duration(milliseconds: 10500));
    });

    test('falls back to LRC when the YRC payload is malformed', () {
      final document = NeteaseLyricParser.parse(
        _response(lrc: '[00:01.00]usable line', yrc: 'not a timed lyric'),
      );

      expect(document.isWordTimed, isFalse);
      expect(document.lines.single.text, 'usable line');
    });

    test('returns an empty document for empty tracks', () {
      final document = NeteaseLyricParser.parse(_response());

      expect(document.lines, isEmpty);
      expect(document.isWordTimed, isFalse);
    });
  });
}
