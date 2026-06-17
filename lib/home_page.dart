import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:context_menus/context_menus.dart';
import 'netease_api/netease_music_api.dart';
import 'player_model.dart';
import 'constants/image_request.dart';
import 'utils/daily_sample.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
      if (!mounted) return;
      if (result.code == 200 && result.data.dailySongs != null) {
        setState(() {
          _recommendSongs = result.data.dailySongs!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '获取推荐歌曲失败: ${result.code}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '获取推荐歌曲失败: $e';
        _isLoading = false;
      });
    }
  }

  void _playSong(Song2 song, int index) async {
    final player = Provider.of<PlayerModel>(context, listen: false);

    // 获取歌曲播放地址
    final urlWrap = await NeteaseMusicApi().songUrl([song.id]);
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
    final player = context.watch<PlayerModel>();
    final bottomPadding = player.currentSong != null ? 100.0 : 0.0;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSummary = constraints.maxWidth >= 1040;
          return Row(
            children: [
              Expanded(
                child: _RecommendationListView(
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  songs: _recommendSongs,
                  bottomPadding: bottomPadding,
                  currentSongId: player.currentSong?.id,
                  onRefresh: _fetchRecommendSongs,
                  onPlaySong: _playSong,
                ),
              ),
              if (showSummary)
                _DailySummaryPanel(
                  songs: _recommendSongs,
                  isLoading: _isLoading,
                  onPlayAll:
                      _recommendSongs.isEmpty
                          ? null
                          : () => _playSong(_recommendSongs.first, 0),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RecommendationListView extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final List<Song2> songs;
  final double bottomPadding;
  final String? currentSongId;
  final VoidCallback onRefresh;
  final void Function(Song2 song, int index) onPlaySong;

  const _RecommendationListView({
    required this.isLoading,
    required this.errorMessage,
    required this.songs,
    required this.bottomPadding,
    required this.currentSongId,
    required this.onRefresh,
    required this.onPlaySong,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          pinned: true,
          title: const Text('Verse'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: onRefresh,
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: _DailyHeader(
            songCount: songs.length,
            onPlayAll: songs.isEmpty ? null : () => onPlaySong(songs.first, 0),
          ),
        ),
        if (isLoading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (errorMessage != null)
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
                  Text(errorMessage!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: onRefresh,
                    child: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final song = songs[index];
              return _RecommendTrackListTile(
                song: song,
                index: index,
                isCurrent: song.id == currentSongId,
                onPlaySong: onPlaySong,
              );
            }, childCount: songs.length),
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottomPadding + 20)),
      ],
    );
  }
}

class _DailyHeader extends StatelessWidget {
  final int songCount;
  final VoidCallback? onPlayAll;

  const _DailyHeader({required this.songCount, required this.onPlayAll});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = DateTime.now().toString().substring(0, 10);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.calendar_today, color: colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每日推荐',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$date · $songCount 首',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onPlayAll,
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放全部'),
          ),
        ],
      ),
    );
  }
}

class _DailySummaryPanel extends StatelessWidget {
  final List<Song2> songs;
  final bool isLoading;
  final VoidCallback? onPlayAll;

  const _DailySummaryPanel({
    required this.songs,
    required this.isLoading,
    required this.onPlayAll,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final previewSongs = stableDailySample(
      songs,
      count: 4,
      date: DateTime.now(),
      keyOf: (song) => song.id,
    );

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.32),
        border: Border(
          left: BorderSide(color: colors.outline.withValues(alpha: 0.18)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日精选',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            DateTime.now().toString().substring(0, 10),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.58),
            ),
          ),
          const SizedBox(height: 22),
          AspectRatio(
            aspectRatio: 1,
            child:
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _CoverCollage(songs: previewSongs),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onPlayAll,
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放全部'),
          ),
          const SizedBox(height: 18),
          if (songs.isNotEmpty)
            Text(
              '${songs.length} 首歌曲',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.62),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverCollage extends StatelessWidget {
  final List<Song2> songs;

  const _CoverCollage({required this.songs});

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: Icon(Icons.music_note, size: 52)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          return _CoverThumb(url: normalizeImageUrl(songs[index].al?.picUrl));
        },
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final String? url;

  const _CoverThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null) return const ColoredBox(color: Colors.black12);
    return CachedNetworkImage(
      imageUrl: url!,
      httpHeaders: imageHeadersFor(url),
      fit: BoxFit.cover,
      placeholder: (_, __) => const ColoredBox(color: Colors.black12),
      errorWidget: (_, __, ___) => const Icon(Icons.music_note),
    );
  }
}

class _RecommendTrackListTile extends StatefulWidget {
  final Song2 song;
  final int index;
  final bool isCurrent;
  final Function(Song2, int) onPlaySong;

  const _RecommendTrackListTile({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.onPlaySong,
  });

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
    final cover = normalizeImageUrl(song.al?.picUrl);
    final colors = Theme.of(context).colorScheme;
    final duration = _formatDuration(song.dt);
    final rowColor =
        widget.isCurrent
            ? colors.primary.withValues(alpha: 0.13)
            : _isHovered
            ? colors.onSurface.withValues(alpha: 0.07)
            : Colors.transparent;

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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 68,
            decoration: BoxDecoration(
              color: rowColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child:
                            widget.isCurrent
                                ? Icon(
                                  Icons.graphic_eq,
                                  color: colors.primary,
                                  size: 20,
                                )
                                : Text(
                                  '${widget.index + 1}'.padLeft(2, '0'),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurface.withValues(
                                      alpha: 0.46,
                                    ),
                                  ),
                                ),
                      ),
                      const SizedBox(width: 8),
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
                          : const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.music_note),
                          ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.name ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.titleMedium?.copyWith(
                                fontWeight:
                                    widget.isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              artists,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color: colors.onSurface.withValues(alpha: 0.62),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (duration != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          duration,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.52),
                          ),
                        ),
                      ],
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child:
                            _isLoading
                                ? const Padding(
                                  padding: EdgeInsets.all(5),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : Icon(
                                  Icons.play_arrow,
                                  color:
                                      _isHovered || widget.isCurrent
                                          ? colors.primary
                                          : colors.onSurface.withValues(
                                            alpha: 0.42,
                                          ),
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _formatDuration(int? milliseconds) {
  if (milliseconds == null || milliseconds <= 0) return null;
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
