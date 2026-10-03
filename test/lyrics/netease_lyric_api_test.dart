import 'package:flutter_test/flutter_test.dart';
import 'package:verse/netease_api/netease_music_api.dart';
import 'package:verse/netease_api/src/api/play/api.dart';

class _ApiPlayHarness with ApiPlay {}

void main() {
  group('new NetEase lyric API', () {
    test('requests every word-timed lyric branch from the v1 endpoint', () {
      final metadata = _ApiPlayHarness().songLyricNewDioMetaData('1902312409');

      expect(metadata.uri.path, '/api/song/lyric/v1');
      expect(metadata.data, {
        'id': '1902312409',
        'cp': false,
        'tv': 0,
        'lv': 0,
        'rv': 0,
        'kv': 0,
        'yv': 0,
        'ytv': 0,
        'yrv': 0,
      });
    });

    test('deserializes word timing, translation, and romanization tracks', () {
      final result = SongLyricWrap.fromJson({
        'code': 200,
        'lrc': {'lyric': '[00:01.00]line'},
        'klyric': <String, dynamic>{},
        'tlyric': {'lyric': '[00:01.00]translation'},
        'yrc': {'lyric': '[1000,500](1000,500,0)line'},
        'ytlrc': {'lyric': '[00:01.00]word translation'},
        'romalrc': {'lyric': '[00:01.00]romanization'},
        'yromalrc': {'lyric': '[00:01.00]word romanization'},
      });

      expect(result.yrc.lyric, '[1000,500](1000,500,0)line');
      expect(result.ytlrc.lyric, '[00:01.00]word translation');
      expect(result.romalrc.lyric, '[00:01.00]romanization');
      expect(result.yromalrc.lyric, '[00:01.00]word romanization');
    });
  });
}
