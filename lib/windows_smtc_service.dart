import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'constants/platform.dart';
import 'player_model.dart';
import 'netease_api/src/api/play/bean.dart'; // 添加 Song2 类的导入

/// 专为 Windows 平台实现的 System Media Transport Controls (SMTC) 服务类
/// 该类只在 Windows 平台上运行，其他平台上将是一个空壳
class WindowsSmtcService {
  SMTCWindows? _smtc;
  PlayerModel? _playerModel;
  StreamSubscription? _buttonPressSubscription;

  // 单例模式
  static WindowsSmtcService? _instance;
  static WindowsSmtcService get instance {
    _instance ??= WindowsSmtcService._();
    return _instance!;
  }

  WindowsSmtcService._();

  /// 初始化 SMTC 服务
  /// 只在 Windows 平台上进行实际初始化
  static Future<void> initialize() async {
    if (PlatformUtils.isWindows) {
      debugPrint('初始化 Windows SMTC 服务');
      try {
        await SMTCWindows.initialize();
        debugPrint('Windows SMTC 初始化成功');
      } catch (e) {
        debugPrint('Windows SMTC 初始化失败: $e');
      }
    }
  }

  /// 绑定播放器模型，监听播放器状态变化
  void attachPlayer(PlayerModel playerModel) {
    if (!PlatformUtils.isWindows) return;

    _playerModel = playerModel;

    // 创建 SMTC 实例并配置初始状态
    _setupSmtc();

    // 监听播放器状态变化
    _playerModel!.addListener(_onPlayerStateChanged);
  }

  /// 设置 SMTC 实例并配置初始状态
  void _setupSmtc() {
    if (!PlatformUtils.isWindows || _playerModel == null) return;

    try {
      _smtc = SMTCWindows(
        metadata: _buildEmptyMetadata(),
        timeline: const PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: 1000,
          positionMs: 0,
          minSeekTimeMs: 0,
          maxSeekTimeMs: 1000,
        ),
        config: const SMTCConfig(
          fastForwardEnabled: false,
          nextEnabled: true,
          pauseEnabled: true,
          playEnabled: true,
          rewindEnabled: false,
          prevEnabled: true,
          stopEnabled: false,
        ),
      );

      // 注册按钮事件监听
      _buttonPressSubscription = _smtc!.buttonPressStream.listen(
        _handleButtonPress,
      );

      // 设置初始播放状态
      _updateSmtcPlaybackStatus(_playerModel!.isPlaying);

      // 如果当前有歌曲在播放，立即更新 SMTC 元数据
      if (_playerModel!.currentSong != null) {
        _updateMetadata(_playerModel!.currentSong!);
        _updatePlaybackTimeline();
      }

      debugPrint('Windows SMTC 设置完成');
    } catch (e) {
      debugPrint('Windows SMTC 设置失败: $e');
    }
  }

  /// 创建一个空的元数据对象
  MusicMetadata _buildEmptyMetadata() {
    return const MusicMetadata(
      title: '无播放内容',
      album: '',
      artist: '',
      albumArtist: '',
      thumbnail: '',
    );
  }

  /// 处理 SMTC 按钮点击事件
  void _handleButtonPress(PressedButton button) {
    if (_playerModel == null) return;

    switch (button) {
      case PressedButton.play:
        debugPrint('SMTC 按下播放按钮');
        _playerModel!.resume();
        break;

      case PressedButton.pause:
        debugPrint('SMTC 按下暂停按钮');
        _playerModel!.pause();
        break;

      case PressedButton.next:
        debugPrint('SMTC 按下下一曲按钮');
        _playerModel!.playNext();
        break;

      case PressedButton.previous:
        debugPrint('SMTC 按下上一曲按钮');
        _playerModel!.playPrevious();
        break;

      default:
        // 忽略其他按钮
        break;
    }
  }

  // 保存上一次处理的歌曲ID，用于检测歌曲变化
  String? _lastSongId;
  bool? _lastPlayingState;

  /// 当播放器状态变化时更新 SMTC
  void _onPlayerStateChanged() {
    if (!PlatformUtils.isWindows || _smtc == null || _playerModel == null)
      return;

    final currentSong = _playerModel!.currentSong;
    final isPlaying = _playerModel!.isPlaying;

    // 只有在播放状态变化时才更新播放状态
    if (_lastPlayingState != isPlaying) {
      _lastPlayingState = isPlaying;
      _updateSmtcPlaybackStatus(isPlaying);
    }

    // 只有在歌曲变化或第一次加载时才更新元数据
    if (currentSong != null) {
      final currentSongId = currentSong.id;
      if (_lastSongId != currentSongId) {
        _lastSongId = currentSongId;
        _updateMetadata(currentSong);
        debugPrint('歌曲变化，更新 SMTC 元数据: ${currentSong.name}');
      }

      // 更新播放进度（这个可以每次都更新）
      _updatePlaybackTimeline();
    }
  }

  /// 更新 SMTC 播放状态
  void _updateSmtcPlaybackStatus(bool isPlaying) {
    if (_smtc == null) return;

    try {
      _smtc!.setPlaybackStatus(
        isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
    } catch (e) {
      debugPrint('更新 SMTC 播放状态失败: $e');
    }
  }

  /// 更新 SMTC 元数据
  void _updateMetadata(Song2 song) {
    if (_smtc == null) return;

    try {
      final metadata = MusicMetadata(
        title: song.name ?? '未知歌曲',
        album: song.al?.name ?? '',
        artist: song.ar?.map((a) => a.name).join(', ') ?? '未知艺术家',
        albumArtist: song.al?.name ?? '',
        thumbnail: song.al?.picUrl ?? '',
      );

      _smtc!.updateMetadata(metadata);
      debugPrint('已更新 SMTC 元数据: ${song.name}');
    } catch (e) {
      debugPrint('更新 SMTC 元数据失败: $e');
    }
  }

  /// 更新播放进度时间线
  void _updatePlaybackTimeline() {
    if (_smtc == null || _playerModel == null) return;

    try {
      final position = _playerModel!.position;
      final duration = _playerModel!.duration;

      if (duration.inMilliseconds > 0) {
        final timeline = PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: duration.inMilliseconds,
          positionMs: position.inMilliseconds,
          minSeekTimeMs: 0,
          maxSeekTimeMs: duration.inMilliseconds,
        );

        _smtc!.updateTimeline(timeline);
      }
    } catch (e) {
      debugPrint('更新 SMTC 时间线失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    if (!PlatformUtils.isWindows) return;

    debugPrint('释放 Windows SMTC 服务资源');

    // 移除播放器状态监听
    if (_playerModel != null) {
      _playerModel!.removeListener(_onPlayerStateChanged);
      _playerModel = null;
    }

    // 取消按钮事件订阅
    _buttonPressSubscription?.cancel();
    _buttonPressSubscription = null;

    // 释放 SMTC 资源
    _smtc?.dispose();
    _smtc = null;
  }
}
