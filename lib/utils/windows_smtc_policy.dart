import 'dart:async';

import '../netease_api/src/api/play/bean.dart';

Map<String, Object> buildSmtcMetadata(Song2 song) {
  final artists =
      song.ar
          ?.map((artist) => artist.name?.trim() ?? '')
          .where((name) => name.isNotEmpty)
          .join(', ') ??
      '';

  return {
    'songId': song.id,
    'title': _fallback(song.name, '未知歌曲'),
    'artist': artists.isEmpty ? '未知艺术家' : artists,
    'album': song.al?.name?.trim() ?? '',
    'thumbnailUrl': song.al?.picUrl?.trim() ?? '',
  };
}

String _fallback(String? value, String fallback) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed;
}

Duration clampSmtcSeek(Duration requested, Duration duration) {
  if (requested < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && requested > duration) return duration;
  return requested;
}

Duration? resolveSmtcSeek(Duration requested, Duration duration) {
  if (duration <= Duration.zero) return null;
  return clampSmtcSeek(requested, duration);
}

String smtcPlaybackStatus({
  required bool hasSong,
  required bool isPlaying,
  required bool isLoading,
  required bool isCompleted,
}) {
  if (!hasSong || isCompleted) return 'stopped';
  if (isLoading) return 'changing';
  return isPlaying ? 'playing' : 'paused';
}

Map<String, Object>? buildSmtcTimeline({
  required Duration position,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return null;
  final safePosition = clampSmtcSeek(position, duration);
  return {
    'positionMs': safePosition.inMilliseconds,
    'durationMs': duration.inMilliseconds,
  };
}

class SmtcTimelineThrottle {
  SmtcTimelineThrottle({this.interval = const Duration(seconds: 1)});

  final Duration interval;
  Duration? _lastSentAt;

  bool shouldSend(Duration now, {bool force = false}) {
    final lastSentAt = _lastSentAt;
    if (force || lastSentAt == null || now - lastSentAt >= interval) {
      _lastSentAt = now;
      return true;
    }
    return false;
  }

  void reset() {
    _lastSentAt = null;
  }
}

class SerialAsyncExecutor {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() command) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await command());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
