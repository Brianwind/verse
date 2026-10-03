# YRC Word Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add NetEase YRC word timing and a smooth, Flutter-native word lyric highlight as the first visual checkpoint.

**Architecture:** Keep the copied API transport thin, normalize all lyric formats into immutable `LyricDocument` data, and render the active line with a scoped display-refresh clock. Ordinary LRC remains a line-timed fallback and is never presented as precise word timing.

**Tech Stack:** Flutter, Dart, just_audio, CustomPainter, flutter_test

---

### Task 1: NetEase New Lyric API

**Files:**
- Modify: `lib/netease_api/src/api/play/api.dart`
- Modify: `lib/netease_api/src/api/play/bean.dart`
- Modify: `lib/netease_api/src/api/play/bean.g.dart`
- Test: `test/lyrics/netease_lyric_api_test.dart`

- [ ] **Step 1: Write failing request and deserialization tests**

Assert that `songLyricNewDioMetaData('1902312409')` targets `/api/song/lyric/v1`, sends `cp`, `lv`, `tv`, `rv`, `kv`, `yv`, `ytv`, and `yrv`, and that `SongLyricWrap.fromJson` preserves `yrc`, `ytlrc`, `romalrc`, and `yromalrc` text.

- [ ] **Step 2: Run the test and verify it fails because the new API and fields do not exist**

Run: `flutter test --no-pub test/lyrics/netease_lyric_api_test.dart`

- [ ] **Step 3: Add the new endpoint and typed lyric branches**

Implement `songLyricNewDioMetaData` using `/api/song/lyric/v1` with the upstream parameters set to zero, plus `songLyricNew`. Extend the hand-maintained JSON model and generated mapping with nullable-safe empty lyric branches.

- [ ] **Step 4: Run the API test and verify it passes**

Run: `flutter test --no-pub test/lyrics/netease_lyric_api_test.dart`

### Task 2: Structured Lyric Model and Parser

**Files:**
- Create: `lib/lyrics/lyric_models.dart`
- Create: `lib/lyrics/netease_lyric_parser.dart`
- Test: `test/lyrics/netease_lyric_parser_test.dart`

- [ ] **Step 1: Write failing parser tests**

Cover YRC line/word timing, YTLRC translation matching, YROMALRC romanization matching, empty-word filtering, chronological sorting, and ordinary LRC fallback with `isWordTimed == false`.

- [ ] **Step 2: Run the parser test and verify missing imports fail**

Run: `flutter test --no-pub test/lyrics/netease_lyric_parser_test.dart`

- [ ] **Step 3: Implement immutable models and parser**

Expose `LyricDocument`, `LyricLine`, and `LyricWord`. Prefer YRC, preserve real millisecond timing, align alternate timed tracks by timestamp, and parse LRC into line timing only when YRC is unavailable.

- [ ] **Step 4: Run parser and API tests**

Run: `flutter test --no-pub test/lyrics`

### Task 3: Display-Refresh Playback Clock

**Files:**
- Create: `lib/lyrics/playback_clock.dart`
- Test: `test/lyrics/playback_clock_test.dart`

- [ ] **Step 1: Write failing position-estimation tests**

Assert that a paused clock remains at its anchor, a playing clock advances from monotonic elapsed time, speed is respected, seeking replaces the anchor, and duration clamps the result.

- [ ] **Step 2: Run the test and verify it fails because the estimator is absent**

Run: `flutter test --no-pub test/lyrics/playback_clock_test.dart`

- [ ] **Step 3: Implement the estimator and scoped ticker-backed clock**

Keep elapsed-time math pure for unit tests. The runtime clock listens to the current `AudioPlayer`, samples its extrapolated position on Flutter VSYNC, and notifies only the active lyric renderer.

- [ ] **Step 4: Run the clock test**

Run: `flutter test --no-pub test/lyrics/playback_clock_test.dart`

### Task 4: Timed Lyric Painter and Lyrics View Integration

**Files:**
- Create: `lib/lyrics/timed_lyric_text.dart`
- Modify: `lib/lyrics_view.dart`
- Test: `test/lyrics/timed_lyric_text_test.dart`

- [ ] **Step 1: Write failing painter/widget tests**

Verify that the active word highlight advances with the clock, future glyphs retain the base color, Unicode grapheme boundaries remain intact, and LRC-only lines render without a fake word sweep.

- [ ] **Step 2: Run the test and verify the widget is missing**

Run: `flutter test --no-pub test/lyrics/timed_lyric_text_test.dart`

- [ ] **Step 3: Implement the scoped active-line painter**

Draw a low-emphasis base layer and a cover-derived highlighted layer. Use measured glyph boxes and a soft partial-glyph sweep, while keeping all non-active lines as ordinary Flutter text.

- [ ] **Step 4: Integrate structured lyrics into `LyricsView`**

Fetch through `songLyricNew`, ignore stale async responses after a song change, use real measured line heights, update line selection from coarse player events, and repaint only the active line from the display-refresh clock.

- [ ] **Step 5: Run targeted and full verification**

Run: `flutter test --no-pub test/lyrics`

Run: `flutter test --no-pub`

Run: `dart analyze lib/lyrics lib/lyrics_view.dart lib/netease_api/src/api/play/api.dart lib/netease_api/src/api/play/bean.dart test/lyrics`

### Task 5: Visual Checkpoint

- [ ] **Step 1: Build and launch the Windows app from the feature branch**

Run: `flutter run -d windows`

- [ ] **Step 2: Stop for user acceptance**

Ask the user to play a NetEase song known to have YRC lyrics, verify the active text fills smoothly word by word, seek backward/forward, pause/resume, switch songs rapidly, and compare with an LRC-only song. Do not start the background phase until this checkpoint is approved.
