import 'package:flutter/foundation.dart';

import '../netease_api/netease_music_api.dart';
import 'amll_ttml_parser.dart';
import 'lyric_models.dart';
import 'lyric_source.dart';
import 'netease_lyric_parser.dart';

typedef NeteaseLyricsLoader = Future<SongLyricWrap> Function(String songId);
typedef AmllLyricsLoader = Future<String?> Function(String songId);
typedef QqLyricsLoader =
    Future<LyricDocument?> Function(LyricSongContext context);
typedef LyricSourceReporter = void Function(LyricSource source);

class LyricResolver {
  const LyricResolver({
    required this.neteaseLoader,
    required this.amllLoader,
    this.qqLoader,
    this.sourceReporter,
    this.sourceTimeout = const Duration(seconds: 12),
  });

  final NeteaseLyricsLoader neteaseLoader;
  final AmllLyricsLoader amllLoader;
  final QqLyricsLoader? qqLoader;
  final LyricSourceReporter? sourceReporter;
  final Duration sourceTimeout;

  Future<LyricDocument> load(LyricSongContext context) async {
    final neteaseFuture = _loadNetease(context.neteaseId);
    final amllFuture = _loadAmll(context.neteaseId);
    final qqFuture = _loadQq(context);

    final netease = await neteaseFuture;
    if (netease?.isWordTimed ?? false) return _select(netease!);

    final amll = await amllFuture;
    if (amll?.isWordTimed ?? false) return _select(amll!);

    final qq = await qqFuture;
    if (qq?.isWordTimed ?? false) return _select(qq!);

    if (netease != null && !netease.document.isEmpty) {
      return _select(netease);
    }
    return LyricDocument.empty;
  }

  Future<LyricCandidate?> _loadNetease(String songId) async {
    try {
      final response = await neteaseLoader(songId).timeout(sourceTimeout);
      return LyricCandidate(
        source: LyricSource.netease,
        document: NeteaseLyricParser.parse(response),
      );
    } catch (_) {
      return null;
    }
  }

  Future<LyricCandidate?> _loadAmll(String songId) async {
    try {
      final source = await amllLoader(songId).timeout(sourceTimeout);
      if (source != null && source.trim().isNotEmpty) {
        return LyricCandidate(
          source: LyricSource.amllDb,
          document: AmllTtmlParser.parse(source),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<LyricCandidate?> _loadQq(LyricSongContext context) async {
    final loader = qqLoader;
    if (loader == null) return null;

    try {
      final document = await loader(context).timeout(sourceTimeout);
      return document == null
          ? null
          : LyricCandidate(source: LyricSource.qqMusic, document: document);
    } catch (_) {
      return null;
    }
  }

  LyricDocument _select(LyricCandidate candidate) {
    final reporter = sourceReporter;
    if (reporter != null) {
      reporter(candidate.source);
    } else {
      debugPrint('歌词来源: ${candidate.source.label}');
    }
    return candidate.document;
  }
}
