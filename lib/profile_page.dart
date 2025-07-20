import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:context_menus/context_menus.dart';

import 'player_model.dart';
import 'netease_api/src/netease_api.dart';
import 'netease_api/src/api/play/bean.dart';
import 'main.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  List<Play>? _playlists;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPlaylists();
  }

  Future<void> _fetchPlaylists() async {
    final profile = NeteaseMusicApi().usc.accountInfo?.profile;
    if (profile == null) {
      setState(() {
        _loading = false;
        _error = '未登录';
      });
      return;
    }
    try {
      final res = await NeteaseMusicApi().userPlayList(
        profile.userId.toString(),
      );
      setState(() {
        _playlists = res.playlist;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载歌单失败: $e';
        _playlists = null;
        _loading = false;
      });
    }
  }

  void _openPlaylistDetail(BuildContext context, Play playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PlaylistDetailPage(
              playlistId: playlist.id.toString(),
              playlistName: playlist.name ?? '',
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = NeteaseMusicApi().usc.accountInfo?.profile;
    Play? likedPlaylist;
    List<Play> otherPlaylists = [];
    if (_playlists != null && profile != null) {
      for (final pl in _playlists!) {
        if (pl.name == '${profile.nickname}喜欢的音乐') {
          likedPlaylist = pl;
        } else {
          otherPlaylists.add(pl);
        }
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : _playlists == null || _playlists!.isEmpty
              ? const Center(child: Text('暂无歌单'))
              : ListView(
                children: [
                  if (likedPlaylist != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      child: Text(
                        '喜欢的音乐',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _openPlaylistDetail(context, likedPlaylist!),
                      child: ListTile(
                        leading:
                            likedPlaylist.coverImgUrl != null
                                ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CachedNetworkImage(
                                    imageUrl: likedPlaylist.coverImgUrl!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    placeholder:
                                        (context, url) => const SizedBox(
                                          width: 48,
                                          height: 48,
                                        ),
                                    errorWidget:
                                        (context, url, error) =>
                                            const Icon(Icons.broken_image),
                                  ),
                                )
                                : const Icon(Icons.favorite, color: Colors.red),
                        title: Text(likedPlaylist.name ?? '我喜欢的音乐'),
                        subtitle: Text('共${likedPlaylist.trackCount ?? 0}首'),
                      ),
                    ),
                  ],
                  if (otherPlaylists.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      child: Text(
                        '我的歌单',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...otherPlaylists.map(
                      (pl) => StatefulBuilder(
                        builder: (context, setState) {
                          bool isHovered = false;
                          return MouseRegion(
                            onEnter: (_) => setState(() => isHovered = true),
                            onExit: (_) => setState(() => isHovered = false),
                            child: InkWell(
                              onTap: () => _openPlaylistDetail(context, pl),
                              child: Container(
                                color:
                                    isHovered
                                        ? Theme.of(context).hoverColor
                                        : null,
                                child: ListTile(
                                  leading:
                                      pl.coverImgUrl != null
                                          ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: pl.coverImgUrl!,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                              placeholder:
                                                  (context, url) =>
                                                      const SizedBox(
                                                        width: 48,
                                                        height: 48,
                                                      ),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const Icon(
                                                        Icons.broken_image,
                                                      ),
                                            ),
                                          )
                                          : const Icon(Icons.queue_music),
                                  title: Text(pl.name ?? '无名歌单'),
                                  subtitle: Text('共${pl.trackCount ?? 0}首'),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
    );
  }
}

class PlaylistDetailPage extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  const PlaylistDetailPage({
    super.key,
    required this.playlistId,
    required this.playlistName,
  });

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  Play? _playlist;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPlaylistDetail();
  }

  Future<void> _fetchPlaylistDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await NeteaseMusicApi().playListDetail(widget.playlistId);
      setState(() {
        _playlist = res.playlist;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载歌单详情失败: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(88),
        child: Column(
          children: [
            // 顶部窗口拖动区和窗口按钮，统一样式
            Material(
              child: Container(
                height: 32,
                child: Row(
                  children: [
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
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    CustomWindowButtons(),
                  ],
                ),
              ),
            ),
            // AppBar单独显示
            AppBar(
              title: Text(widget.playlistName),
              leading: IconButton(
                tooltip: '',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              toolbarHeight: 56,
            ),
          ],
        ),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : _playlist == null ||
                  _playlist!.tracks == null ||
                  _playlist!.tracks!.isEmpty
              ? const Center(child: Text('歌单暂无歌曲'))
              : ListView.builder(
                itemCount: _playlist!.tracks!.length,
                itemBuilder: (context, idx) {
                  final playTrack = _playlist!.tracks![idx];
                  return _TrackListTile(
                    playTrack: playTrack,
                    playlist: _playlist!,
                  );
                },
              ),
      bottomNavigationBar: const PlayerBar(),
    );
  }
}

class _TrackListTile extends StatefulWidget {
  final dynamic playTrack;
  final dynamic playlist;
  const _TrackListTile({
    Key? key,
    required this.playTrack,
    required this.playlist,
  }) : super(key: key);

  @override
  State<_TrackListTile> createState() => _TrackListTileState();
}

class _TrackListTileState extends State<_TrackListTile> {
  bool _isLoading = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ContextMenuRegion(
        // 定义右键菜单
        contextMenu: GenericContextMenu(
          buttonConfigs: [
            ContextMenuButtonConfig(
              "从歌单移除歌曲",
              onPressed: () => _removeSongFromPlaylist(context),
            ),
          ],
        ),
        child: Container(
          color: _isHovered ? Theme.of(context).hoverColor : null,
          child: ListTile(
            mouseCursor: SystemMouseCursors.basic,
            leading:
                widget.playTrack.al.picUrl != null
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: widget.playTrack.al.picUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) =>
                                const SizedBox(width: 48, height: 48),
                        errorWidget:
                            (context, url, error) =>
                                const Icon(Icons.music_note),
                      ),
                    )
                    : const Icon(Icons.music_note),
            title: Text(widget.playTrack.name ?? '未知歌曲'),
            subtitle: Text(
              widget.playTrack.ar?.map((a) => a.name).join(', ') ?? '',
            ),
            enabled: !_isLoading,
            onTap:
                _isLoading
                    ? null
                    : () async {
                      setState(() => _isLoading = true);
                      try {
                        // 歌曲详情加超时
                        final detailWrap = await NeteaseMusicApi()
                            .songDetail([widget.playTrack.id])
                            .timeout(const Duration(seconds: 8));
                        final song2 =
                            detailWrap.songs?.isNotEmpty == true
                                ? detailWrap.songs![0]
                                : null;
                        if (song2 == null) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('无法获取歌曲详情'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                          return;
                        }
                        // 歌曲URL加超时
                        final urlWrap = await NeteaseMusicApi()
                            .songUrl([widget.playTrack.id])
                            .timeout(const Duration(seconds: 8));
                        final url =
                            urlWrap.data?.isNotEmpty == true
                                ? urlWrap.data![0].url
                                : null;
                        if (url == null || url.isEmpty) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('无法播放该歌曲'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                          return;
                        }
                        if (context.mounted) {
                          final player = Provider.of<PlayerModel>(
                            context,
                            listen: false,
                          );
                          // 正确转换: 创建类型安全的 List<Song2>
                          final List<Song2> tracks = [];
                          if (widget.playlist.tracks != null) {
                            for (final t in widget.playlist.tracks!) {
                              final song =
                                  Song2()
                                    ..id = t.id
                                    ..name = t.name
                                    ..ar = t.ar
                                    ..al = t.al
                                    ..dt = t.dt;
                              tracks.add(song);
                            }
                          }
                          final startIndex = tracks.indexWhere(
                            (s) => s.id == widget.playTrack.id,
                          );
                          await player.playPlaylist(
                            playlistId: widget.playlist.id,
                            tracks: tracks,
                            startIndex: startIndex,
                            url: url,
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('加载或播放超时/失败: ${e.toString()}'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
          ),
        ),
      ),
    );
  }

  // 从歌单中删除歌曲的方法
  Future<void> _removeSongFromPlaylist(BuildContext context) async {
    final playlistId = widget.playlist.id.toString();
    final songId = widget.playTrack.id.toString();

    // 显示确认对话框
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('确认'),
                content: Text('确定要从歌单中移除歌曲"${widget.playTrack.name}"吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('确定'),
                  ),
                ],
              ),
        ) ??
        false;

    if (!confirmed || !context.mounted) return;

    // 显示加载指示器
    setState(() => _isLoading = true);

    try {
      final player = Provider.of<PlayerModel>(context, listen: false);
      final success = await player.removeSongFromPlaylist(songId, playlistId);

      if (!context.mounted) return;

      if (success) {
        // 提示成功
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已从歌单移除歌曲'),
            duration: Duration(seconds: 1),
          ),
        );

        // 刷新歌单详情
        final playlistDetailState =
            context.findAncestorStateOfType<_PlaylistDetailPageState>();
        if (playlistDetailState != null) {
          playlistDetailState._fetchPlaylistDetail();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('移除歌曲失败'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('移除歌曲异常: $e'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
