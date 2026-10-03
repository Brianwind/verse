import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/amll_ttml_parser.dart';
import 'package:verse/lyrics/lyric_models.dart';

const _gunjoTtml = '''
<tt xmlns="http://www.w3.org/ns/ttml"
    xmlns:ttm="http://www.w3.org/ns/ttml#metadata"
    xmlns:itunes="http://music.apple.com/lyric-ttml-internal">
  <body dur="04:03.932">
    <div begin="00:01.236" end="04:03.932">
      <p begin="00:01.236" end="00:03.394" ttm:agent="v1">
        <span begin="00:01.236" end="00:01.567">嗚</span>
        <span begin="00:01.567" end="00:01.936">呼</span>
        <span begin="00:01.936" end="00:02.131">い</span>
        <span ttm:role="x-translation" xml:lang="zh-CN">啊 一如往常</span>
        <span ttm:role="x-roman">aa itsumo no you ni</span>
      </p>
      <p begin="00:03.516" end="00:06.800" ttm:agent="v1">
        <span begin="00:03.516" end="00:04.120">過</span>
        <span begin="00:04.120" end="00:04.450">ぎ</span>
      </p>
    </div>
  </body>
</tt>
''';

void main() {
  group('AmllTtmlParser', () {
    test('preserves AMLLDB line and word timing', () {
      final document = AmllTtmlParser.parse(_gunjoTtml);

      expect(document.isWordTimed, isTrue);
      expect(document.lines, hasLength(2));
      expect(document.lines.first.start, const Duration(milliseconds: 1236));
      expect(document.lines.first.end, const Duration(milliseconds: 3394));
      expect(document.lines.first.text, '嗚呼い');
      expect(document.lines.first.words.map((word) => word.text), [
        '嗚',
        '呼',
        'い',
      ]);
      expect(
        document.lines.first.words[1].start,
        const Duration(milliseconds: 1567),
      );
      expect(
        document.lines.first.words[1].end,
        const Duration(milliseconds: 1936),
      );
    });

    test('extracts alternate tracks without mixing them into main text', () {
      final line = AmllTtmlParser.parse(_gunjoTtml).lines.first;

      expect(line.text, '嗚呼い');
      expect(line.translation, '啊 一如往常');
      expect(line.romanization, 'aa itsumo no you ni');
    });

    test('supports seconds and milliseconds TTML time expressions', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml"><body><div>
  <p begin="1.25s" end="2500ms">
    <span begin="1250ms" end="1.75s">A</span>
  </p>
</div></body></tt>
''';

      final line = AmllTtmlParser.parse(ttml).lines.single;

      expect(line.start, const Duration(milliseconds: 1250));
      expect(line.end, const Duration(milliseconds: 2500));
      expect(line.words.single.end, const Duration(milliseconds: 1750));
    });

    test('returns an empty document for malformed TTML', () {
      expect(AmllTtmlParser.parse('<not-ttml'), same(LyricDocument.empty));
    });
  });
}
