import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:verse/netease_api/src/api/play/bean.dart';
import 'package:verse/utils/windows_smtc_policy.dart';

void main() {
  test('buildSmtcMetadata maps song fields and joins artists', () {
    final song = Song2.fromJson({
      'id': 42,
      'name': 'Test Song',
      'ar': [
        {'id': 1, 'name': 'Artist A'},
        {'id': 2, 'name': 'Artist B'},
      ],
      'al': {
        'id': 3,
        'name': 'Test Album',
        'picUrl': 'https://example.com/cover.jpg',
      },
    });

    expect(buildSmtcMetadata(song), {
      'songId': '42',
      'title': 'Test Song',
      'artist': 'Artist A, Artist B',
      'album': 'Test Album',
      'thumbnailUrl': 'https://example.com/cover.jpg',
    });
  });

  test('buildSmtcMetadata supplies safe fallbacks for missing fields', () {
    final song = Song2.fromJson({'id': '7'});

    expect(buildSmtcMetadata(song), {
      'songId': '7',
      'title': '未知歌曲',
      'artist': '未知艺术家',
      'album': '',
      'thumbnailUrl': '',
    });
  });

  test('clampSmtcSeek keeps requested position inside the track duration', () {
    expect(
      clampSmtcSeek(const Duration(seconds: -2), const Duration(minutes: 3)),
      Duration.zero,
    );
    expect(
      clampSmtcSeek(const Duration(minutes: 4), const Duration(minutes: 3)),
      const Duration(minutes: 3),
    );
    expect(
      clampSmtcSeek(const Duration(seconds: 45), const Duration(minutes: 3)),
      const Duration(seconds: 45),
    );
  });

  test('SmtcTimelineThrottle sends at most once per second unless forced', () {
    final throttle = SmtcTimelineThrottle();

    expect(throttle.shouldSend(Duration.zero), isTrue);
    expect(throttle.shouldSend(const Duration(milliseconds: 999)), isFalse);
    expect(throttle.shouldSend(const Duration(seconds: 1)), isTrue);
    expect(
      throttle.shouldSend(const Duration(milliseconds: 1100), force: true),
      isTrue,
    );
  });

  test('SerialAsyncExecutor never overlaps queued track changes', () async {
    final executor = SerialAsyncExecutor();
    final firstMayFinish = Completer<void>();
    final events = <String>[];

    final first = executor.run(() async {
      events.add('first-start');
      await firstMayFinish.future;
      events.add('first-end');
    });
    final second = executor.run(() async {
      events.add('second-start');
      events.add('second-end');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);

    firstMayFinish.complete();
    await Future.wait([first, second]);
    expect(events, ['first-start', 'first-end', 'second-start', 'second-end']);
  });

  test('SerialAsyncExecutor continues after a failed command', () async {
    final executor = SerialAsyncExecutor();
    var secondRan = false;

    final first = executor.run(() async => throw StateError('failed'));
    final second = executor.run(() async {
      secondRan = true;
    });

    await expectLater(first, throwsStateError);
    await second;
    expect(secondRan, isTrue);
  });

  test('smtcPlaybackStatus reflects the real playback lifecycle', () {
    expect(
      smtcPlaybackStatus(
        hasSong: false,
        isPlaying: false,
        isLoading: false,
        isCompleted: false,
      ),
      'stopped',
    );
    expect(
      smtcPlaybackStatus(
        hasSong: true,
        isPlaying: false,
        isLoading: true,
        isCompleted: false,
      ),
      'changing',
    );
    expect(
      smtcPlaybackStatus(
        hasSong: true,
        isPlaying: true,
        isLoading: false,
        isCompleted: false,
      ),
      'playing',
    );
    expect(
      smtcPlaybackStatus(
        hasSong: true,
        isPlaying: false,
        isLoading: false,
        isCompleted: false,
      ),
      'paused',
    );
    expect(
      smtcPlaybackStatus(
        hasSong: true,
        isPlaying: false,
        isLoading: false,
        isCompleted: true,
      ),
      'stopped',
    );
  });

  test('buildSmtcTimeline waits for duration and clamps position', () {
    expect(
      buildSmtcTimeline(
        position: const Duration(seconds: 2),
        duration: Duration.zero,
      ),
      isNull,
    );
    expect(
      buildSmtcTimeline(
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 3),
      ),
      {'positionMs': 180000, 'durationMs': 180000},
    );
  });

  test('resolveSmtcSeek ignores requests until duration is known', () {
    expect(resolveSmtcSeek(const Duration(seconds: 20), Duration.zero), isNull);
    expect(
      resolveSmtcSeek(const Duration(minutes: 4), const Duration(minutes: 3)),
      const Duration(minutes: 3),
    );
  });

  test('SmtcTimelineThrottle reset makes the next update immediate', () {
    final throttle = SmtcTimelineThrottle();

    expect(throttle.shouldSend(Duration.zero), isTrue);
    expect(throttle.shouldSend(const Duration(milliseconds: 100)), isFalse);
    throttle.reset();
    expect(throttle.shouldSend(const Duration(milliseconds: 100)), isTrue);
  });
}
