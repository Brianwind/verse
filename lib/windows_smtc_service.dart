import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'constants/platform.dart';
import 'player_model.dart';
import 'utils/windows_smtc_policy.dart';

/// Keeps the Windows System Media Transport Controls in sync with PlayerModel.
///
/// The native half of this channel lives in windows/runner/windows_smtc.*.
/// On non-Windows platforms every public operation is a no-op.
class WindowsSmtcService {
  static const MethodChannel _channel = MethodChannel('verse/windows_smtc');

  static final WindowsSmtcService instance = WindowsSmtcService._();

  WindowsSmtcService._();

  PlayerModel? _playerModel;
  StreamSubscription<ProcessingState>? _processingStateSubscription;
  final SerialAsyncExecutor _trackChangeExecutor = SerialAsyncExecutor();
  final SmtcTimelineThrottle _timelineThrottle = SmtcTimelineThrottle();
  final Stopwatch _clock = Stopwatch();
  Future<void> _lifecycleTail = Future<void>.value();

  String? _lastSongId;
  String? _lastPlaybackStatus;
  bool? _lastEnabled;
  bool _handlerInstalled = false;
  bool _nativeInitialized = false;
  int _lifecycleGeneration = 0;
  int? _initializationGeneration;
  bool _syncRunning = false;
  bool _syncPending = false;
  bool _forceTimeline = false;
  bool _disposed = false;

  static Future<void> initialize() => instance._installHandler();

  Future<void> _installHandler() async {
    if (!PlatformUtils.isWindows || _handlerInstalled) return;
    _handlerInstalled = true;
    _disposed = false;
    _lifecycleGeneration++;
    _clock.reset();
    _clock.start();
    _channel.setMethodCallHandler(_handleNativeCommand);
  }

  Future<void> _initializeNative() async {
    if (_nativeInitialized || _disposed) return;
    final generation = _lifecycleGeneration;
    if (_initializationGeneration == generation) {
      await _lifecycleTail;
      return;
    }

    _initializationGeneration = generation;
    final initialization = _lifecycleTail.then((_) async {
      if (_disposed || generation != _lifecycleGeneration) return;
      final initialized = await _invokeChannel('initialize');
      if (_disposed || generation != _lifecycleGeneration) {
        if (initialized) await _invokeChannel('dispose');
        return;
      }
      if (initialized) {
        _nativeInitialized = true;
        _resetNativeStateCache();
      }
    });
    _lifecycleTail = initialization;
    try {
      await initialization;
    } finally {
      if (_initializationGeneration == generation) {
        _initializationGeneration = null;
      }
    }
  }

  void _resetNativeStateCache() {
    _lastSongId = null;
    _lastPlaybackStatus = null;
    _lastEnabled = null;
    _timelineThrottle.reset();
  }

  /// Attaches the single application player. Reattaching the same instance is
  /// intentionally idempotent, while attaching a replacement removes every
  /// listener from the old instance first.
  void attachPlayer(PlayerModel playerModel) {
    if (!PlatformUtils.isWindows || _disposed) return;
    if (identical(_playerModel, playerModel)) {
      _scheduleSync(forceTimeline: true);
      return;
    }

    _detachPlayer();
    _playerModel = playerModel;
    playerModel.addListener(_onPlayerChanged);
    _processingStateSubscription = playerModel.audioPlayer.processingStateStream
        .listen((_) => _scheduleSync(forceTimeline: true));
    unawaited(_initializeNative());
    _scheduleSync(forceTimeline: true);
  }

  void _detachPlayer() {
    _playerModel?.removeListener(_onPlayerChanged);
    _playerModel = null;
    unawaited(_processingStateSubscription?.cancel());
    _processingStateSubscription = null;
  }

  void _onPlayerChanged() => _scheduleSync();

  void _scheduleSync({bool forceTimeline = false}) {
    if (_disposed || _playerModel == null) return;
    _syncPending = true;
    _forceTimeline = _forceTimeline || forceTimeline;
    if (!_syncRunning) unawaited(_drainSync());
  }

  Future<void> _drainSync() async {
    _syncRunning = true;
    try {
      await _initializeNative();
      while (_syncPending && !_disposed) {
        _syncPending = false;
        final forceTimeline = _forceTimeline;
        _forceTimeline = false;
        await _syncPlayerState(forceTimeline: forceTimeline);
      }
    } finally {
      _syncRunning = false;
      if (_syncPending && !_disposed) unawaited(_drainSync());
    }
  }

  Future<void> _syncPlayerState({required bool forceTimeline}) async {
    final player = _playerModel;
    if (player == null) return;

    final song = player.currentSong;
    if (song == null) {
      if (_lastPlaybackStatus != 'stopped') {
        if (await _invokeNative('setPlaybackStatus', {'status': 'stopped'})) {
          _lastPlaybackStatus = 'stopped';
        }
      }
      await _setEnabled(false);
      _lastSongId = null;
      _timelineThrottle.reset();
      return;
    }

    final songChanged = _lastSongId != song.id;
    if (songChanged) {
      if (await _invokeNative('updateMetadata', buildSmtcMetadata(song))) {
        _lastSongId = song.id;
        _timelineThrottle.reset();
      }
    }
    await _setEnabled(true);

    final processingState = player.audioPlayer.processingState;
    final playbackStatus = smtcPlaybackStatus(
      hasSong: true,
      isPlaying: player.isPlaying,
      isLoading:
          processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering,
      isCompleted: processingState == ProcessingState.completed,
    );
    final statusChanged = playbackStatus != _lastPlaybackStatus;
    if (statusChanged) {
      if (await _invokeNative('setPlaybackStatus', {
        'status': playbackStatus,
      })) {
        _lastPlaybackStatus = playbackStatus;
      }
    }

    if (_timelineThrottle.shouldSend(
      _clock.elapsed,
      force: forceTimeline || songChanged || statusChanged,
    )) {
      if (!await _sendTimeline(player)) _timelineThrottle.reset();
    }
  }

  Future<bool> _setEnabled(bool enabled) async {
    if (_lastEnabled == enabled) return true;
    final updated = await _invokeNative('setEnabled', {'enabled': enabled});
    if (updated) _lastEnabled = enabled;
    return updated;
  }

  Future<bool> _sendTimeline(PlayerModel player) {
    final timeline = buildSmtcTimeline(
      position: player.position,
      duration: player.duration,
    );
    if (timeline == null) return Future<bool>.value(false);
    return _invokeNative('updateTimeline', timeline);
  }

  Future<void> _handleNativeCommand(MethodCall call) async {
    final player = _playerModel;
    if (player == null || player.currentSong == null || _disposed) return;

    switch (call.method) {
      case 'play':
        player.resume();
        break;
      case 'pause':
        player.pause();
        break;
      case 'next':
        await _runTrackChange(player.playNext);
        break;
      case 'previous':
        await _runTrackChange(player.playPrevious);
        break;
      case 'seek':
        final arguments = call.arguments;
        final positionMs =
            arguments is Map ? arguments['positionMs'] as num? : null;
        if (positionMs == null) return;
        final seekPosition = resolveSmtcSeek(
          Duration(milliseconds: positionMs.round()),
          player.duration,
        );
        if (seekPosition == null) return;
        player.seek(seekPosition);
        _scheduleSync(forceTimeline: true);
        break;
    }
  }

  Future<void> _runTrackChange(Future<void> Function() command) async {
    try {
      await _trackChangeExecutor.run(command);
    } catch (error, stackTrace) {
      debugPrint('Windows SMTC track change failed: $error\n$stackTrace');
    }
  }

  Future<bool> _invokeNative(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!PlatformUtils.isWindows || _disposed) return false;
    return _invokeChannel(method, arguments);
  }

  Future<bool> _invokeChannel(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
      return true;
    } on MissingPluginException catch (error) {
      debugPrint('Windows SMTC channel is unavailable: $error');
      return false;
    } on PlatformException catch (error) {
      debugPrint('Windows SMTC $method failed: ${error.message}');
      return false;
    }
  }

  void dispose() {
    if (!PlatformUtils.isWindows || _disposed) return;
    _detachPlayer();
    _disposed = true;
    _lifecycleGeneration++;
    _syncPending = false;
    _forceTimeline = false;
    _clock.stop();
    if (_handlerInstalled) {
      _channel.setMethodCallHandler(null);
      _handlerInstalled = false;
    }
    _nativeInitialized = false;
    final disposal = _lifecycleTail.then((_) async {
      await _invokeChannel('dispose');
      _resetNativeStateCache();
    });
    _lifecycleTail = disposal;
    unawaited(disposal);
  }
}
