import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:context_menus/context_menus.dart';
import 'netease_api/netease_music_api.dart';
import 'player_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = false;
  List<Song2> _recommendSongs = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRecommendSongs();
  }

  Future<void> _fetchRecommendSongs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 使用网易云API获取每日推荐歌曲
      final result = await NeteaseMusicApi().recommendSongList();
      if (result.code == 200 && result.data?.dailySongs != null) {
        setState(() {
          _recommendSongs = result.data!.dailySongs!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '获取推荐歌曲失败: ${result.code}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '获取推荐歌曲失败: $e';
        _isLoading = false;
      });
    }
  }

  void _playSong(Song2 song, int index) async {
    final player = Provider.of<PlayerModel>(context, listen: false);

    // 获取歌曲播放地址
    final urlWrap = await NeteaseMusicApi().songUrl([song.id!]);
    if (urlWrap.data?.isNotEmpty == true && urlWrap.data![0].url != null) {
      String url = urlWrap.data![0].url!;

      // 创建播放列表并播放歌曲
      await player.playPlaylist(
        playlistId: 'recommend_daily',
        tracks: _recommendSongs,
        startIndex: index,
        url: url,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            title: const Text('Verse'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _fetchRecommendSongs,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '每日推荐',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    DateTime.now().toString().substring(0, 10),
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    Text(_errorMessage!),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchRecommendSongs,
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final song = _recommendSongs[index];
                return _RecommendTrackListTile(
                  song: song,
                  index: index,
                  onPlaySong: _playSong,
                );
              }, childCount: _recommendSongs.length),
            ),
        ],
      ),
    );
  }
}

class _RecommendTrackListTile extends StatefulWidget {
  final Song2 song;
  final int index;
  final Function(Song2, int) onPlaySong;

  const _RecommendTrackListTile({
    Key? key,
    required this.song,
    required this.index,
    required this.onPlaySong,
  }) : super(key: key);

  @override
  State<_RecommendTrackListTile> createState() =>
      _RecommendTrackListTileState();
}

class _RecommendTrackListTileState extends State<_RecommendTrackListTile> {
  bool _isLoading = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final artists = song.ar?.map((a) => a.name).join(', ') ?? '';
    final cover = song.al?.picUrl;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ContextMenuRegion(
        // 定义右键菜单
        contextMenu: GenericContextMenu(
          buttonConfigs: [
            ContextMenuButtonConfig(
              "播放这首歌",
              onPressed: () => widget.onPlaySong(song, widget.index),
            ),
          ],
        ),
        child: Container(
          color: _isHovered ? Theme.of(context).hoverColor : null,
          child: ListTile(
            mouseCursor: SystemMouseCursors.basic,
            leading:
                cover != null
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: cover,
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
            title: Text(
              song.name ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              artists,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            enabled: !_isLoading,
            onTap:
                _isLoading
                    ? null
                    : () async {
                      setState(() => _isLoading = true);
                      try {
                        await widget.onPlaySong(song, widget.index);
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
          ),
        ),
      ),
    );
  }
}
