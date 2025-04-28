import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:async';
import 'netease_api/netease_music_api.dart';
import 'player_model.dart';
import 'lyrics_view.dart';
import 'fluid_background.dart'; // 导入流体背景组件

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isMouseInWindow = false;
  bool _isMouseOverAppBar = false; // 新增变量，跟踪鼠标是否在AppBar区域
  bool _isBackgroundReady = false;

  // 存储从封面图片提取的主题颜色
  ImageThemeColors? _themeColors;

  @override
  void initState() {
    super.initState();
    _startHideControlsTimer();

    // 预加载当前歌曲背景
    _preloadCurrentSongBackground();
  }

  // 预加载当前歌曲背景图片
  Future<void> _preloadCurrentSongBackground() async {
    final player = Provider.of<PlayerModel>(context, listen: false);
    final song = player.currentSong;
    if (song != null && song.al?.picUrl != null) {
      try {
        // 预缓存图片并预加载颜色
        await FluidBackground.preloadBackground(song.al?.picUrl);

        // 获取主题颜色
        final themeColors = await FluidBackground.getThemeColorsForImage(
          song.al?.picUrl,
        );

        if (mounted) {
          setState(() {
            _isBackgroundReady = true;
            _themeColors = themeColors;
          });
        }
      } catch (e) {
        debugPrint('预加载背景失败: $e');
      }
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          (_isMouseInWindow == false || _showControls) &&
          !_isMouseOverAppBar) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _handleMouseEnter(PointerEnterEvent event) {
    setState(() {
      _isMouseInWindow = true;
      _showControls = true;
    });
    _startHideControlsTimer();
  }

  void _handleMouseExit(PointerExitEvent event) {
    setState(() {
      _isMouseInWindow = false;
      // 只有当鼠标不在AppBar区域时才隐藏控件
      if (!_isMouseOverAppBar) {
        _showControls = false;
      }
    });
  }

  void _handleMouseMove(PointerHoverEvent event) {
    // 检查鼠标是否在AppBar区域
    _isMouseOverAppBar = event.position.dy < 40; // AppBar高度为40

    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _startHideControlsTimer();
  }

  // 处理主题颜色更新的回调
  void _onThemeColorsExtracted(ImageThemeColors colors) {
    if (mounted) {
      setState(() {
        _themeColors = colors;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final song = player.currentSong;
    if (song == null)
      return const Scaffold(body: Center(child: Text('暂无播放歌曲')));
    final artists = song.ar?.map((a) => a.name).join(', ') ?? '';
    final cover = song.al?.picUrl;
    final duration = player.duration;
    final position = player.position;

    // 根据主题颜色创建文本样式
    final TextStyle titleStyle = TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.bold,
      color:
          _themeColors?.textColor ??
          Theme.of(context).textTheme.titleLarge?.color,
    );

    final TextStyle artistStyle = TextStyle(
      fontSize: 24,
      color: _themeColors?.textColor.withOpacity(0.8) ?? Colors.grey,
    );

    return Scaffold(
      extendBodyBehindAppBar: true, // 确保内容延伸到AppBar后面
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(40),
        // 恢复AnimatedOpacity，使返回按钮与底部控制栏行为一致
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 40,
            leading: MouseRegion(
              // 为返回按钮添加MouseRegion以重置计时器
              onEnter: (_) {
                setState(() {
                  _showControls = true;
                });
                _startHideControlsTimer(); // 重新开始计时器，而不是取消
              },
              onHover: (_) {
                if (!_showControls) {
                  setState(() {
                    _showControls = true;
                  });
                }
                _startHideControlsTimer();
              },
              child: IconButton(
                icon: FaIcon(
                  FontAwesomeIcons.angleDown,
                  color:
                      _themeColors?.textColor ??
                      (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary),
                  size: 24,
                ),
                padding: EdgeInsets.zero,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                hoverColor: Colors.transparent,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ),
      body: MouseRegion(
        onEnter: _handleMouseEnter,
        onExit: _handleMouseExit,
        onHover: _handleMouseMove,
        child: Stack(
          children: [
            // 使用AnimatedSwitcher确保背景平滑过渡
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: FluidBackground(
                key: ValueKey(cover ?? 'no-cover'), // 确保图片变化时重建Widget
                imageUrl: cover,
                isPlaying: player.isPlaying,
                staticMode: true, // 总是使用静态模式
                onThemeColorsExtracted: _onThemeColorsExtracted, // 添加颜色更新回调
              ),
            ),

            // 主要内容区域（占据整个空间）
            _buildMainContent(
              context,
              player,
              song,
              artists,
              cover,
              duration,
              position,
              titleStyle, // 传递标题样式
              artistStyle, // 传递艺术家样式
            ),

            // 底部控制区（使用Positioned.bottom将它定位在底部）
            _buildPlayerControls(context, player, song, duration, position),
          ],
        ),
      ),
    );
  }

  // 构建主内容区域
  Widget _buildMainContent(
    BuildContext context,
    PlayerModel player,
    Song2 song,
    String artists,
    String? cover,
    Duration duration,
    Duration position,
    TextStyle titleStyle, // 添加标题样式参数
    TextStyle artistStyle, // 添加艺术家样式参数
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧：专辑封面和歌曲信息
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.only(right: 40.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 540),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final imageSize =
                              constraints.maxWidth * 0.7 < 240.0
                                  ? 240.0
                                  : constraints.maxWidth * 0.7;

                          return Hero(
                            tag: 'song-cover-${song.id}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child:
                                  cover != null
                                      ? CachedNetworkImage(
                                        imageUrl: cover,
                                        width: imageSize,
                                        height: imageSize,
                                        fit: BoxFit.cover,
                                        placeholder:
                                            (context, url) => SizedBox(
                                              width: imageSize,
                                              height: imageSize,
                                            ),
                                        errorWidget:
                                            (context, url, error) => Icon(
                                              Icons.music_note,
                                              size: imageSize / 2,
                                            ),
                                      )
                                      : Icon(
                                        Icons.music_note,
                                        size: imageSize / 2,
                                      ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                      Hero(
                        tag: 'song-title-${song.id}',
                        child: Material(
                          color: Colors.transparent,
                          child: Text(
                            song.name ?? '',
                            style: titleStyle, // 使用提取的主题颜色
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Hero(
                        tag: 'song-artist-${song.id}',
                        child: Material(
                          color: Colors.transparent,
                          child: Text(
                            artists,
                            style: artistStyle, // 使用提取的主题颜色
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 右侧：歌词
          Expanded(
            flex: 4,
            child: Center(
              child: LyricsView(
                songId: song.id,
                themeColors: _themeColors, // 传递主题颜色给歌词组件
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建播放器控制区域
  Widget _buildPlayerControls(
    BuildContext context,
    PlayerModel player,
    Song2 song,
    Duration duration,
    Duration position,
  ) {
    final Color progressBarColor =
        _themeColors?.textColor ?? Theme.of(context).colorScheme.primary;
    final Color textColor =
        _themeColors?.textColor ??
        Theme.of(context).textTheme.bodyMedium?.color ??
        Colors.white;

    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: _showControls ? 0 : -60,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          height: _showControls ? 100 : 0,
          clipBehavior: Clip.hardEdge,
          padding: _showControls ? const EdgeInsets.all(12.0) : EdgeInsets.zero,
          margin: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child:
                      duration.inMilliseconds > 0
                          ? ProgressBar(
                            progress: position,
                            total: duration,
                            onSeek: player.seek,
                            timeLabelTextStyle: const TextStyle(
                              fontSize: 0,
                              color: Colors.transparent,
                            ),
                            barHeight: 4,
                            baseBarColor: textColor.withValues(
                              alpha: 0.3,
                            ), // 使用字体色的低透明度
                            progressBarColor: progressBarColor, // 使用提取的主题颜色
                            thumbColor: progressBarColor, // 使用提取的主题颜色
                            thumbRadius: 6,
                          )
                          : const SizedBox(height: 16.0),
                ),
              ),

              // 播放控制按钮
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                child: Container(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 左侧时间显示
                      AnimatedOpacity(
                        opacity: _showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                        child: Row(
                          children: [
                            Text(
                              _formatDuration(position),
                              style: TextStyle(
                                fontSize: 14,
                                color: textColor.withOpacity(0.8), // 使用提取的主题颜色
                              ),
                            ),
                            Text(
                              ' / ',
                              style: TextStyle(
                                fontSize: 14,
                                color: textColor.withOpacity(0.8), // 使用提取的主题颜色
                              ),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: TextStyle(
                                fontSize: 14,
                                color: textColor.withOpacity(0.8), // 使用提取的主题颜色
                              ),
                            ),
                            // 添加喜欢按钮到左侧区域
                            const SizedBox(width: 16),
                            IconButton(
                              icon: Icon(
                                player.isCurrentSongLiked()
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color:
                                    player.isCurrentSongLiked()
                                        ? Colors.red
                                        : textColor, // 使用提取的主题颜色
                                size: 22,
                              ),
                              splashRadius: 20,
                              tooltip:
                                  player.isCurrentSongLiked() ? '取消喜欢' : '喜欢',
                              onPressed: () async {
                                if (song.id != null) {
                                  await player.toggleLikeSong(song.id!);
                                }
                              },
                            ),
                            // 添加收藏到歌单按钮
                            IconButton(
                              icon: Icon(
                                Icons.playlist_add,
                                color: textColor, // 使用提取的主题颜色
                                size: 22,
                              ),
                              splashRadius: 20,
                              tooltip: '收藏到歌单',
                              onPressed: () {
                                if (song.id != null) {
                                  _showAddToPlaylistDialog(
                                    context,
                                    song.id!,
                                    player,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      // 中间控制按钮组
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.skip_previous,
                              size: 32,
                              color: textColor, // 使用提取的主题颜色
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => player.playPrevious(),
                          ),
                          const SizedBox(width: 24),
                          IconButton(
                            icon: Icon(
                              player.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              size: 48,
                              color: textColor, // 使用提取的主题颜色
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              if (player.isPlaying) {
                                player.audioPlayer.pause();
                              } else {
                                player.audioPlayer.play();
                              }
                            },
                          ),
                          const SizedBox(width: 24),
                          IconButton(
                            icon: Icon(
                              Icons.skip_next,
                              size: 32,
                              color: textColor, // 使用提取的主题颜色
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => player.playNext(),
                          ),
                        ],
                      ),

                      // 右侧占位，保持控制按钮居中
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // 添加与左侧区域相匹配的占位组件，使控制按钮组真正居中
                          const SizedBox(width: 178.8),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return [if (duration.inHours > 0) hours, minutes, seconds].join(':');
  }

  // 显示添加到歌单的对话框
  void _showAddToPlaylistDialog(
    BuildContext context,
    String songId,
    PlayerModel player,
  ) async {
    // 使用key标识对话框，方便后续关闭
    final loadingDialogKey = GlobalKey<State>();

    // 显示加载指示器
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            key: loadingDialogKey,
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Center(child: CircularProgressIndicator()),
          ),
    );

    void _closeLoadingDialog() {
      // 检查对话框是否仍然显示，然后关闭它
      if (loadingDialogKey.currentContext != null &&
          Navigator.of(loadingDialogKey.currentContext!).canPop()) {
        Navigator.of(loadingDialogKey.currentContext!).pop();
      } else if (context.mounted && Navigator.of(context).canPop()) {
        // 备用方案
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    try {
      // 获取当前登录用户信息
      final accountInfo = NeteaseMusicApi().usc.accountInfo;
      if (accountInfo?.profile?.userId == null) {
        _closeLoadingDialog(); // 关闭加载指示器
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先登录')));
        }
        return;
      }

      // 使用非空断言前先将变量赋值给本地变量，确保安全访问
      final userProfile = accountInfo!.profile!;
      final userId = userProfile.userId.toString();

      // 获取用户创建的歌单
      final playlistResult = await NeteaseMusicApi().userPlayList(userId);

      // 关闭加载指示器
      _closeLoadingDialog();

      if (!context.mounted) return; // 安全检查

      if (playlistResult.code != 200 || playlistResult.playlist == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('获取歌单列表失败')));
        return;
      }

      // 过滤出用户创建的歌单（不包括"喜欢的音乐"，因为可以通过喜欢按钮操作）
      final userPlaylists =
          playlistResult.playlist!.where((pl) {
            // 排除"喜欢的音乐"歌单和特殊类型歌单
            return pl.creator?.userId == userId &&
                pl.name != '${userProfile.nickname}喜欢的音乐' &&
                (pl.specialType == null || pl.specialType == 0);
          }).toList();

      if (userPlaylists.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有可用的歌单，请先创建歌单')));
        return;
      }

      // 显示歌单选择对话框
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('收藏到歌单'),
              content: SizedBox(
                width:
                    MediaQuery.of(dialogContext).size.width / 4, // 将宽度缩小到原来的1/4
                height:
                    MediaQuery.of(dialogContext).size.height /
                    2, // 将高度缩小到原来的1/2
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: userPlaylists.length,
                  itemBuilder: (itemContext, index) {
                    final playlist = userPlaylists[index];
                    return ListTile(
                      leading:
                          playlist.coverImgUrl != null
                              ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: CachedNetworkImage(
                                  imageUrl: playlist.coverImgUrl!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  placeholder:
                                      (_, __) =>
                                          const SizedBox(width: 40, height: 40),
                                  errorWidget:
                                      (_, __, ___) =>
                                          const Icon(Icons.queue_music),
                                ),
                              )
                              : const Icon(Icons.queue_music),
                      title: Text(playlist.name ?? '未命名歌单'),
                      subtitle: Text('${playlist.trackCount ?? 0}首'),
                      onTap: () async {
                        // 关闭歌单选择对话框
                        Navigator.of(itemContext).pop();

                        // 使用新的key标识第二个加载对话框
                        final addingDialogKey = GlobalKey<State>();

                        // 显示加载指示器
                        if (!context.mounted) return;
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder:
                              (loadContext) => AlertDialog(
                                key: addingDialogKey,
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                content: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                        );

                        void _closeAddingDialog() {
                          if (addingDialogKey.currentContext != null &&
                              Navigator.of(
                                addingDialogKey.currentContext!,
                              ).canPop()) {
                            Navigator.of(addingDialogKey.currentContext!).pop();
                          } else if (context.mounted &&
                              Navigator.of(context).canPop()) {
                            Navigator.of(context, rootNavigator: true).pop();
                          }
                        }

                        try {
                          final success = await player.addSongToPlaylist(
                            songId,
                            playlist.id,
                          );

                          // 确保关闭加载指示器
                          _closeAddingDialog();

                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(success ? '收藏成功' : '收藏失败'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        } catch (e) {
                          // 确保关闭加载指示器
                          _closeAddingDialog();

                          if (!context.mounted) return;
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('收藏失败: $e')));
                        }
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
              ],
            ),
      );
    } catch (e) {
      _closeLoadingDialog(); // 关闭加载指示器

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载歌单失败: $e')));
    }
  }
}
