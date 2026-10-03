import 'dart:async';

import 'package:dio/dio.dart';

import '../utils/lru_cache.dart';

typedef AmllRemoteLoader = Future<String?> Function(String songId);

class AmllDbClient {
  AmllDbClient({
    Dio? dio,
    AmllRemoteLoader? remoteLoader,
    int cacheCapacity = 100,
  }) : _dio = dio ?? _createDio(),
       _remoteLoader = remoteLoader,
       _cache = LruCache<String, String>(capacity: cacheCapacity);

  static final AmllDbClient instance = AmllDbClient();

  final Dio _dio;
  final AmllRemoteLoader? _remoteLoader;
  final LruCache<String, String> _cache;
  final Map<String, Future<String?>> _inFlight = {};

  Future<String?> fetch(String songId) {
    final normalizedId = songId.trim();
    if (normalizedId.isEmpty) return Future.value();

    final cached = _cache[normalizedId];
    if (cached != null) return Future.value(cached);

    final pending = _inFlight[normalizedId];
    if (pending != null) return pending;

    final request = _load(normalizedId);
    _inFlight[normalizedId] = request;
    unawaited(
      request.whenComplete(() {
        if (identical(_inFlight[normalizedId], request)) {
          _inFlight.remove(normalizedId);
        }
      }),
    );
    return request;
  }

  Future<String?> _load(String songId) async {
    try {
      final source = await (_remoteLoader ?? _fetchRemote)(songId);
      final normalized = _normalizeTtml(source);
      if (normalized != null) _cache[songId] = normalized;
      return normalized;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchRemote(String songId) async {
    final uri = Uri.https(
      'amll-ttml-db.stevexmh.net',
      '/ncm/${Uri.encodeComponent(songId)}',
      const {'format': 'ttml'},
    );
    final response = await _dio.getUri<String>(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    return response.statusCode == 200 ? response.data : null;
  }

  static String? _normalizeTtml(String? source) {
    final trimmed = source?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final ttmlStart = RegExp(
      r'^(?:<\?xml[^>]*>\s*)?<tt(?:\s|>)',
      caseSensitive: false,
    );
    return ttmlStart.hasMatch(trimmed) ? trimmed : null;
  }

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
        headers: const {
          'Accept':
              'application/ttml+xml, application/xml, text/xml, text/plain',
        },
      ),
    );
  }
}
