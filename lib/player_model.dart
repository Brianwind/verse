import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async'; // 添加 StreamSubscription 所需导入
import 'fluid_background.dart'; // 导入FluidBackground
import 'netease_api/netease_music_api.dart';

enum PlayMode { order, shuffle }

class PlayerModel extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Song2? _currentSong;
  String? _songUrl;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  String? _playlistId;
  List<Song2> _playlistTracks = [];
  int _currentIndex = -1;
  PlayMode _playMode = PlayMode.order;
  List<int> _shuffleOrder = [];

  bool _isAutoChanging = false;

  late final StreamSubscription<PlaybackEvent> _playbackEventSubscription;

  // 添加喜欢歌曲状态Map，用于缓存歌曲的喜欢状态
  final Map<String, bool> _likedSongs = {};

  // 用于缓存歌曲URL的映射，避免重复请求
  final Map<String, String> _songUrlCache = {};

  // 使用单独的缓存锁避免同一首歌多次请求URL
  final Set<String> _fetchingUrls = {};

  // 添加URL预缓存功能，提前加载下一首歌曲的URL
  Future<void> _preloadNextSongUrl() async {
    if (_playlistTracks.isEmpty || _currentIndex < 0) return;

    // 计算下一首歌的索引
    int nextIndex;
    if (_playMode == PlayMode.order) {
      nextIndex = (_currentIndex + 1) % _playlistTracks.length;
    } else {
      nextIndex = (_currentIndex + 1) % _shuffleOrder.length;
      nextIndex = _shuffleOrder[nextIndex];
    }

    final nextSong = _playlistTracks[nextIndex];
    if (nextSong.id != null && !_songUrlCache.containsKey(nextSong.id)) {
      // 非阻塞式预加载
      _getSongUrl(nextSong.id).then((url) {
        // 已经预缓存URL，无需其他操作
      });
    }
  }

  String? get nextSongId {
    if (_playlistTracks.isEmpty || _currentIndex < 0) return null;
    int nextIndex;
    if (_playMode == PlayMode.order) {
      nextIndex = (_currentIndex + 1) % _playlistTracks.length;
    } else {
      nextIndex = (_currentIndex + 1) % _shuffleOrder.length;
      nextIndex = _shuffleOrder[nextIndex];
    }
    return _playlistTracks[nextIndex].id;
  }

  Song2? get currentSong => _currentSong;
  String? get songUrl => _songUrl;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioPlayer get audioPlayer => _audioPlayer;
  String? get playlistId => _playlistId;
  List<Song2> get playlistTracks => _playlistTracks;
  int get currentIndex => _currentIndex;
  PlayMode get playMode => _playMode;

  PlayerModel() {
    _audioPlayer.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _audioPlayer.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();
    });

    _audioPlayer.processingStateStream.listen((state) {
      debugPrint("处理状态变化: $state");
      if (state == ProcessingState.completed) {
        debugPrint("播放完成，准备播放下一首");
        _playNextSafe();
      }
    });

    Stream.periodic(const Duration(milliseconds: 500)).listen((_) {
      if (_audioPlayer.position.inMilliseconds > 0 &&
          _audioPlayer.duration != null &&
          _audioPlayer.duration!.inMilliseconds > 0 &&
          _audioPlayer.position.inMilliseconds >=
              _audioPlayer.duration!.inMilliseconds - 500 &&
          _audioPlayer.processingState != ProcessingState.completed &&
          _audioPlayer.playing) {
        _audioPlayer.pause();
        _playNextSafe();
      }
    });

    _playbackEventSubscription = _audioPlayer.playbackEventStream.listen((
      event,
    ) {
      if (event.processingState == ProcessingState.completed) {
        debugPrint("从playbackEventStream检测到播放完成");
        _playNextSafe();
      }
    });

    // 初始化时加载用户喜欢的歌曲列表
    fetchLikedSongs();
  }

  void _playNextSafe() {
    if (!_isAutoChanging) {
      _isAutoChanging = true;

      Future.delayed(const Duration(milliseconds: 300), () async {
        try {
          await playNext();
        } catch (e) {
          debugPrint("自动切换下一首时出错: $e");
        } finally {
          _isAutoChanging = false;
        }
      });
    }
  }

  Future<void> playPlaylist({
    required String playlistId,
    required List<Song2> tracks,
    required int startIndex,
    required String url,
  }) async {
    _playlistId = playlistId;
    _playlistTracks = tracks;
    _currentIndex = startIndex;
    _playMode = _playMode;
    _shuffleOrder = List.generate(tracks.length, (i) => i);
    if (_playMode == PlayMode.shuffle) {
      _shuffleOrder.shuffle();
      _currentIndex = _shuffleOrder.indexOf(startIndex);
    }
    await playSong(tracks[startIndex], url);
    notifyListeners();
  }

  void togglePlayMode() {
    if (_playMode == PlayMode.order) {
      _playMode = PlayMode.shuffle;
      _shuffleOrder = List.generate(_playlistTracks.length, (i) => i);
      _shuffleOrder.shuffle();
      if (_currentIndex >= 0 && _currentIndex < _playlistTracks.length) {
        _currentIndex = _shuffleOrder.indexOf(_currentIndex);
      }
    } else {
      if (_currentIndex >= 0 && _currentIndex < _shuffleOrder.length) {
        _currentIndex = _shuffleOrder[_currentIndex];
      }
      _playMode = PlayMode.order;
    }
    notifyListeners();
  }

  Future<void> playPrevious() async {
    if (_playlistTracks.isEmpty) return;
    if (_playMode == PlayMode.order) {
      _currentIndex =
          (_currentIndex - 1 + _playlistTracks.length) % _playlistTracks.length;
    } else {
      _currentIndex =
          (_currentIndex - 1 + _shuffleOrder.length) % _shuffleOrder.length;
    }
    final idx =
        _playMode == PlayMode.order
            ? _currentIndex
            : _shuffleOrder[_currentIndex];
    final song = _playlistTracks[idx];

    final url = await _getSongUrl(song.id);
    await playSong(song, url);
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_playlistTracks.isEmpty) return;

    try {
      await _audioPlayer.stop();

      if (_playMode == PlayMode.order) {
        _currentIndex = (_currentIndex + 1) % _playlistTracks.length;
      } else {
        _currentIndex = (_currentIndex + 1) % _shuffleOrder.length;
      }

      final idx =
          _playMode == PlayMode.order
              ? _currentIndex
              : _shuffleOrder[_currentIndex];
      final song = _playlistTracks[idx];
      final url = await _getSongUrl(song.id);

      // 如果获取不到URL，尝试播放下一首
      if (url.isEmpty) {
        return await playNext();
      }

      await playSong(song, url);
      notifyListeners();
    } catch (e) {
      debugPrint('播放下一首歌曲时出错: $e');
      await Future.delayed(const Duration(seconds: 1));
      if (_playlistTracks.isNotEmpty) {
        await playNext();
      }
    }
  }

  Future<String> _getSongUrl(String songId) async {
    // 首先检查缓存
    if (_songUrlCache.containsKey(songId)) {
      return _songUrlCache[songId]!;
    }

    // 避免同一首歌重复请求
    if (_fetchingUrls.contains(songId)) {
      // 等待直到该歌曲的URL请求完成
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return _fetchingUrls.contains(songId);
      });

      // 现在应该有缓存了
      if (_songUrlCache.containsKey(songId)) {
        return _songUrlCache[songId]!;
      }
    }

    try {
      _fetchingUrls.add(songId);
      final urlWrap = await NeteaseMusicApi().songUrl([songId]);
      final url =
          urlWrap.data?.isNotEmpty == true ? urlWrap.data![0].url ?? '' : '';

      // 缓存URL
      if (url.isNotEmpty) {
        _songUrlCache[songId] = url;
      }

      return url;
    } finally {
      _fetchingUrls.remove(songId);
    }
  }

  Future<void> playSong(Song2 song, String url) async {
    if (url.isEmpty) {
      debugPrint("播放歌曲URL为空: ${song.name}");
      if (_playlistTracks.isNotEmpty) {
        return await playNext();
      }
      return;
    }

    // 设置加载标志
    debugPrint("开始加载歌曲: ${song.name}");

    // 预加载下一首歌曲，提高响应速度
    Future.microtask(() {
      _preloadNextSongUrl();
    });

    _currentSong = song;
    _songUrl = url;

    try {
      // 如果歌曲有封面图，先开始预加载背景和颜色提取
      // 这是非阻塞操作，会在后台线程完成
      if (song.al?.picUrl != null) {
        FluidBackground.preloadBackground(song.al?.picUrl);
      }

      // 先指示状态改变，提高UI响应速度
      _isPlaying = true;
      notifyListeners();

      // 停止当前播放，准备新的音频源
      await _audioPlayer.stop();

      debugPrint("设置音频源: $url");
      // 明确等待音频源设置完成
      await _audioPlayer
          .setAudioSource(
            AudioSource.uri(Uri.parse(url)),
            preload: true, // 确保预加载
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint("设置音频源超时");
              return null;
            },
          );

      // 强制延迟一小段时间，确保音频源已准备就绪
      await Future.delayed(const Duration(milliseconds: 50));

      // 确保UI状态为播放
      if (!_isPlaying) {
        _isPlaying = true;
        notifyListeners();
      }

      // 使用明确的播放指令，并捕获所有可能的错误
      try {
        debugPrint("发送播放命令");
        // 使用同步播放命令
        _audioPlayer.play();
        debugPrint("播放命令已发送");
      } catch (playError) {
        debugPrint("播放指令发生错误: $playError");
        // 如果播放失败，等待后重试
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          debugPrint("重试播放命令");
          await _audioPlayer.play();
        } catch (e) {
          debugPrint("重试播放命令仍然失败: $e");
        }
      }
    } catch (e) {
      debugPrint("播放歌曲时出错: $e");
      // 出错时尝试播放下一首
      if (_playlistTracks.isNotEmpty) {
        return await playNext();
      }
    }
  }

  void pause() {
    _audioPlayer.pause();
  }

  void resume() {
    _audioPlayer.play();
  }

  void seek(Duration pos) {
    _audioPlayer.seek(pos);
  }

  // 获取当前歌曲的喜欢状态
  bool isCurrentSongLiked() {
    if (_currentSong?.id == null) return false;

    // 确保使用字符串格式的ID进行比较
    final songId = _currentSong!.id.toString();

    // 直接检查ID是否在列表中
    if (_likedSongs.containsKey(songId)) {
      return true;
    }

    // 尝试其他可能的格式（如果是数字ID）
    if (int.tryParse(songId) != null) {
      // 遍历所有喜欢的歌曲
      for (final likedId in _likedSongs.keys) {
        // 尝试数值比较
        if (int.tryParse(likedId) != null &&
            int.parse(likedId) == int.parse(songId)) {
          return true;
        }
      }
    }

    return false;
  }

  // 检查歌曲是否被喜欢
  bool isSongLiked(String songId) {
    // 确保使用字符串格式
    songId = songId.toString();

    // 也尝试检查不同格式的ID
    if (!(_likedSongs[songId] ?? false)) {
      // 如果当前格式没找到，尝试其他可能的格式
      if (_likedSongs.containsKey(int.tryParse(songId)?.toString())) {
        return true;
      }
    }

    return _likedSongs[songId] ?? false;
  }

  // 获取用户喜欢的歌曲列表
  Future<void> fetchLikedSongs() async {
    try {
      // 获取当前登录用户信息
      final accountInfo = NeteaseMusicApi().usc.accountInfo;
      if (accountInfo?.profile?.userId == null) {
        debugPrint('用户未登录，无法获取喜欢的歌曲');
        return;
      }

      debugPrint('开始获取喜欢的歌曲列表，用户ID: ${accountInfo!.profile!.userId}');

      // 调用API获取用户喜欢的歌曲列表
      final result = await NeteaseMusicApi().likeSongList(
        accountInfo.profile!.userId!,
      );
      if (result.code == 200 && result.ids != null) {
        debugPrint('获取喜欢的歌曲列表成功: ${result.ids!.length}首');

        // 清空当前缓存并更新
        _likedSongs.clear();

        // 记录前5个ID用于调试
        final sampleIds =
            result.ids!.take(5).map((id) => id.toString()).toList();
        debugPrint('示例ID: ${sampleIds.join(", ")}');

        // 存储多种格式的ID以确保匹配
        for (final id in result.ids!) {
          final strId = id.toString();
          _likedSongs[strId] = true;

          // 如果当前ID是当前播放歌曲的ID，打印确认信息
          if (_currentSong != null &&
              _currentSong!.id != null &&
              (_currentSong!.id == strId ||
                  _currentSong!.id.toString() == strId)) {
            debugPrint('*** 当前播放歌曲(${_currentSong!.id})在喜欢列表中 ***');
          }
        }

        // 如果当前正在播放歌曲，检查它是否在喜欢列表中
        if (_currentSong != null && _currentSong!.id != null) {
          final currId = _currentSong!.id.toString();
          final isLiked = _likedSongs.containsKey(currId);
          debugPrint('当前播放歌曲ID: $currId, 是否在喜欢列表中: $isLiked');

          // 如果未找到，尝试遍历所有喜欢的歌曲ID进行比较
          if (!isLiked) {
            for (final likedId in _likedSongs.keys) {
              if (likedId == currId ||
                  int.tryParse(likedId) == int.tryParse(currId)) {
                debugPrint('找到匹配! currId=$currId, likedId=$likedId');
                _likedSongs[currId] = true;
                break;
              }
            }
          }
        }

        notifyListeners();
      } else {
        debugPrint('获取喜欢的歌曲列表失败: ${result.code}');
      }
    } catch (e) {
      debugPrint('获取喜欢的歌曲列表异常: $e');
    }
  }

  // 切换歌曲的喜欢状态
  Future<bool> toggleLikeSong(String songId) async {
    try {
      // 获取当前喜欢状态的反向值
      final like = !(_likedSongs[songId] ?? false);

      // 调用API设置歌曲的喜欢状态
      final result = await NeteaseMusicApi().likeSong(songId, like);

      if (result.code == 200) {
        // 更新缓存中的状态
        if (like) {
          _likedSongs[songId] = true;
        } else {
          _likedSongs.remove(songId);
        }
        notifyListeners();
        debugPrint('${like ? "喜欢" : "取消喜欢"}歌曲成功: $songId');
        return true;
      } else {
        debugPrint('${like ? "喜欢" : "取消喜欢"}歌曲失败: ${result.code}');
        return false;
      }
    } catch (e) {
      debugPrint('${_likedSongs[songId] ?? false ? "取消喜欢" : "喜欢"}歌曲异常: $e');
      return false;
    }
  }

  // 添加歌曲到歌单
  Future<bool> addSongToPlaylist(String songId, String playlistId) async {
    try {
      final result = await NeteaseMusicApi().playlistManipulateTracks(
        playlistId,
        songId,
        true, // true表示添加
      );

      if (result.code == 200) {
        debugPrint('歌曲($songId)添加到歌单($playlistId)成功');
        return true;
      } else {
        debugPrint('歌曲添加到歌单失败: ${result.code}');
        return false;
      }
    } catch (e) {
      debugPrint('歌曲添加到歌单异常: $e');
      return false;
    }
  }

  // 从歌单中删除歌曲
  Future<bool> removeSongFromPlaylist(String songId, String playlistId) async {
    try {
      final result = await NeteaseMusicApi().playlistManipulateTracks(
        playlistId,
        songId,
        false, // false表示删除
      );

      if (result.code == 200) {
        debugPrint('歌曲($songId)从歌单($playlistId)移除成功');
        return true;
      } else {
        debugPrint('歌曲从歌单移除失败: ${result.code}');
        return false;
      }
    } catch (e) {
      debugPrint('歌曲从歌单移除异常: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _playbackEventSubscription.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
