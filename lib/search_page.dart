import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:context_menus/context_menus.dart';
import 'netease_api/netease_music_api.dart';
import 'player_model.dart';
import 'constants/image_request.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  List<Song2> _searchResults = [];
  String? _errorMessage;
  String _currentKeyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final keyword = _searchController.text.trim();

    if (keyword.isEmpty) {
      setState(() {
        _searchResults = [];
        _errorMessage = null;
        _currentKeyword = '';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentKeyword = keyword;
    });

    try {
      // 使用网易云API搜索歌曲
      final searchResult = await NeteaseMusicApi().searchSong(
        keyword,
        limit: 50,
        cloudSearch: false,
      );
      if (searchResult.code == 200 && searchResult.result.songs.isNotEmpty) {
        // 获取歌曲ID列表
        final songIds = searchResult.result.songs.map((s) => s.id).toList();

        // 调用 songDetail API 获取完整的歌曲信息（包括封面）
        final detailResult = await NeteaseMusicApi().songDetail(songIds);

        if (detailResult.code == 200 && detailResult.songs != null) {
          setState(() {
            _searchResults = detailResult.songs!;
            _isLoading = false;
          });
        } else {
          setState(() {
            _searchResults = [];
            _errorMessage = '获取歌曲详情失败: ${detailResult.code}';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _searchResults = [];
          _errorMessage =
              searchResult.code == 200
                  ? '没有找到相关歌曲'
                  : '搜索失败: ${searchResult.code}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _errorMessage = '搜索失败: $e';
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
        playlistId: 'search_$_currentKeyword',
        tracks: _searchResults,
        startIndex: index,
        url: url,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final bottomPadding = player.currentSong != null ? 100.0 : 0.0;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(floating: true, pinned: true, title: const Text('搜索音乐')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索歌曲、歌手...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon:
                      _searchController.text.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                                _errorMessage = null;
                                _currentKeyword = '';
                              });
                            },
                          )
                          : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                onSubmitted: (_) => _performSearch(),
                onChanged: (_) => setState(() {}),
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
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_searchResults.isEmpty && _currentKeyword.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_note,
                      size: 64,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '搜索你喜欢的音乐',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  '找到 ${_searchResults.length} 首歌曲',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
            ),
          if (_searchResults.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final song = _searchResults[index];
                return _SearchResultListTile(
                  song: song,
                  index: index,
                  onPlaySong: _playSong,
                );
              }, childCount: _searchResults.length),
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
        ],
      ),
    );
  }
}

class _SearchResultListTile extends StatefulWidget {
  final Song2 song;
  final int index;
  final Function(Song2, int) onPlaySong;

  const _SearchResultListTile({
    Key? key,
    required this.song,
    required this.index,
    required this.onPlaySong,
  }) : super(key: key);

  @override
  State<_SearchResultListTile> createState() => _SearchResultListTileState();
}

class _SearchResultListTileState extends State<_SearchResultListTile> {
  bool _isLoading = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final artists = song.ar?.map((a) => a.name).join(', ') ?? '';
    final cover = normalizeImageUrl(song.al?.picUrl);
    final albumName = song.al?.name ?? '';

    // 计算歌曲时长
    String duration = '';
    if (song.dt != null) {
      final totalSeconds = song.dt! ~/ 1000;
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      duration = '$minutes:${seconds.toString().padLeft(2, '0')}';
    }

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
                        httpHeaders: imageHeadersFor(cover),
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
              '$artists · $albumName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing:
                duration.isNotEmpty
                    ? Text(
                      duration,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    )
                    : null,
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
