import 'package:flutter_test/flutter_test.dart';
import 'package:verse/lyrics/lyric_source.dart';
import 'package:verse/lyrics/qq_song_matcher.dart';

const _target = LyricSongContext(
  neteaseId: '1500151581',
  title: '群青',
  artists: ['YOASOBI'],
  album: 'THE BOOK',
  duration: Duration(milliseconds: 248000),
);

QqSongCandidate _candidate({
  int id = 287838659,
  String mid = '0035UDLu1yiTvO',
  String title = '群青',
  List<String> artists = const ['YOASOBI'],
  String album = 'THE BOOK',
  int durationMs = 248000,
}) {
  return QqSongCandidate(
    id: id,
    mid: mid,
    title: title,
    artists: artists,
    album: album,
    duration: Duration(milliseconds: durationMs),
  );
}

void main() {
  group('QqSongMatcher', () {
    test('accepts translated title suffixes and matching metadata', () {
      final result = QqSongMatcher.selectBest(_target, [
        _candidate(title: '群青 (Ultramarine)'),
      ]);

      expect(result?.id, 287838659);
    });

    test('rejects a different artist and album', () {
      final result = QqSongMatcher.selectBest(_target, [
        _candidate(artists: const ['Other'], album: 'Other Album'),
      ]);

      expect(result, isNull);
    });

    test('accepts album identity when artist metadata differs', () {
      final result = QqSongMatcher.selectBest(_target, [
        _candidate(artists: const ['Ayase']),
      ]);

      expect(result, isNotNull);
    });

    test('keeps version markers significant', () {
      final result = QqSongMatcher.selectBest(_target, [
        _candidate(title: '群青 (Live)'),
      ]);

      expect(result, isNull);
    });

    test('rejects candidates outside the three-second duration window', () {
      final result = QqSongMatcher.selectBest(_target, [
        _candidate(durationMs: 251001),
      ]);

      expect(result, isNull);
    });

    test('chooses the strongest reliable candidate', () {
      final result = QqSongMatcher.selectBest(_target, [
        _candidate(id: 1, mid: 'artist-only', album: 'Other Album'),
        _candidate(id: 2, mid: 'album-only', artists: const ['Other']),
        _candidate(id: 3, mid: 'exact'),
      ]);

      expect(result?.id, 3);
    });

    test('ignores featuring credits on either side', () {
      const target = LyricSongContext(
        neteaseId: '3406178212',
        title: 'ワンダー',
        artists: ['r-906', '初音ミク'],
        album: 'ワンダー',
        duration: Duration(seconds: 180),
      );

      final result = QqSongMatcher.selectBest(target, [
        _candidate(
          title: 'ワンダー feat. 初音ミク',
          artists: const ['r-906', '初音未来'],
          album: 'ワンダー feat. 初音ミク',
          durationMs: 180000,
        ),
      ]);

      expect(result, isNotNull);
      expect(
        QqSongMatcher.normalizeTitle('歌姫失格 (feat. 初音ミク)'),
        QqSongMatcher.normalizeTitle('歌姫失格'),
      );
    });

    test('accepts an artist credit that extends the other platform name', () {
      const target = LyricSongContext(
        neteaseId: '3386967464',
        title: '告白の夜',
        artists: ['Ayasa'],
        album: '告白の夜',
        duration: Duration(seconds: 290),
      );

      final result = QqSongMatcher.selectBest(target, [
        _candidate(
          title: '告白の夜 (告白之夜)',
          artists: const ['Ayasa绚沙'],
          album: 'CHRONICLE V',
          durationMs: 290000,
        ),
      ]);

      expect(result, isNotNull);
    });

    test('ranks every reliable candidate in score order', () {
      final ranked = QqSongMatcher.rank(_target, [
        _candidate(id: 1, mid: 'artist-only', album: 'Other Album'),
        _candidate(id: 2, mid: 'wrong', artists: const ['Other'], album: 'X'),
        _candidate(id: 3, mid: 'exact'),
      ]);

      expect(ranked.map((candidate) => candidate.id), [3, 1]);
    });

    test('builds a short search title', () {
      expect(QqSongMatcher.searchTitle('アクマバライ (feat. 雨衣 & 初音ミク)'), 'アクマバライ');
      expect(QqSongMatcher.searchTitle('桜海岸（樱花海岸）'), '桜海岸');
      expect(QqSongMatcher.searchTitle('群青 (Live)'), '群青 (Live)');
    });

    test('parses dynamic QQ search fields', () {
      final candidate = QqSongCandidate.fromJson({
        'id': '287838659',
        'mid': '0035UDLu1yiTvO',
        'title': '群青',
        'interval': 248,
        'singer': [
          {'name': 'YOASOBI'},
        ],
        'album': {'name': 'THE BOOK'},
      });

      expect(candidate.id, 287838659);
      expect(candidate.artists, ['YOASOBI']);
      expect(candidate.duration, const Duration(seconds: 248));
    });
  });
}
