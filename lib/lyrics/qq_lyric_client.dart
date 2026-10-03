import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';

import '../utils/lru_cache.dart';
import 'lyric_models.dart';
import 'lyric_source.dart';
import 'qq_qdes.dart';
import 'qq_qrc_parser.dart';
import 'qq_song_matcher.dart';

typedef QqApiRequest =
    Future<Map<String, dynamic>> Function({
      required String method,
      required String module,
      required Map<String, dynamic> parameters,
    });
typedef QqTracksDecoder =
    Future<QqDecryptedTracks> Function(QqEncryptedTracks tracks);

class QqEncryptedTracks {
  const QqEncryptedTracks({
    required this.lyric,
    this.translation,
    this.romanization,
  });

  final String lyric;
  final String? translation;
  final String? romanization;
}

class QqDecryptedTracks {
  const QqDecryptedTracks({
    required this.lyric,
    this.translation,
    this.romanization,
  });

  final String lyric;
  final String? translation;
  final String? romanization;
}

class QqLyricClient {
  QqLyricClient({
    Dio? dio,
    QqApiRequest? request,
    QqTracksDecoder? decoder,
    int cacheCapacity = 100,
    this.sourceTimeout = const Duration(seconds: 10),
  }) : _dio = dio ?? _createDio(),
       _requestOverride = request,
       _decoder = decoder ?? _decodeTracksOffThread,
       _matchCache = LruCache<String, QqSongCandidate>(capacity: cacheCapacity),
       _documentCache = LruCache<String, LyricDocument>(
         capacity: cacheCapacity,
       );

  static final QqLyricClient instance = QqLyricClient();

  static const String _endpoint = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
  static const String _searchMethod = 'DoSearchForQQMusicLite';
  static const String _searchModule = 'music.search.SearchCgiService';
  static const String _lyricMethod = 'GetPlayLyricInfo';
  static const String _lyricModule = 'music.musichallSong.PlayLyricInfo';

  final Dio _dio;
  final QqApiRequest? _requestOverride;
  final QqTracksDecoder _decoder;
  final LruCache<String, QqSongCandidate> _matchCache;
  final LruCache<String, LyricDocument> _documentCache;
  final Map<String, Future<LyricDocument?>> _inFlight = {};
  final Duration sourceTimeout;

  Future<LyricDocument?> fetch(LyricSongContext context) {
    if (!context.hasQqSearchMetadata) return Future.value();

    final documentKey = context.neteaseId.trim();
    if (documentKey.isNotEmpty) {
      final cached = _documentCache[documentKey];
      if (cached != null) return Future.value(cached);
    }

    final requestKey = '$documentKey|${QqSongMatcher.cacheKey(context)}';
    final pending = _inFlight[requestKey];
    if (pending != null) return pending;

    final request = _load(
      context,
    ).timeout(sourceTimeout, onTimeout: () => null).catchError((_) => null);
    _inFlight[requestKey] = request;
    unawaited(
      request.then((_) {
        if (identical(_inFlight[requestKey], request)) {
          _inFlight.remove(requestKey);
        }
      }),
    );
    return request;
  }

  /// Candidates tried per song. QQ often lists several releases of the same
  /// recording and only some of them carry word-timed lyrics.
  static const int _maxLyricAttempts = 3;

  Future<LyricDocument?> _load(LyricSongContext context) async {
    final matchKey = QqSongMatcher.cacheKey(context);
    final cached = _matchCache[matchKey];
    if (cached != null) {
      final document = await _fetchDocument(cached);
      if (document != null) return _remember(context, document);
    }

    final attempted = <String>{if (cached != null) cached.mid};
    for (final query in _searchQueries(context)) {
      final candidates = await _searchCandidates(context, query);
      for (final candidate in candidates) {
        if (attempted.length >= _maxLyricAttempts) return null;
        if (!attempted.add(candidate.mid)) continue;
        final document = await _fetchDocument(candidate);
        if (document == null) continue;
        _matchCache[matchKey] = candidate;
        return _remember(context, document);
      }
    }
    return null;
  }

  LyricDocument _remember(LyricSongContext context, LyricDocument document) {
    final documentKey = context.neteaseId.trim();
    if (documentKey.isNotEmpty) _documentCache[documentKey] = document;
    return document;
  }

  Future<LyricDocument?> _fetchDocument(QqSongCandidate candidate) async {
    final encrypted = await _fetchEncryptedTracks(candidate);
    if (encrypted == null) return null;
    final tracks = await _decoder(encrypted);
    final document = QqQrcParser.parse(
      tracks.lyric,
      translation: tracks.translation,
      romanization: tracks.romanization,
    );
    if (!document.isWordTimed || document.isEmpty) return null;
    return document;
  }

  Future<List<QqSongCandidate>> _searchCandidates(
    LyricSongContext context,
    String query,
  ) async {
    final data = await _request(
      method: _searchMethod,
      module: _searchModule,
      parameters: {
        'search_id': DateTime.now().microsecondsSinceEpoch.toString(),
        'remoteplace': 'search.android.keyboard',
        'query': query,
        'search_type': 0,
        'num_per_page': 10,
        'page_num': 1,
        'highlight': 0,
        'nqc_flag': 0,
        'page_id': 1,
        'grp': 1,
      },
    );

    final body = _asStringMap(data['body']);
    final items = body?['item_song'];
    if (items is! List) return const [];

    final candidates = <QqSongCandidate>[];
    for (final item in items.take(10)) {
      final json = _asStringMap(item);
      if (json != null) candidates.add(QqSongCandidate.fromJson(json));
    }
    return QqSongMatcher.rank(context, candidates);
  }

  Future<QqEncryptedTracks?> _fetchEncryptedTracks(QqSongCandidate song) async {
    final artists = song.artists.join(', ');
    final data = await _request(
      method: _lyricMethod,
      module: _lyricModule,
      parameters: {
        'albumName': _base64(song.album),
        'crypt': 1,
        'ct': 19,
        'cv': 2111,
        'interval': song.duration?.inSeconds ?? 0,
        'lrc_t': 0,
        'qrc': 1,
        'qrc_t': 0,
        'roma': 1,
        'roma_t': 0,
        'singerName': _base64(artists),
        'songID': song.id,
        'songName': _base64(song.title),
        'trans': 1,
        'trans_t': 0,
        'type': 0,
      },
    );

    final lyric = _nonEmptyString(data['lyric']);
    if (lyric == null) return null;
    return QqEncryptedTracks(
      lyric: lyric,
      translation: _nonEmptyString(data['trans']),
      romanization: _nonEmptyString(data['roma']),
    );
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required String module,
    required Map<String, dynamic> parameters,
  }) async {
    final override = _requestOverride;
    if (override != null) {
      return override(method: method, module: module, parameters: parameters);
    }

    final response = await _dio.post<Object?>(
      _endpoint,
      data: {
        'comm': const {
          'ct': 11,
          'cv': '1003006',
          'v': '1003006',
          'os_ver': '15',
          'phonetype': '24122RKC7C',
          'tmeAppID': 'qqmusiclight',
          'nettype': 'NETWORK_WIFI',
          'udid': '0',
          'uid': '0',
        },
        'request': {'method': method, 'module': module, 'param': parameters},
      },
    );
    final root = _asStringMap(response.data);
    final request = _asStringMap(root?['request']);
    final data = _asStringMap(request?['data']);
    if (!_isZero(root?['code']) || !_isZero(request?['code']) || data == null) {
      throw StateError('QQ Music API returned an unsuccessful response');
    }
    return data;
  }

  static Future<QqDecryptedTracks> _decodeTracksOffThread(
    QqEncryptedTracks tracks,
  ) {
    return Isolate.run(() {
      String? decodeOptional(String? value) {
        return value == null ? null : QqQdes.decryptAndInflate(value);
      }

      return QqDecryptedTracks(
        lyric: QqQdes.decryptAndInflate(tracks.lyric),
        translation: decodeOptional(tracks.translation),
        romanization: decodeOptional(tracks.romanization),
      );
    });
  }

  /// The precise query first; then title + lead artist, because long queries
  /// (album names, bracketed notes, featuring lists) often return nothing.
  static List<String> _searchQueries(LyricSongContext context) {
    String build(Iterable<String> parts) {
      final query =
          parts.where((part) => part.trim().isNotEmpty).join(' ').trim();
      return query.length <= 60 ? query : query.substring(0, 60);
    }

    final precise = build([
      context.title,
      ...context.artists.take(2),
      if (context.album.isNotEmpty) context.album,
    ]);
    final broad = build([
      QqSongMatcher.searchTitle(context.title),
      ...context.artists.take(1),
    ]);
    return [precise, if (broad.isNotEmpty && broad != precise) broad];
  }

  static String _base64(String value) {
    return base64.encode(utf8.encode(value));
  }

  static String? _nonEmptyString(Object? value) {
    final result = value?.toString().trim();
    return result == null || result.isEmpty ? null : result;
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static bool _isZero(Object? value) {
    return value == 0 || value?.toString() == '0';
  }

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
        contentType: Headers.jsonContentType,
        headers: const {
          'Cookie': 'tmeLoginType=-1;',
          'User-Agent': 'okhttp/3.14.9',
        },
      ),
    );
  }
}
