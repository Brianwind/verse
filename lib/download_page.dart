import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'constants/image_request.dart';
import 'download_model.dart';

class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final download = context.watch<DownloadModel>();
    final tasks = download.tasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载'),
        actions: [
          if (tasks.any(
            (task) =>
                task.state == DownloadTaskState.succeeded ||
                task.state == DownloadTaskState.skipped ||
                task.state == DownloadTaskState.canceled,
          ))
            TextButton.icon(
              onPressed: download.clearCompletedTasks,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('清除已完成'),
            ),
        ],
      ),
      body:
          tasks.isEmpty
              ? const _EmptyDownloadState()
              : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                children: [
                  if (download.currentTask != null) ...[
                    _CurrentDownloadCard(task: download.currentTask!),
                    const SizedBox(height: 18),
                  ],
                  _DownloadSummary(model: download),
                  const SizedBox(height: 12),
                  ...tasks.map((task) => _DownloadTaskTile(task: task)),
                ],
              ),
    );
  }
}

class _EmptyDownloadState extends StatelessWidget {
  const _EmptyDownloadState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.download_for_offline_outlined,
            size: 56,
            color: colors.onSurface.withValues(alpha: 0.32),
          ),
          const SizedBox(height: 12),
          Text(
            '暂无下载任务',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '从歌曲右键菜单、播放栏或歌单详情页添加下载',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.52),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentDownloadCard extends StatelessWidget {
  const _CurrentDownloadCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final song = task.song;
    final colors = Theme.of(context).colorScheme;
    final artists = song.ar?.map((artist) => artist.name).join(', ') ?? '';
    final album = song.al?.name ?? '';
    final coverUrl = normalizeImageUrl(song.al?.picUrl);
    final progress = task.progress;
    final percent = progress == null ? null : '${(progress * 100).round()}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(8),
        color: colors.surface.withValues(alpha: 0.62),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '当前任务',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                percent ?? task.stageLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _CoverThumb(url: coverUrl, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.name ?? '未知歌曲',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        artists,
                        album,
                      ].where((item) => item.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DefaultTextStyle(
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: colors.onSurface.withValues(alpha: 0.62),
            ),
            child: Row(
              children: [
                Text(_formatBytesProgress(task)),
                const Spacer(),
                Text(_formatSpeed(task.bytesPerSecond)),
                const SizedBox(width: 18),
                Text(_formatEta(task.estimatedRemaining)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadSummary extends StatelessWidget {
  const _DownloadSummary({required this.model});

  final DownloadModel model;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          '队列',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 10),
        Text(
          '${model.completedCount}/${model.totalCount} 已处理',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.56),
          ),
        ),
        const Spacer(),
        if (model.failedCount > 0)
          Text(
            '失败 ${model.failedCount}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final song = task.song;
    final artists = song.ar?.map((artist) => artist.name).join(', ') ?? '';
    final progress = task.progress;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: _CoverThumb(
            url: normalizeImageUrl(song.al?.picUrl),
            size: 42,
          ),
          title: Text(
            song.name ?? '未知歌曲',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(artists, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(999),
                      color:
                          task.state == DownloadTaskState.failed
                              ? colors.error
                              : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    progress == null
                        ? task.stageLabel
                        : '${(progress * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
              if (task.errorMessage != null) ...[
                const SizedBox(height: 4),
                Text(
                  task.errorMessage!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.error),
                ),
              ],
            ],
          ),
          trailing: _TaskActions(task: task),
        ),
      ),
    );
  }
}

class _TaskActions extends StatelessWidget {
  const _TaskActions({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final model = context.read<DownloadModel>();
    if (task.canRetry) {
      return IconButton(
        tooltip: '重试',
        icon: const Icon(Icons.refresh),
        onPressed: () => model.retryTask(task.id),
      );
    }
    if (task.canCancel) {
      return IconButton(
        tooltip: '取消',
        icon: const Icon(Icons.close),
        onPressed: () => model.cancelTask(task.id),
      );
    }
    return Text(
      task.stageLabel,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.56),
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox(
      width: size,
      height: size,
      child: const Icon(Icons.music_note),
    );
    if (url == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url!,
        httpHeaders: imageHeadersFor(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => SizedBox(width: size, height: size),
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}

String _formatBytesProgress(DownloadTask task) {
  final total = task.totalBytes;
  if (total == null || total <= 0) return _formatBytes(task.receivedBytes);
  return '${_formatBytes(task.receivedBytes)} / ${_formatBytes(total)}';
}

String _formatSpeed(int? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond <= 0) return '- B/s';
  return '${_formatBytes(bytesPerSecond)}/s';
}

String _formatEta(Duration? duration) {
  if (duration == null || duration.isNegative) return '剩余 --:--';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '剩余 ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 100 ? 0 : 1)} GB';
}
