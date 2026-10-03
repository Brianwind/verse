import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';

class PlaybackPositionEstimator {
  Duration _anchorPosition = Duration.zero;
  Duration _anchorElapsed = Duration.zero;
  bool _playing = false;
  double _speed = 1;
  Duration? _duration;

  void synchronize({
    required Duration position,
    required Duration elapsed,
    required bool playing,
    required double speed,
    Duration? duration,
  }) {
    _anchorPosition = position;
    _anchorElapsed = elapsed;
    _playing = playing;
    _speed = speed;
    _duration = duration;
  }

  Duration positionAt(Duration elapsed) {
    var position = _anchorPosition;
    if (_playing && elapsed > _anchorElapsed) {
      final elapsedMicroseconds =
          (elapsed - _anchorElapsed).inMicroseconds * _speed;
      position += Duration(microseconds: elapsedMicroseconds.round());
    }

    if (position < Duration.zero) {
      return Duration.zero;
    }

    final duration = _duration;
    if (duration != null && position > duration) {
      return duration;
    }
    return position;
  }
}

class PlaybackClock extends ChangeNotifier
    implements ValueListenable<Duration> {
  PlaybackClock({required AudioPlayer player, required TickerProvider vsync})
    : _player = player {
    _ticker = vsync.createTicker(_handleTick);
    _stopwatch.start();
    _subscriptions.addAll([
      _player.positionStream.listen((_) => _synchronizeFromPlayer()),
      _player.playerStateStream.listen((_) => _synchronizeFromPlayer()),
      _player.speedStream.listen((_) => _synchronizeFromPlayer()),
      _player.durationStream.listen((_) => _synchronizeFromPlayer()),
    ]);
    _synchronizeFromPlayer();
  }

  final AudioPlayer _player;
  final PlaybackPositionEstimator _estimator = PlaybackPositionEstimator();
  final Stopwatch _stopwatch = Stopwatch();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late final Ticker _ticker;

  Duration _position = Duration.zero;
  bool _disposed = false;

  Duration get position => _position;

  @override
  Duration get value => _position;

  void _synchronizeFromPlayer() {
    if (_disposed) return;

    _estimator.synchronize(
      position: _player.position,
      elapsed: _stopwatch.elapsed,
      playing: _player.playing,
      speed: _player.speed,
      duration: _player.duration,
    );
    _updatePosition();

    if (_player.playing) {
      if (!_ticker.isActive) {
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _handleTick(Duration _) {
    _updatePosition();
  }

  void _updatePosition() {
    final nextPosition = _estimator.positionAt(_stopwatch.elapsed);
    if (nextPosition == _position) return;
    _position = nextPosition;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _ticker.dispose();
    _stopwatch.stop();
    super.dispose();
  }
}
