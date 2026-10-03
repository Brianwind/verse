import 'lyric_source.dart';

class QqSongCandidate {
  const QqSongCandidate({
    required this.id,
    required this.mid,
    required this.title,
    required this.artists,
    required this.album,
    this.duration,
  });

  factory QqSongCandidate.fromJson(Map<String, dynamic> json) {
    final singerData = json['singer'];
    final artists = <String>[];
    if (singerData is List) {
      for (final singer in singerData) {
        if (singer is! Map) continue;
        final name = singer['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) artists.add(name);
      }
    }

    final albumData = json['album'];
    final album =
        albumData is Map ? albumData['name']?.toString().trim() ?? '' : '';
    final durationSeconds = _positiveInt(json['interval']);

    return QqSongCandidate(
      id: _positiveInt(json['id']) ?? 0,
      mid: json['mid']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      artists: List.unmodifiable(artists),
      album: album,
      duration:
          durationSeconds == null ? null : Duration(seconds: durationSeconds),
    );
  }

  final int id;
  final String mid;
  final String title;
  final List<String> artists;
  final String album;
  final Duration? duration;

  bool get canFetchLyrics => id > 0 && mid.isNotEmpty;

  static int? _positiveInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

class QqSongMatcher {
  static final RegExp _bracketPattern = RegExp(
    r'[\(\（\[【]([^\)\）\]】]*)[\)\）\]】]',
  );
  static final RegExp _versionMarkerPattern = RegExp(
    r'\b(?:live|remix|instrumental|cover|acoustic|remaster(?:ed)?|version|ver|edit|mix|karaoke|inst|off ?vocal|back ?track|tv ?size)\b|伴奏|现场|翻唱|重制|重录|不插电|第一现场|the first take',
    caseSensitive: false,
  );

  /// Featured-artist credits do not identify a different recording, and the
  /// platforms disagree on whether they belong in the title: NetEase's
  /// `ワンダー` is `ワンダー feat. 初音ミク` on QQ Music.
  static final RegExp _trailingFeaturingPattern = RegExp(
    r'\s+(?:feat|ft)\.?\s.*$',
    caseSensitive: false,
  );
  static final RegExp _featuringMarkerPattern = RegExp(
    r'^\s*(?:feat|ft|with)\b',
    caseSensitive: false,
  );
  static final RegExp _whitespacePattern = RegExp(r'\s+');
  static final RegExp _separatorPattern = RegExp(
    r'''[\s\-_.,，。·・:：;；!！?？'"“”‘’/\\|~～+&＆]''',
  );

  static QqSongCandidate? selectBest(
    LyricSongContext target,
    Iterable<QqSongCandidate> candidates,
  ) {
    final ranked = rank(target, candidates);
    return ranked.isEmpty ? null : ranked.first;
  }

  /// Reliable candidates ordered from strongest to weakest match.
  static List<QqSongCandidate> rank(
    LyricSongContext target,
    Iterable<QqSongCandidate> candidates,
  ) {
    final scored = <_ScoredCandidate>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate.mid)) continue;
      final result = _score(target, candidate);
      if (result != null) scored.add(result);
    }
    // Stable: equal scores keep the search engine's relevance order.
    final order = [for (var i = 0; i < scored.length; i++) i]..sort((a, b) {
      final byScore = scored[b].score.compareTo(scored[a].score);
      return byScore != 0 ? byScore : a.compareTo(b);
    });
    return [for (final index in order) scored[index].candidate];
  }

  static String cacheKey(LyricSongContext context) {
    final durationSeconds = context.duration?.inSeconds ?? 0;
    return <String>[
      normalizeTitle(context.title),
      context.artists.map(normalizeIdentity).join(','),
      normalizeIdentity(context.album),
      '$durationSeconds',
    ].join('|');
  }

  static String normalizeTitle(String source) {
    final folded = _stripFeaturing(_foldFullWidth(source).toLowerCase());
    final withoutTranslations = folded.replaceAllMapped(_bracketPattern, (
      match,
    ) {
      final content = match.group(1) ?? '';
      return _isVersionMarker(content) ? content : '';
    });
    return withoutTranslations.replaceAll(_separatorPattern, '');
  }

  /// A short title for a broader search: bracketed translations, sources and
  /// featuring credits removed, version markers kept.
  static String searchTitle(String source) {
    final folded = _stripFeaturing(_foldFullWidth(source));
    final simplified =
        folded
            .replaceAllMapped(_bracketPattern, (match) {
              final content = match.group(1) ?? '';
              return _isVersionMarker(content) ? match.group(0)! : ' ';
            })
            .replaceAll(_whitespacePattern, ' ')
            .trim();
    return simplified.isEmpty ? source.trim() : simplified;
  }

  static bool _isVersionMarker(String bracketContent) {
    return !_featuringMarkerPattern.hasMatch(bracketContent) &&
        _versionMarkerPattern.hasMatch(bracketContent);
  }

  static String _stripFeaturing(String title) {
    return title.replaceFirst(_trailingFeaturingPattern, '');
  }

  static String normalizeIdentity(String source) {
    final folded = _foldFullWidth(source).toLowerCase();
    return folded.replaceAll(_separatorPattern, '');
  }

  static _ScoredCandidate? _score(
    LyricSongContext target,
    QqSongCandidate candidate,
  ) {
    if (!candidate.canFetchLyrics ||
        normalizeTitle(target.title).isEmpty ||
        normalizeTitle(target.title) != normalizeTitle(candidate.title)) {
      return null;
    }

    final targetArtists =
        target.artists.map(normalizeIdentity).toSet()..remove('');
    final candidateArtists =
        candidate.artists.map(normalizeIdentity).toSet()..remove('');
    final artistMatched = targetArtists.any(
      (target) =>
          candidateArtists.any((candidate) => _sameArtist(target, candidate)),
    );

    final targetAlbum = normalizeIdentity(target.album);
    final candidateAlbum = normalizeIdentity(candidate.album);
    final albumMatched =
        targetAlbum.isNotEmpty &&
        candidateAlbum.isNotEmpty &&
        targetAlbum == candidateAlbum;

    if (!artistMatched && !albumMatched) return null;

    final targetDuration = target.duration;
    final candidateDuration = candidate.duration;
    var durationDifferenceMs = 0;
    if (targetDuration != null && candidateDuration != null) {
      durationDifferenceMs =
          (targetDuration - candidateDuration).inMilliseconds.abs();
      if (durationDifferenceMs > const Duration(seconds: 3).inMilliseconds) {
        return null;
      }
    }

    var score = 1000;
    if (artistMatched) score += 300;
    if (albumMatched) score += 220;
    if (targetDuration != null && candidateDuration != null) {
      score += 180 - (durationDifferenceMs ~/ 20).clamp(0, 150);
    }

    return _ScoredCandidate(candidate, score);
  }

  /// Exact match, or one credit extends the other (`Ayasa` / `Ayasa绚沙`).
  /// Short names must match exactly to avoid accidental overlaps.
  static bool _sameArtist(String left, String right) {
    if (left == right) return true;
    final shorter = left.length <= right.length ? left : right;
    final longer = identical(shorter, left) ? right : left;
    return shorter.length >= 3 && longer.contains(shorter);
  }

  static String _foldFullWidth(String source) {
    final buffer = StringBuffer();
    for (final rune in source.runes) {
      if (rune == 0x3000) {
        buffer.write(' ');
      } else if (rune >= 0xff01 && rune <= 0xff5e) {
        buffer.writeCharCode(rune - 0xfee0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }
}

class _ScoredCandidate {
  const _ScoredCandidate(this.candidate, this.score);

  final QqSongCandidate candidate;
  final int score;
}
