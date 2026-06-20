import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verse/download_model.dart';
import 'package:verse/netease_api/netease_music_api.dart';

void main() {
  group('DownloadModel', () {
    test(
      'skips existing files without requesting url or downloading',
      () async {
        final downloadedPaths = <String>[];
        var resolverCalls = 0;
        var metadataCalls = 0;
        final model = DownloadModel(
          initialDownloadDirectory: r'C:\Music',
          urlResolver: (song) async {
            resolverCalls++;
            return 'https://example.test/song.mp3';
          },
          downloadExecutor: ({
            required url,
            required savePath,
            onProgress,
            cancelToken,
          }) async {
            downloadedPaths.add(savePath);
          },
          metadataWriter: ({
            required song,
            required tempPath,
            required savePath,
          }) async {
            metadataCalls++;
          },
          fileExists: (path) async => path == r'C:\Music\Artist - Existing.mp3',
          ensureDirectory: (_) async {},
          settingsLoader: () async => null,
          settingsSaver: (_) async {},
          defaultDirectoryResolver: () async => r'C:\Music',
        );

        await model.downloadSong(_song('1', 'Existing', ['Artist']));
        await model.waitForIdle();

        expect(resolverCalls, 0);
        expect(metadataCalls, 0);
        expect(downloadedPaths, isEmpty);
        expect(model.tasks.single.state, DownloadTaskState.skipped);
        expect(model.skippedCount, 1);
        expect(model.succeededCount, 0);
        expect(model.failedCount, 0);
        expect(model.status, DownloadQueueStatus.completed);
      },
    );

    test('continues serial queue after one song fails', () async {
      final downloadedNames = <String>[];
      final model = DownloadModel(
        initialDownloadDirectory: r'C:\Music',
        urlResolver: (song) async {
          if (song.id == 'bad') return null;
          return 'https://example.test/${song.id}.mp3';
        },
        downloadExecutor: ({
          required url,
          required savePath,
          onProgress,
          cancelToken,
        }) async {
          downloadedNames.add(savePath.split(r'\').last);
        },
        metadataWriter:
            ({required song, required tempPath, required savePath}) async {},
        fileExists: (_) async => false,
        ensureDirectory: (_) async {},
        settingsLoader: () async => null,
        settingsSaver: (_) async {},
        defaultDirectoryResolver: () async => r'C:\Music',
      );

      await model.downloadSongs([
        _song('good-1', 'First', ['Artist']),
        _song('bad', 'Broken', ['Artist']),
        _song('good-2', 'Second', ['Artist']),
      ]);
      await model.waitForIdle();

      expect(downloadedNames, [
        'Artist - First.mp3.download',
        'Artist - Second.mp3.download',
      ]);
      expect(model.tasks.map((task) => task.state), [
        DownloadTaskState.succeeded,
        DownloadTaskState.failed,
        DownloadTaskState.succeeded,
      ]);
      expect(model.succeededCount, 2);
      expect(model.failedCount, 1);
      expect(model.skippedCount, 0);
      expect(model.status, DownloadQueueStatus.completed);
    });

    test(
      'marks task failed and leaves no final mp3 when metadata writing fails',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'verse-download-test-',
        );
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });

        final model = DownloadModel(
          initialDownloadDirectory: temp.path,
          urlResolver: (_) async => 'https://example.test/song.mp3',
          downloadExecutor: ({
            required url,
            required savePath,
            onProgress,
            cancelToken,
          }) async {
            await File(savePath).writeAsBytes([0xff, 0xfb, 1, 2]);
          },
          metadataWriter: ({
            required song,
            required tempPath,
            required savePath,
          }) async {
            await File(savePath).writeAsBytes([1, 2, 3]);
            throw StateError('metadata failed');
          },
          fileExists: (path) => File(path).exists(),
          ensureDirectory: (path) => Directory(path).create(recursive: true),
          settingsLoader: () async => null,
          settingsSaver: (_) async {},
          defaultDirectoryResolver: () async => temp.path,
        );

        await model.downloadSong(_song('1', 'Broken Metadata', ['Artist']));
        await model.waitForIdle();

        final task = model.tasks.single;
        expect(task.state, DownloadTaskState.failed);
        expect(task.errorMessage, contains('metadata failed'));
        expect(await File(task.savePath!).exists(), isFalse);
        expect(await File(task.tempPath!).exists(), isFalse);
      },
    );

    test('writes LRC lyrics into the final MP3 metadata', () async {
      final temp = await Directory.systemTemp.createTemp(
        'verse-download-test-',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      const lyrics = '[00:01.00]第一句\n[00:02.50]第二句';
      final model = DownloadModel(
        initialDownloadDirectory: temp.path,
        urlResolver: (_) async => 'https://example.test/song.mp3',
        downloadExecutor: ({
          required url,
          required savePath,
          onProgress,
          cancelToken,
        }) async {
          await File(savePath).writeAsBytes([0xff, 0xfb, 1, 2]);
        },
        lyricsResolver: (_) async => lyrics,
        fileExists: (path) => File(path).exists(),
        ensureDirectory: (path) => Directory(path).create(recursive: true),
        settingsLoader: () async => null,
        settingsSaver: (_) async {},
        defaultDirectoryResolver: () async => temp.path,
      );

      await model.downloadSong(_song('1', 'With Lyrics', ['Artist']));
      await model.waitForIdle();

      final task = model.tasks.single;
      expect(task.state, DownloadTaskState.succeeded);
      final frames = _parseId3Frames(await File(task.savePath!).readAsBytes());
      final uslt = _decodeUsltFrame(frames['USLT']!);
      expect(uslt.language, 'und');
      expect(uslt.description, 'LRC');
      expect(uslt.lyrics, lyrics);
    });

    test('skips USLT when LRC lyrics are empty', () async {
      final temp = await Directory.systemTemp.createTemp(
        'verse-download-test-',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final model = DownloadModel(
        initialDownloadDirectory: temp.path,
        urlResolver: (_) async => 'https://example.test/song.mp3',
        downloadExecutor: ({
          required url,
          required savePath,
          onProgress,
          cancelToken,
        }) async {
          await File(savePath).writeAsBytes([0xff, 0xfb, 1, 2]);
        },
        lyricsResolver: (_) async => '   ',
        fileExists: (path) => File(path).exists(),
        ensureDirectory: (path) => Directory(path).create(recursive: true),
        settingsLoader: () async => null,
        settingsSaver: (_) async {},
        defaultDirectoryResolver: () async => temp.path,
      );

      await model.downloadSong(_song('1', 'No Lyrics', ['Artist']));
      await model.waitForIdle();

      final task = model.tasks.single;
      expect(task.state, DownloadTaskState.succeeded);
      final frames = _parseId3Frames(await File(task.savePath!).readAsBytes());
      expect(frames, isNot(contains('USLT')));
    });

    test('continues metadata writing when lyrics lookup fails', () async {
      final temp = await Directory.systemTemp.createTemp(
        'verse-download-test-',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final model = DownloadModel(
        initialDownloadDirectory: temp.path,
        urlResolver: (_) async => 'https://example.test/song.mp3',
        downloadExecutor: ({
          required url,
          required savePath,
          onProgress,
          cancelToken,
        }) async {
          await File(savePath).writeAsBytes([0xff, 0xfb, 1, 2]);
        },
        lyricsResolver: (_) async => throw StateError('lyrics unavailable'),
        fileExists: (path) => File(path).exists(),
        ensureDirectory: (path) => Directory(path).create(recursive: true),
        settingsLoader: () async => null,
        settingsSaver: (_) async {},
        defaultDirectoryResolver: () async => temp.path,
      );

      await model.downloadSong(_song('1', 'Lyrics Fail', ['Artist']));
      await model.waitForIdle();

      final task = model.tasks.single;
      expect(task.state, DownloadTaskState.succeeded);
      final frames = _parseId3Frames(await File(task.savePath!).readAsBytes());
      expect(frames, contains('TIT2'));
      expect(frames, isNot(contains('USLT')));
    });

    test('calculates download speed and estimated remaining time', () async {
      var now = DateTime(2026, 1, 1, 12);
      final model = DownloadModel(
        initialDownloadDirectory: r'C:\Music',
        clock: () => now,
        urlResolver: (_) async => 'https://example.test/song.mp3',
        downloadExecutor: ({
          required url,
          required savePath,
          onProgress,
          cancelToken,
        }) async {
          onProgress?.call(512, 2048);
          now = now.add(const Duration(seconds: 2));
          onProgress?.call(1024, 2048);
        },
        metadataWriter:
            ({required song, required tempPath, required savePath}) async {},
        fileExists: (_) async => false,
        ensureDirectory: (_) async {},
        settingsLoader: () async => null,
        settingsSaver: (_) async {},
        defaultDirectoryResolver: () async => r'C:\Music',
      );

      await model.downloadSong(_song('1', 'Progress', ['Artist']));
      await model.waitForIdle();

      final task = model.tasks.single;
      expect(task.bytesPerSecond, 512);
      expect(task.estimatedRemaining, const Duration(seconds: 2));
    });

    test(
      'does not estimate remaining time when total size is unknown',
      () async {
        final model = DownloadModel(
          initialDownloadDirectory: r'C:\Music',
          urlResolver: (_) async => 'https://example.test/song.mp3',
          downloadExecutor: ({
            required url,
            required savePath,
            onProgress,
            cancelToken,
          }) async {
            onProgress?.call(1024, -1);
          },
          metadataWriter:
              ({required song, required tempPath, required savePath}) async {},
          fileExists: (_) async => false,
          ensureDirectory: (_) async {},
          settingsLoader: () async => null,
          settingsSaver: (_) async {},
          defaultDirectoryResolver: () async => r'C:\Music',
        );

        await model.downloadSong(_song('1', 'Unknown Size', ['Artist']));
        await model.waitForIdle();

        expect(model.tasks.single.estimatedRemaining, isNull);
      },
    );

    test('cancels current download and removes it from the queue list', () async {
      final started = Completer<void>();
      final model = DownloadModel(
        initialDownloadDirectory: r'C:\Music',
        urlResolver: (_) async => 'https://example.test/song.mp3',
        downloadExecutor: ({
          required url,
          required savePath,
          onProgress,
          cancelToken,
        }) async {
          started.complete();
          await cancelToken!.whenCancel;
          throw DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.cancel,
          );
        },
        metadataWriter:
            ({required song, required tempPath, required savePath}) async {},
        fileExists: (_) async => false,
        ensureDirectory: (_) async {},
        settingsLoader: () async => null,
        settingsSaver: (_) async {},
        defaultDirectoryResolver: () async => r'C:\Music',
      );

      await model.downloadSong(_song('1', 'Cancel Me', ['Artist']));
      await started.future;
      final taskId = model.tasks.single.id;
      await model.cancelTask(taskId);
      await model.waitForIdle();

      expect(model.tasks, isEmpty);
      expect(model.canceledCount, 0);
    });

    test('cancels queued task and removes it before it is downloaded', () async {
      final firstMayFinish = Completer<void>();
      final downloadedIds = <String>[];
      final model = DownloadModel(
        initialDownloadDirectory: r'C:\Music',
        urlResolver: (song) async => 'https://example.test/${song.id}.mp3',
        downloadExecutor: ({
          required url,
          required savePath,
          onProgress,
          cancelToken,
        }) async {
          downloadedIds.add(url.split('/').last.replaceAll('.mp3', ''));
          if (url.contains('first')) await firstMayFinish.future;
        },
        metadataWriter:
            ({required song, required tempPath, required savePath}) async {},
        fileExists: (_) async => false,
        ensureDirectory: (_) async {},
        settingsLoader: () async => null,
        settingsSaver: (_) async {},
        defaultDirectoryResolver: () async => r'C:\Music',
      );

      await model.downloadSongs([
        _song('first', 'First', ['Artist']),
        _song('second', 'Second', ['Artist']),
      ]);
      await Future<void>.delayed(Duration.zero);
      await model.cancelTask(model.tasks.last.id);
      firstMayFinish.complete();
      await model.waitForIdle();

      expect(downloadedIds, ['first']);
      expect(model.tasks.map((task) => task.song.id), ['first']);
    });

    test(
      'retries failed task by resetting progress and queueing it again',
      () async {
        var attempts = 0;
        final model = DownloadModel(
          initialDownloadDirectory: r'C:\Music',
          urlResolver: (_) async => 'https://example.test/song.mp3',
          downloadExecutor: ({
            required url,
            required savePath,
            onProgress,
            cancelToken,
          }) async {
            attempts++;
            onProgress?.call(128, 1024);
            if (attempts == 1) throw StateError('network failed');
          },
          metadataWriter:
              ({required song, required tempPath, required savePath}) async {},
          fileExists: (_) async => false,
          ensureDirectory: (_) async {},
          settingsLoader: () async => null,
          settingsSaver: (_) async {},
          defaultDirectoryResolver: () async => r'C:\Music',
        );

        await model.downloadSong(_song('1', 'Retry Me', ['Artist']));
        await model.waitForIdle();
        expect(model.tasks.single.state, DownloadTaskState.failed);
        expect(model.tasks.single.canRetry, isTrue);

        await model.retryTask(model.tasks.single.id);
        await model.waitForIdle();

        expect(attempts, 2);
        expect(model.tasks.single.state, DownloadTaskState.succeeded);
        expect(model.tasks.single.receivedBytes, 128);
        expect(model.tasks.single.errorMessage, isNull);
      },
    );

    test('clearCompletedTasks keeps failed tasks for retry', () async {
      final model = DownloadModel(
        initialDownloadDirectory: r'C:\Music',
        urlResolver:
            (song) async =>
                song.id == 'bad' ? null : 'https://example.test/song.mp3',
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

      await model.downloadSongs([
        _song('good', 'Good', ['Artist']),
        _song('bad', 'Bad', ['Artist']),
      ]);
      await model.waitForIdle();
      model.clearCompletedTasks();

      expect(model.tasks.length, 1);
      expect(model.tasks.single.song.id, 'bad');
      expect(model.tasks.single.state, DownloadTaskState.failed);
    });
  });
}

Map<String, Uint8List> _parseId3Frames(Uint8List bytes) {
  expect(ascii.decode(bytes.sublist(0, 3)), 'ID3');
  final tagSize = _decodeSynchsafe(bytes, 6);
  final frames = <String, Uint8List>{};
  var offset = 10;
  final end = 10 + tagSize;

  while (offset + 10 <= end) {
    final id = ascii.decode(bytes.sublist(offset, offset + 4));
    if (id.trim().isEmpty || bytes[offset] == 0) break;
    final size = _decodeFrameSize(bytes, offset + 4);
    final dataStart = offset + 10;
    final dataEnd = dataStart + size;
    frames[id] = Uint8List.fromList(bytes.sublist(dataStart, dataEnd));
    offset = dataEnd;
  }

  return frames;
}

int _decodeSynchsafe(Uint8List bytes, int offset) {
  return (bytes[offset] << 21) |
      (bytes[offset + 1] << 14) |
      (bytes[offset + 2] << 7) |
      bytes[offset + 3];
}

int _decodeFrameSize(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

({String language, String description, String lyrics}) _decodeUsltFrame(
  Uint8List data,
) {
  expect(data.first, 1);
  final language = ascii.decode(data.sublist(1, 4));
  final separator = _findUtf16Terminator(data, 4);
  final description = _decodeUtf16LeWithBom(data.sublist(4, separator));
  final lyrics = _decodeUtf16Le(data.sublist(separator + 2));
  return (language: language, description: description, lyrics: lyrics);
}

int _findUtf16Terminator(Uint8List data, int start) {
  for (var i = start; i + 1 < data.length; i += 2) {
    if (data[i] == 0 && data[i + 1] == 0) return i;
  }
  return data.length;
}

String _decodeUtf16LeWithBom(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return _decodeUtf16Le(bytes.sublist(2));
  }
  return _decodeUtf16Le(bytes);
}

String _decodeUtf16Le(Uint8List bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(units);
}

Song2 _song(String id, String name, List<String> artistNames) {
  return Song2()
    ..id = id
    ..name = name
    ..dt = 200000
    ..publishTime = DateTime(2026).millisecondsSinceEpoch
    ..ar =
        artistNames
            .map(
              (name) =>
                  Artists()
                    ..id = '${name.hashCode.abs()}'
                    ..name = name,
            )
            .toList()
    ..al =
        (Album()
          ..id = 'album-$id'
          ..name = 'Album $name'
          ..picUrl = null
          ..artists =
              artistNames
                  .map(
                    (name) =>
                        Artists()
                          ..id = '${name.hashCode.abs()}'
                          ..name = name,
                  )
                  .toList());
}
