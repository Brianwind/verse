import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:verse/download_model.dart';
import 'package:verse/download_page.dart';
import 'package:verse/netease_api/netease_music_api.dart';

void main() {
  testWidgets('shows an empty download state', (tester) async {
    final model = _model();

    await tester.pumpWidget(_wrap(model));

    expect(find.text('下载'), findsOneWidget);
    expect(find.text('暂无下载任务'), findsOneWidget);
  });

  testWidgets('shows current task progress, speed, and eta', (tester) async {
    final task =
        DownloadTask(
            id: 'active-1',
            song: _song('1', 'Active Song', ['Artist']),
            fileName: 'Artist - Active Song.mp3',
          )
          ..state = DownloadTaskState.downloading
          ..receivedBytes = 1024
          ..totalBytes = 2048
          ..bytesPerSecond = 512
          ..estimatedRemaining = const Duration(seconds: 2);
    final model = _FakeDownloadModel([task], currentTask: task);

    await tester.pumpWidget(_wrap(model));
    await tester.pump();

    expect(find.text('当前任务'), findsOneWidget);
    expect(find.text('Active Song'), findsWidgets);
    expect(find.textContaining('50%'), findsWidgets);
    expect(find.textContaining('512 B/s'), findsOneWidget);
    expect(find.textContaining('剩余 00:02'), findsOneWidget);
  });

  testWidgets('clears completed tasks from the queue list', (tester) async {
    final task = DownloadTask(
      id: 'done-1',
      song: _song('1', 'Completed Song', ['Artist']),
      fileName: 'Artist - Completed Song.mp3',
    )..state = DownloadTaskState.succeeded;
    final model = _FakeDownloadModel([task]);

    await tester.pumpWidget(_wrap(model));
    expect(find.text('Completed Song'), findsOneWidget);

    await tester.tap(find.text('清除已完成'));
    await tester.pump();

    expect(find.text('Completed Song'), findsNothing);
    expect(find.text('暂无下载任务'), findsOneWidget);
  });
}

class _FakeDownloadModel extends DownloadModel {
  _FakeDownloadModel(this._tasks, {DownloadTask? currentTask})
    : _currentTask = currentTask,
      super(
        initialDownloadDirectory: r'C:\Music',
        urlResolver: (_) async => null,
        downloadExecutor:
            ({
              required url,
              required savePath,
              onProgress,
              cancelToken,
            }) async {},
        metadataWriter:
            ({required song, required tempPath, required savePath}) async {},
        fileExists: (_) async => false,
        ensureDirectory: (_) async {},
        settingsLoader: () async => null,
        settingsSaver: (_) async {},
        defaultDirectoryResolver: () async => r'C:\Music',
      );

  final List<DownloadTask> _tasks;
  final DownloadTask? _currentTask;

  @override
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  @override
  DownloadTask? get currentTask => _currentTask;

  @override
  int get totalCount => _tasks.length;

  @override
  int get completedCount => _tasks.where((task) => task.isTerminal).length;

  @override
  int get failedCount =>
      _tasks.where((task) => task.state == DownloadTaskState.failed).length;

  @override
  void clearCompletedTasks() {
    _tasks.removeWhere(
      (task) =>
          task.state == DownloadTaskState.succeeded ||
          task.state == DownloadTaskState.skipped ||
          task.state == DownloadTaskState.canceled,
    );
    notifyListeners();
  }
}

Widget _wrap(DownloadModel model) {
  return ChangeNotifierProvider.value(
    value: model,
    child: const MaterialApp(home: DownloadPage()),
  );
}

DownloadModel _model({
  DateTime Function()? clock,
  DownloadExecutor? downloadExecutor,
}) {
  return DownloadModel(
    initialDownloadDirectory: r'C:\Music',
    clock: clock,
    urlResolver: (_) async => 'https://example.test/song.mp3',
    downloadExecutor:
        downloadExecutor ??
        ({required url, required savePath, onProgress, cancelToken}) async {},
    metadataWriter:
        ({required song, required tempPath, required savePath}) async {},
    fileExists: (_) async => false,
    ensureDirectory: (_) async {},
    settingsLoader: () async => null,
    settingsSaver: (_) async {},
    defaultDirectoryResolver: () async => r'C:\Music',
  );
}

Song2 _song(String id, String name, List<String> artistNames) {
  return Song2()
    ..id = id
    ..name = name
    ..ar = artistNames.map((name) => Artists()..name = name).toList()
    ..al = (Album()..name = 'Album');
}
