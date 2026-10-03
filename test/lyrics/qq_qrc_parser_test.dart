import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/qq_qrc_parser.dart';

void main() {
  group('QqQrcParser', () {
    test('parses tags placed before each word', () {
      final document = QqQrcParser.parse('[1000,800](1000,250)你(1250,550)好');

      expect(document.isWordTimed, isTrue);
      expect(document.lines.single.text, '你好');
      expect(document.lines.single.words, hasLength(2));
      expect(
        document.lines.single.words.last.end,
        const Duration(milliseconds: 1800),
      );
    });

    test('parses tags placed after each word and preserves spaces', () {
      final document = QqQrcParser.parse(
        '[1000,800]hello (1000,400)world(1400,400)',
      );

      expect(document.lines.single.text, 'hello world');
      expect(document.lines.single.words.first.text, 'hello ');
      expect(document.lines.single.words.last.text, 'world');
    });

    test(
      'extracts XML content and aligns QRC translation and LRC romanization',
      () {
        final document = QqQrcParser.parse(
          '<QrcInfos><LyricInfo><Lyric_1 LyricContent="[1000,800](1000,400)群(1400,400)青" /></LyricInfo></QrcInfos>',
          translation:
              '<QrcInfos><LyricInfo LyricContent="[1000,800]蓝色(1000,800)" /></QrcInfos>',
          romanization: '[00:01.00]gunjou',
        );

        expect(document.lines.single.translation, '蓝色');
        expect(document.lines.single.romanization, 'gunjou');
      },
    );

    test('recovers content when QQ leaves quotes unescaped', () {
      const source = '''
<?xml version="1.0" encoding="utf-8"?>
<QrcInfos>
<LyricInfo LyricCount="1">
<Lyric_1 LyricType="1" LyricContent="[ti:衛星]
[1000,800]"(1000,200)Hi(1200,400)"(1600,200) &amp;(1800,100)
[2000,500]星(2000,500)
"/>
</LyricInfo>
</QrcInfos>''';
      final document = QqQrcParser.parse(source);

      expect(document.isWordTimed, isTrue);
      expect(document.lines.map((line) => line.text), ['"Hi" &', '星']);
    });

    test('keeps lines that contain zero-length tokens', () {
      final document = QqQrcParser.parse(
        '[1000,800](1000,400)る(1400,0)？\n'
        '[2000,800]手(2000,300) (2300,0)君(2300,500)',
      );

      expect(document.lines.map((line) => line.text), ['る？', '手 君']);
      expect(
        document.lines.first.words.last.end,
        const Duration(milliseconds: 1400),
      );
    });

    test('discards lines without valid word timing', () {
      expect(QqQrcParser.parse('[1000,800]普通歌词').isEmpty, isTrue);
      expect(
        QqQrcParser.parse('[1000,800](1200,100)后(1000,100)前').isEmpty,
        isTrue,
      );
    });
  });
}
