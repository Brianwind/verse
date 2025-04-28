import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
                final artists = song.ar?.map((a) => a.name).join(', ') ?? '';
                final cover = song.al?.picUrl;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Card(
                    elevation: 2,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            cover != null
                                ? CachedNetworkImage(
                                  imageUrl: cover,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  placeholder:
                                      (context, url) => Container(
                                        width: 56,
                                        height: 56,
                                        color: Colors.grey.shade300,
                                      ),
                                  errorWidget:
                                      (context, url, error) => const Icon(
                                        Icons.music_note,
                                        size: 32,
                                      ),
                                )
                                : Container(
                                  width: 56,
                                  height: 56,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.music_note, size: 32),
                                ),
                      ),
                      title: Text(
                        song.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _playSong(song, index),
                      ),
                      onTap: () => _playSong(song, index),
                    ),
                  ),
                );
              }, childCount: _recommendSongs.length),
            ),
        ],
      ),
    );
  }
}
