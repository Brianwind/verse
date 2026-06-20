import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'constants/image_request.dart';
import 'netease_api/netease_music_api.dart';
import 'utils/download_paths.dart';
import 'utils/id3v23_writer.dart';

typedef DownloadProgressCallback =
    void Function(int receivedBytes, int totalBytes);

typedef DownloadUrlResolver = Future<String?> Function(Song2 song);

typedef DownloadExecutor =
    Future<void> Function({
      required String url,
      required String savePath,
      DownloadProgressCallback? onProgress,
      CancelToken? cancelToken,
    });

typedef DownloadMetadataWriter =
    Future<void> Function({
      required Song2 song,
      required String tempPath,
      required String savePath,
    });

typedef DownloadFileExists = Future<bool> Function(String path);
typedef DownloadDirectoryEnsurer = Future<void> Function(String path);
typedef DownloadSettingsLoader = Future<String?> Function();
typedef DownloadSettingsSaver = Future<void> Function(String path);
typedef DownloadDefaultDirectoryResolver = Future<String> Function();
typedef DownloadClock = DateTime Function();
typedef DownloadLyricsResolver = Future<String?> Function(Song2 song);

enum DownloadQueueStatus { idle, running, completed }

enum DownloadTaskState {
  queued,
  downloading,
  writingMetadata,
  succeeded,
  failed,
  skipped,
  canceled,
}

class DownloadTask {
  DownloadTask({required this.id, required this.song, required this.fileName});

  final String id;
  final Song2 song;
  final String fileName;
  DownloadTaskState state = DownloadTaskState.queued;
  int receivedBytes = 0;
  int? totalBytes;
  int? bytesPerSecond;
  Duration? estimatedRemaining;
  DateTime? startedAt;
  DateTime? completedAt;
  String? savePath;
  String? tempPath;
  String? errorMessage;
  CancelToken? _cancelToken;

  bool get canCancel =>
      state == DownloadTaskState.queued ||
      state == DownloadTaskState.downloading;

  bool get canRetry => state == DownloadTaskState.failed;

  String get stageLabel {
    switch (state) {
      case DownloadTaskState.queued:
        return '排队中';
      case DownloadTaskState.downloading:
        return '下载中';
      case DownloadTaskState.writingMetadata:
        return '写入 metadata';
      case DownloadTaskState.succeeded:
        return '完成';
      case DownloadTaskState.failed:
        return '失败';
      case DownloadTaskState.skipped:
        return '已跳过';
      case DownloadTaskState.canceled:
        return '已取消';
    }
  }

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1).toDouble();
  }

  bool get isTerminal =>
      state == DownloadTaskState.succeeded ||
      state == DownloadTaskState.failed ||
      state == DownloadTaskState.skipped ||
      state == DownloadTaskState.canceled;

  void resetForRetry() {
    state = DownloadTaskState.queued;
    receivedBytes = 0;
    totalBytes = null;
    bytesPerSecond = null;
    estimatedRemaining = null;
    startedAt = null;
    completedAt = null;
    errorMessage = null;
    _cancelToken = null;
  }
}

class DownloadModel extends ChangeNotifier {
  static const int targetBitrate = 320000;
  static const String _settingsFileName = 'verse_settings.json';
  static const String _downloadDirectoryKey = 'downloadDirectory';

  final Queue<DownloadTask> _queue = Queue<DownloadTask>();
  final List<DownloadTask> _tasks = [];
  final Dio _dio;
  final DownloadUrlResolver? _injectedUrlResolver;
  final DownloadExecutor? _injectedDownloadExecutor;
  final DownloadMetadataWriter? _injectedMetadataWriter;
  final DownloadFileExists? _injectedFileExists;
  final DownloadDirectoryEnsurer? _injectedEnsureDirectory;
  final DownloadSettingsLoader? _injectedSettingsLoader;
  final DownloadSettingsSaver? _injectedSettingsSaver;
  final DownloadDefaultDirectoryResolver? _injectedDefaultDirectoryResolver;
  final DownloadLyricsResolver? _injectedLyricsResolver;
  final DownloadClock? _clock;
  final Id3v23Writer _id3Writer = Id3v23Writer();

  String _downloadDirectory;
  DownloadQueueStatus _status = DownloadQueueStatus.idle;
  DownloadTask? _currentTask;
  bool _processing = false;
  bool _initialized = false;
  Completer<void>? _idleCompleter;
  String? _sourceName;
  String? _lastErrorMessage;
  int _nextTaskId = 0;

  DownloadModel({
    String? initialDownloadDirectory,
    Dio? dio,
    DownloadUrlResolver? urlResolver,
    DownloadExecutor? downloadExecutor,
    DownloadMetadataWriter? metadataWriter,
    DownloadFileExists? fileExists,
    DownloadDirectoryEnsurer? ensureDirectory,
    DownloadSettingsLoader? settingsLoader,
    DownloadSettingsSaver? settingsSaver,
    DownloadDefaultDirectoryResolver? defaultDirectoryResolver,
    DownloadLyricsResolver? lyricsResolver,
    DownloadClock? clock,
  }) : _downloadDirectory =
           initialDownloadDirectory ?? _initialDownloadDirectory(),
       _dio = dio ?? Dio(),
       _injectedUrlResolver = urlResolver,
       _injectedDownloadExecutor = downloadExecutor,
       _injectedMetadataWriter = metadataWriter,
       _injectedFileExists = fileExists,
       _injectedEnsureDirectory = ensureDirectory,
       _injectedSettingsLoader = settingsLoader,
       _injectedSettingsSaver = settingsSaver,
       _injectedDefaultDirectoryResolver = defaultDirectoryResolver,
       _injectedLyricsResolver = lyricsResolver,
       _clock = clock ?? DateTime.now;

  String get downloadDirectory => _downloadDirectory;
  DownloadQueueStatus get status => _status;
  DownloadTask? get currentTask => _currentTask;
  List<DownloadTask> get tasks => UnmodifiableListView(_tasks);
  bool get isInitialized => _initialized;
  bool get isRunning => _processing;
  int get totalCount => _tasks.length;
  int get succeededCount =>
      _tasks.where((task) => task.state == DownloadTaskState.succeeded).length;
  int get failedCount =>
      _tasks.where((task) => task.state == DownloadTaskState.failed).length;
  int get skippedCount =>
      _tasks.where((task) => task.state == DownloadTaskState.skipped).length;
  int get canceledCount =>
      _tasks.where((task) => task.state == DownloadTaskState.canceled).length;
  int get completedCount => _tasks.where((task) => task.isTerminal).length;
  int get pendingCount =>
      _tasks.where((task) => task.state == DownloadTaskState.queued).length;
  String? get sourceName => _sourceName;
  String? get lastErrorMessage => _lastErrorMessage;

  Future<void> init() async {
    if (_initialized) return;

    final savedDirectory = await _loadDownloadDirectory();
    if (savedDirectory != null && savedDirectory.trim().isNotEmpty) {
      _downloadDirectory = savedDirectory.trim();
    } else {
      _downloadDirectory = await _resolveDefaultDirectory();
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setDownloadDirectory(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Download directory cannot be empty');
    }

    _downloadDirectory = trimmed;
    await _saveDownloadDirectory(trimmed);
    notifyListeners();
  }

  Future<void> resetDownloadDirectory() async {
    final directory = await _resolveDefaultDirectory();
    await setDownloadDirectory(directory);
  }

  Future<void> downloadSong(Song2 song) {
    return downloadSongs([song]);
  }

  Future<void> downloadSongs(List<Song2> songs, {String? sourceName}) async {
    final tasks =
        songs
            .where((song) => song.id.trim().isNotEmpty)
            .map(
              (song) => DownloadTask(
                id: 'download-${++_nextTaskId}',
                song: song,
                fileName: buildMp3DownloadFileName(
                  songName: song.name,
                  artistNames:
                      song.ar?.map((artist) => artist.name) ?? const [],
                ),
              ),
            )
            .toList();

    if (tasks.isEmpty) return;

    _sourceName = sourceName;
    _tasks.addAll(tasks);
    _queue.addAll(tasks);
    _status = DownloadQueueStatus.running;
    _idleCompleter ??= Completer<void>();
    notifyListeners();

    _startProcessing();
  }

  Future<void> cancelTask(String taskId) async {
    final task = _findTask(taskId);
    if (task == null || !task.canCancel) return;

    if (task.state == DownloadTaskState.queued) {
      _queue.remove(task);
      task.state = DownloadTaskState.canceled;
      task.completedAt = _now();
      _tasks.remove(task);
      _refreshStatus();
      notifyListeners();
      _completeIdleIfNeeded();
      return;
    }

    task.state = DownloadTaskState.canceled;
    _tasks.remove(task);
    task._cancelToken?.cancel('用户取消下载');
    _refreshStatus();
    notifyListeners();
  }

  Future<void> retryTask(String taskId) async {
    final task = _findTask(taskId);
    if (task == null || !task.canRetry) return;

    task.resetForRetry();
    _queue.add(task);
    _status = DownloadQueueStatus.running;
    _idleCompleter ??= Completer<void>();
    notifyListeners();
    _startProcessing();
  }

  void clearCompletedTasks() {
    _tasks.removeWhere(
      (task) =>
          task.state == DownloadTaskState.succeeded ||
          task.state == DownloadTaskState.skipped ||
          task.state == DownloadTaskState.canceled,
    );
    _refreshStatus();
    notifyListeners();
  }

  Future<void> waitForIdle() {
    if (!_processing && _queue.isEmpty) return Future.value();
    return (_idleCompleter ??= Completer<void>()).future;
  }

  DownloadTask? _findTask(String taskId) {
    for (final task in _tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  void _startProcessing() {
    if (_processing) return;
    _processing = true;
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeFirst();
        if (task.state == DownloadTaskState.canceled) continue;

        _currentTask = task;
        task.state = DownloadTaskState.downloading;
        task.savePath = joinDownloadPath(_downloadDirectory, task.fileName);
        task.tempPath = '${task.savePath}.download';
        task.startedAt = _now();
        task.completedAt = null;
        task.errorMessage = null;
        task.receivedBytes = 0;
        task.totalBytes = null;
        task.bytesPerSecond = null;
        task.estimatedRemaining = null;
        task._cancelToken = CancelToken();
        notifyListeners();

        try {
          await _ensureDirectory(_downloadDirectory);

          if (await _fileExists(task.savePath!)) {
            task.state = DownloadTaskState.skipped;
            task.completedAt = _now();
            notifyListeners();
            continue;
          }

          final url = await _resolveSongUrl(task.song);
          _throwIfCanceled(task);
          if (url == null || url.trim().isEmpty) {
            throw StateError('无法获取下载地址');
          }

          await _downloadFile(
            url: url,
            savePath: task.tempPath!,
            cancelToken: task._cancelToken,
            onProgress: (received, total) {
              _updateProgress(task, received, total);
              notifyListeners();
            },
          );
          _throwIfCanceled(task);

          task.state = DownloadTaskState.writingMetadata;
          notifyListeners();

          await _writeMetadata(
            song: task.song,
            tempPath: task.tempPath!,
            savePath: task.savePath!,
          );
          _throwIfCanceled(task);

          await _deleteFileIfExists(task.tempPath);
          task.state = DownloadTaskState.succeeded;
          task.completedAt = _now();
          notifyListeners();
        } catch (e) {
          await _deleteFileIfExists(task.tempPath);
          if (task.state == DownloadTaskState.canceled || _isCancelError(e)) {
            task.state = DownloadTaskState.canceled;
            task.completedAt = _now();
          } else {
            if (task.state == DownloadTaskState.writingMetadata) {
              await _deleteFileIfExists(task.savePath);
            }
            task.state = DownloadTaskState.failed;
            task.errorMessage = e.toString();
            task.completedAt = _now();
            _lastErrorMessage = task.errorMessage;
          }
          notifyListeners();
        } finally {
          task._cancelToken = null;
          if (_currentTask == task) _currentTask = null;
        }
      }
    } finally {
      _processing = false;
      _refreshStatus();
      _completeIdleIfNeeded();
      notifyListeners();
    }
  }

  void _throwIfCanceled(DownloadTask task) {
    if (task.state == DownloadTaskState.canceled) {
      throw DioException(
        requestOptions: RequestOptions(path: task.savePath ?? ''),
        type: DioExceptionType.cancel,
      );
    }
  }

  bool _isCancelError(Object error) {
    return error is DioException && error.type == DioExceptionType.cancel;
  }

  void _updateProgress(DownloadTask task, int received, int total) {
    task.receivedBytes = received;
    task.totalBytes = total > 0 ? total : null;

    final startedAt = task.startedAt;
    if (startedAt == null || received <= 0) {
      task.bytesPerSecond = null;
      task.estimatedRemaining = null;
      return;
    }

    final elapsedMs = _now().difference(startedAt).inMilliseconds;
    if (elapsedMs <= 0) {
      task.bytesPerSecond = null;
      task.estimatedRemaining = null;
      return;
    }

    final bytesPerSecond = (received * 1000 / elapsedMs).round();
    task.bytesPerSecond = bytesPerSecond > 0 ? bytesPerSecond : null;

    final totalBytes = task.totalBytes;
    if (totalBytes == null || bytesPerSecond <= 0 || received >= totalBytes) {
      task.estimatedRemaining = null;
      return;
    }

    final remainingBytes = totalBytes - received;
    task.estimatedRemaining = Duration(
      milliseconds: (remainingBytes * 1000 / bytesPerSecond).round(),
    );
  }

  DateTime _now() {
    // Existing DownloadModel instances survive Flutter hot reload. If this
    // field was added after the instance was created, it can be null.
    return (_clock ?? DateTime.now)();
  }

  void _refreshStatus() {
    if (_processing || _queue.isNotEmpty) {
      _status = DownloadQueueStatus.running;
    } else if (_tasks.isEmpty) {
      _status = DownloadQueueStatus.idle;
    } else {
      _status = DownloadQueueStatus.completed;
    }
  }

  void _completeIdleIfNeeded() {
    if (_processing || _queue.isNotEmpty) return;
    final completer = _idleCompleter;
    _idleCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<String?> _resolveSongUrl(Song2 song) {
    final resolver = _injectedUrlResolver;
    if (resolver != null) return resolver(song);
    return _resolveSongUrlFromApi(song);
  }

  Future<String?> _resolveSongUrlFromApi(Song2 song) async {
    final result = await NeteaseMusicApi()
        .songUrl([song.id], br: targetBitrate)
        .timeout(const Duration(seconds: 12));
    if (result.data == null || result.data!.isEmpty) return null;
    return result.data!.first.url;
  }

  Future<void> _downloadFile({
    required String url,
    required String savePath,
    DownloadProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) {
    final executor = _injectedDownloadExecutor;
    if (executor != null) {
      return executor(
        url: url,
        savePath: savePath,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    return _downloadFileWithDio(
      url: url,
      savePath: savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<void> _downloadFileWithDio({
    required String url,
    required String savePath,
    DownloadProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) {
    return _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      deleteOnError: true,
      options: Options(
        followRedirects: true,
        headers: const {
          'Referer': 'https://music.163.com/',
          'Origin': 'https://music.163.com',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        },
      ),
      onReceiveProgress: (received, total) {
        onProgress?.call(received, total);
      },
    );
  }

  Future<void> _writeMetadata({
    required Song2 song,
    required String tempPath,
    required String savePath,
  }) {
    final writer = _injectedMetadataWriter;
    if (writer != null) {
      return writer(song: song, tempPath: tempPath, savePath: savePath);
    }
    return _writeMetadataToFile(
      song: song,
      tempPath: tempPath,
      savePath: savePath,
    );
  }

  Future<void> _writeMetadataToFile({
    required Song2 song,
    required String tempPath,
    required String savePath,
  }) async {
    final coverUrl = normalizeImageUrl(song.al?.picUrl);
    Uint8List? coverBytes;
    String? coverMimeType;
    String? unsynchronizedLyrics;

    if (coverUrl != null) {
      final response = await _dio
          .get<List<int>>(
            coverUrl,
            options: Options(
              responseType: ResponseType.bytes,
              headers: imageHeadersFor(coverUrl),
            ),
          )
          .timeout(const Duration(seconds: 12));
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw StateError('封面下载失败');
      }
      coverBytes = Uint8List.fromList(data);
      coverMimeType = _detectCoverMimeType(coverUrl, response);
    }

    try {
      final lyricText = await _resolveLyrics(song);
      final normalizedLyrics = lyricText?.trim();
      if (normalizedLyrics != null && normalizedLyrics.isNotEmpty) {
        unsynchronizedLyrics = normalizedLyrics;
      }
    } catch (e) {
      debugPrint('获取下载歌词失败: $e');
    }

    final sourceBytes = await File(tempPath).readAsBytes();
    final metadata = _metadataFromSong(
      song,
      coverBytes: coverBytes,
      coverMimeType: coverMimeType,
      unsynchronizedLyrics: unsynchronizedLyrics,
    );
    final outputBytes = _id3Writer.writeMetadataToBytes(sourceBytes, metadata);
    await File(savePath).writeAsBytes(outputBytes, flush: true);
  }

  Mp3Metadata _metadataFromSong(
    Song2 song, {
    Uint8List? coverBytes,
    String? coverMimeType,
    String? unsynchronizedLyrics,
  }) {
    final artists =
        song.ar
            ?.map((artist) => artist.name?.trim())
            .where((name) => name != null && name.isNotEmpty)
            .cast<String>()
            .toList() ??
        const <String>[];
    final albumArtists =
        song.al?.artists
            ?.map((artist) => artist.name?.trim())
            .where((name) => name != null && name.isNotEmpty)
            .cast<String>()
            .toList() ??
        const <String>[];
    final albumArtist =
        albumArtists.isNotEmpty
            ? albumArtists.join('/')
            : _safeReadString(() => song.al?.artist?.name) ?? artists.join('/');

    final customText = <String, String>{};
    _putCustomText(customText, 'NETEASE_SONG_ID', song.id);
    _putCustomText(
      customText,
      'NETEASE_ALBUM_ID',
      _safeReadString(() => song.al?.id),
    );
    final artistIds = song.ar
        ?.map((artist) => _safeReadString(() => artist.id))
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .join(',');
    _putCustomText(customText, 'NETEASE_ARTIST_IDS', artistIds);

    return Mp3Metadata(
      title: song.name,
      artists: artists,
      album: song.al?.name,
      albumArtist: albumArtist,
      year: _yearFromPublishTime(song.publishTime),
      durationMs: song.dt,
      coverBytes: coverBytes,
      coverMimeType: coverMimeType,
      unsynchronizedLyrics: unsynchronizedLyrics,
      customText: customText,
    );
  }

  Future<String?> _resolveLyrics(Song2 song) {
    final resolver = _injectedLyricsResolver;
    if (resolver != null) return resolver(song);
    return _resolveLyricsFromApi(song);
  }

  Future<String?> _resolveLyricsFromApi(Song2 song) async {
    final songId = song.id.trim();
    if (songId.isEmpty) return null;
    final result = await NeteaseMusicApi()
        .songLyric(songId)
        .timeout(const Duration(seconds: 12));
    return result.lrc.lyric;
  }

  void _putCustomText(Map<String, String> target, String key, String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return;
    target[key] = normalized;
  }

  String? _safeReadString(String? Function() read) {
    try {
      final value = read();
      final normalized = value?.trim();
      return normalized == null || normalized.isEmpty ? null : normalized;
    } catch (_) {
      return null;
    }
  }

  String? _yearFromPublishTime(int? publishTime) {
    if (publishTime == null || publishTime <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(publishTime).year.toString();
  }

  String _detectCoverMimeType(String coverUrl, Response<List<int>> response) {
    final contentType = response.headers.value(Headers.contentTypeHeader);
    if (contentType != null && contentType.trim().isNotEmpty) {
      return contentType.split(';').first.trim();
    }

    final lowerUrl = coverUrl.toLowerCase();
    if (lowerUrl.contains('.png')) return 'image/png';
    if (lowerUrl.contains('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<bool> _fileExists(String path) {
    final exists = _injectedFileExists;
    if (exists != null) return exists(path);
    return File(path).exists();
  }

  Future<void> _ensureDirectory(String path) {
    final ensure = _injectedEnsureDirectory;
    if (ensure != null) return ensure(path);
    return Directory(path).create(recursive: true);
  }

  Future<void> _deleteFileIfExists(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String?> _loadDownloadDirectory() {
    final loader = _injectedSettingsLoader;
    if (loader != null) return loader();
    return _loadDownloadDirectoryFromDisk();
  }

  Future<void> _saveDownloadDirectory(String path) {
    final saver = _injectedSettingsSaver;
    if (saver != null) return saver(path);
    return _saveDownloadDirectoryToDisk(path);
  }

  Future<String> _resolveDefaultDirectory() {
    final resolver = _injectedDefaultDirectoryResolver;
    if (resolver != null) return resolver();
    return _resolveDefaultDirectoryFromPlatform();
  }

  Future<String?> _loadDownloadDirectoryFromDisk() async {
    final file = await _settingsFile();
    if (!await file.exists()) return null;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded[_downloadDirectoryKey];
      return value is String ? value : null;
    } catch (e) {
      debugPrint('读取下载设置失败: $e');
      return null;
    }
  }

  Future<void> _saveDownloadDirectoryToDisk(String path) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);

    var settings = <String, dynamic>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          settings = decoded;
        }
      } catch (e) {
        debugPrint('读取已有设置失败，将重写设置文件: $e');
      }
    }

    settings[_downloadDirectoryKey] = path;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings),
    );
  }

  Future<File> _settingsFile() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return File(joinDownloadPath(supportDirectory.path, _settingsFileName));
  }

  Future<String> _resolveDefaultDirectoryFromPlatform() async {
    final supportDirectory = await getApplicationSupportDirectory();
    Directory? downloadsDirectory;
    try {
      downloadsDirectory = await getDownloadsDirectory();
    } catch (e) {
      debugPrint('获取下载目录失败: $e');
    }

    return resolveDefaultDownloadDirectory(
      environment: Platform.environment,
      downloadsDirectory: downloadsDirectory?.path,
      supportDirectory: supportDirectory.path,
      isWindows: Platform.isWindows,
    );
  }

  static String _initialDownloadDirectory() {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.trim().isNotEmpty) {
        return joinDownloadPath(userProfile, 'Desktop');
      }
    }
    return '';
  }
}
