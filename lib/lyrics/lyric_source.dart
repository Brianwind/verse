import '../netease_api/netease_music_api.dart';
import 'lyric_models.dart';

enum LyricSource { netease, amllDb, qqMusic }

extension LyricSourceLabel on LyricSource {
  String get label => switch (this) {
    LyricSource.netease => '网易云音乐',
    LyricSource.amllDb => 'AMLLDB',
    LyricSource.qqMusic => 'QQ音乐',
  };
}

class LyricSongContext {
  const LyricSongContext({
    required this.neteaseId,
    required this.title,
    required this.artists,
    required this.album,
    this.duration,
  });

  factory LyricSongContext.fromSong(Song2 song) {
    final durationMs = song.dt;
    return LyricSongContext(
      neteaseId: song.id,
      title: song.name?.trim() ?? '',
      artists: List.unmodifiable(
        song.ar
                ?.map((artist) => artist.name?.trim() ?? '')
                .where((name) => name.isNotEmpty) ??
            const <String>[],
      ),
      album: song.al?.name?.trim() ?? '',
      duration:
          durationMs != null && durationMs > 0
              ? Duration(milliseconds: durationMs)
              : null,
    );
  }

  factory LyricSongContext.idOnly(String neteaseId) {
    return LyricSongContext(
      neteaseId: neteaseId,
      title: '',
      artists: const [],
      album: '',
    );
  }

  final String neteaseId;
  final String title;
  final List<String> artists;
  final String album;
  final Duration? duration;

  bool get hasQqSearchMetadata {
    return title.trim().isNotEmpty &&
        (artists.any((artist) => artist.trim().isNotEmpty) ||
            album.trim().isNotEmpty);
  }
}

class LyricCandidate {
  const LyricCandidate({required this.source, required this.document});

  final LyricSource source;
  final LyricDocument document;

  bool get isWordTimed => document.isWordTimed;
}
