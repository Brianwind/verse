import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'download_model.dart';
import 'netease_api/netease_music_api.dart';

void queueSongDownload(BuildContext context, Song2 song) {
  unawaited(context.read<DownloadModel>().downloadSong(song));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('已加入下载队列: ${song.name ?? '未知歌曲'}'),
      duration: const Duration(seconds: 1),
    ),
  );
}

void queueSongsDownload(
  BuildContext context,
  List<Song2> songs, {
  String? sourceName,
}) {
  if (songs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('没有可下载的歌曲'), duration: Duration(seconds: 1)),
    );
    return;
  }

  unawaited(
    context.read<DownloadModel>().downloadSongs(songs, sourceName: sourceName),
  );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('已加入下载队列: ${songs.length} 首'),
      duration: const Duration(seconds: 1),
    ),
  );
}
