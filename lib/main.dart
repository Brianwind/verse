import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:context_menus/context_menus.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';

import 'player_model.dart';
import 'netease_api/src/netease_api.dart';
import 'netease_api/src/api/login/bean.dart';
import 'login_page.dart';
import 'settings_page.dart';
import 'profile_page.dart';
import 'player_screen.dart';
import 'home_page.dart'; // 导入新的HomePage组件

// 添加自定义TitleBar组件
class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    // 定义按钮颜色
    final buttonColors = WindowButtonColors(
      iconNormal: Theme.of(context).colorScheme.onSurface,
      mouseOver: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      mouseDown: Theme.of(context).colorScheme.primary.withOpacity(0.2),
      iconMouseOver: Theme.of(context).colorScheme.primary,
      iconMouseDown: Theme.of(context).colorScheme.primary,
    );

    final closeButtonColors = WindowButtonColors(
      iconNormal: Theme.of(context).colorScheme.onSurface,
      mouseOver: Colors.red,
      mouseDown: Colors.red.shade800,
      iconMouseOver: Colors.white,
      iconMouseDown: Colors.white,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 左侧可拖动区域
            Expanded(
              child: WindowTitleBarBox(
                child: MoveWindow(
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0),
                        child: Text(
                          'Verse',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 右侧窗口控制按钮
            WindowButton(
              colors: buttonColors,
              iconBuilder:
                  (context) =>
                      Center(child: FaIcon(FontAwesomeIcons.minus, size: 12)),
              onPressed: () => appWindow.minimize(),
            ),
            WindowButton(
              colors: buttonColors,
              iconBuilder:
                  (context) =>
                      Center(child: FaIcon(FontAwesomeIcons.circle, size: 12)),
              onPressed: () => appWindow.maximizeOrRestore(),
            ),
            WindowButton(
              colors: closeButtonColors,
              iconBuilder:
                  (context) =>
                      Center(child: FaIcon(FontAwesomeIcons.xmark, size: 12)),
              onPressed: () => appWindow.close(),
            ),
          ],
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NeteaseMusicApi.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => PlayerModel(),
      child: const MainApp(),
    ),
  );
  doWhenWindowReady(() {
    const initialSize = Size(800, 500);
    appWindow.minSize = initialSize;
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.show();
  });
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool _logined = false;
  NeteaseAccountInfoWrap? _accountInfo;
  int _selectedIndex = 0;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    NeteaseMusicApi().usc.listenLoginState((state, info) {
      setState(() {
        _logined = state == LoginState.Logined;
        _accountInfo = info;
      });

      // 当登录状态发生变化时，通知PlayerModel更新喜欢歌曲列表
      if (state == LoginState.Logined) {
        // 我们不能在initState中直接使用Provider.of，所以使用延迟回调
        Future.delayed(Duration(milliseconds: 300), () {
          if (mounted) {
            // 确保组件仍然挂载
            Provider.of<PlayerModel>(context, listen: false).fetchLikedSongs();
          }
        });
      }
    });
    _logined = NeteaseMusicApi().usc.isLogined;
    _accountInfo = NeteaseMusicApi().usc.accountInfo;

    // 如果用户已经登录，也要刷新一次喜欢列表
    if (_logined) {
      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted) {
          Provider.of<PlayerModel>(context, listen: false).fetchLikedSongs();
        }
      });
    }
  }

  void _onNavTap(int idx) {
    setState(() {
      _selectedIndex = idx;
    });
  }

  void _onThemeModeChanged(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ContextMenuOverlay(
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          primarySwatch: Colors.blue,
          colorScheme: ColorScheme.fromSwatch(
            primarySwatch: Colors.blue,
          ).copyWith(secondary: Colors.blue),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.blue,
          colorScheme: ColorScheme.fromSwatch(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
          ).copyWith(secondary: Colors.blue),
        ),
        themeMode: _themeMode,
        debugShowCheckedModeBanner: false,
        home: Column(
          children: [
            // 添加自定义TitleBar
            const CustomTitleBar(),
            Expanded(
              child: Stack(
                children: [
                  Scaffold(
                    body: Row(
                      children: [
                        NavigationRail(
                          selectedIndex: _selectedIndex,
                          onDestinationSelected: _onNavTap,
                          labelType: NavigationRailLabelType.all,
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.home),
                              label: Text('首页'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.person),
                              label: Text('我的'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.login),
                              label: Text('登录'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.settings),
                              label: Text('设置'),
                            ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              if (_selectedIndex == 0) {
                                return const HomePage();
                              } else if (_selectedIndex == 1) {
                                return const ProfilePage();
                              } else if (_selectedIndex == 2) {
                                return LoginPage();
                              } else {
                                return SettingsPage(
                                  themeMode: _themeMode,
                                  onThemeModeChanged: _onThemeModeChanged,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: PlayerBar(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final song = player.currentSong;
    if (song == null) return SizedBox.shrink();
    final artists = song.ar?.map((a) => a.name).join(', ') ?? '';
    final cover = song.al?.picUrl;
    final duration = player.duration;
    final position = player.position;
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (cover != null)
                PlayerBarCover(
                  coverUrl: cover,
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder:
                            (context, animation, secondaryAnimation) =>
                                const PlayerScreen(), // 移除不存在的参数staticFluidMode
                        transitionDuration: const Duration(milliseconds: 500),
                        transitionsBuilder: (
                          context,
                          animation,
                          secondaryAnimation,
                          child,
                        ) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                      ),
                    );
                  },
                )
              else
                const Icon(Icons.music_note, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'song-title-${song.id}',
                      child: Material(
                        color: Colors.transparent,
                        child: Text(
                          song.name ?? '',
                          maxLines: 2, // 允许最多2行
                          overflow: TextOverflow.ellipsis, // 如果2行还不够，则显示省略号
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Hero(
                      tag: 'song-artist-${song.id}',
                      child: Material(
                        color: Colors.transparent,
                        child: Text(
                          artists,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child:
                          duration.inMilliseconds > 0
                              ? ProgressBar(
                                progress: position,
                                total: duration,
                                onSeek: player.seek,
                                timeLabelType: TimeLabelType.remainingTime,
                                barHeight: 4,
                                baseBarColor: Colors.grey.shade400,
                                progressBarColor:
                                    Theme.of(context).colorScheme.primary,
                                thumbColor:
                                    Theme.of(context).colorScheme.primary,
                                thumbRadius: 7,
                              )
                              : const SizedBox(height: 16),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 添加喜欢按钮
                  IconButton(
                    icon: Icon(
                      player.isCurrentSongLiked()
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: player.isCurrentSongLiked() ? Colors.red : null,
                      size: 20,
                    ),
                    tooltip: player.isCurrentSongLiked() ? '取消喜欢' : '喜欢',
                    onPressed: () async {
                      if (song.id != null) {
                        await player.toggleLikeSong(song.id!);
                      }
                    },
                  ),
                  // 添加收藏到歌单按钮
                  IconButton(
                    icon: const Icon(Icons.playlist_add, size: 20),
                    tooltip: '收藏到歌单',
                    onPressed: () {
                      if (song.id != null) {
                        _showAddToPlaylistDialog(context, song.id!, player);
                      }
                    },
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.backward, size: 18),
                    onPressed: () async {
                      await player.playPrevious();
                    },
                  ),
                  IconButton(
                    icon: FaIcon(
                      player.isPlaying
                          ? FontAwesomeIcons.pause
                          : FontAwesomeIcons.play,
                      size: 18,
                    ),
                    onPressed: () {
                      if (player.isPlaying) {
                        player.audioPlayer.pause();
                      } else {
                        player.audioPlayer.play();
                      }
                    },
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.forward, size: 18),
                    onPressed: () async {
                      await player.playNext();
                    },
                  ),
                  IconButton(
                    icon: FaIcon(
                      player.playMode == PlayMode.order
                          ? FontAwesomeIcons.repeat
                          : FontAwesomeIcons.shuffle,
                      size: 18,
                    ),
                    tooltip:
                        player.playMode == PlayMode.order ? '顺序播放' : '随机播放',
                    onPressed: () {
                      player.togglePlayMode();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerBarCover extends StatefulWidget {
  final String coverUrl;
  final VoidCallback onTap;
  const PlayerBarCover({
    super.key,
    required this.coverUrl,
    required this.onTap,
  });

  @override
  State<PlayerBarCover> createState() => _PlayerBarCoverState();
}

class _PlayerBarCoverState extends State<PlayerBarCover> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    final player = Provider.of<PlayerModel>(context, listen: false);
    final songId = player.currentSong?.id ?? 'unknown';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Hero(
              tag: 'song-cover-$songId',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: widget.coverUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  placeholder:
                      (context, url) => const SizedBox(width: 56, height: 56),
                  errorWidget:
                      (context, url, error) => const Icon(Icons.music_note),
                ),
              ),
            ),
            if (isHovered) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: Colors.black.withOpacity(0.08),
                  ),
                ),
              ),
              Center(
                child: FaIcon(
                  FontAwesomeIcons.angleUp,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先登录'),
            duration: Duration(seconds: 1), // 减少显示时间
          ),
        );
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
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('收藏到歌单'),
            content: SizedBox(
              width:
                  MediaQuery.of(dialogContext).size.width / 4, // 将宽度缩小到原来的1/4
              height:
                  MediaQuery.of(dialogContext).size.height / 2, // 将高度缩小到原来的1/2
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
                      Navigator.of(dialogContext).pop();

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
                          SnackBar(content: Text(success ? '收藏成功' : '收藏失败')),
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
