# QQ Word Lyrics Implementation Plan

**Goal:** Add QQ Music QRC as a strict, third-priority word-timed lyric source without changing the accepted player UI.

**Architecture:** Normalize full song metadata into a provider-neutral context, run NetEase, AMLLDB, and QQ lookups concurrently, then select real word timing in the fixed order NetEase YRC, AMLLDB TTML, QQ QRC, and finally NetEase LRC. Keep QQ transport, matching, decryption, and parsing independently testable.

**Tech Stack:** Flutter, Dart, Dio, XML, PointyCastle-compatible pure Dart DES tables, flutter_test

---

### Task 1: QQ Data Model And Strict Matcher

**Files:**
- Create: `lib/lyrics/lyric_source.dart`
- Create: `lib/lyrics/qq_song_matcher.dart`
- Test: `test/lyrics/qq_song_matcher_test.dart`

- [x] Add complete song context and lyric-source candidates.
- [x] Parse QQ search results and normalize title, artist, album, and duration.
- [x] Reject version, identity, and duration mismatches; rank only reliable candidates.

### Task 2: QDES Decoder And QRC Parser

**Files:**
- Create: `lib/lyrics/qq_qdes.dart`
- Create: `lib/lyrics/qq_qrc_parser.dart`
- Create: `third_party/licenses/pyqdes-MIT.txt`
- Test: `test/lyrics/qq_qdes_test.dart`
- Test: `test/lyrics/qq_qrc_parser_test.dart`

- [x] Port the MIT `pyqdes` behavior, including its QQ-compatible DES table, and retain attribution.
- [x] Validate hex and block sizes, decrypt QDES, inflate zlib, and decode UTF-8.
- [x] Parse both common QRC word-tag layouts and align translation and romanization tracks.

### Task 3: Anonymous QQ Client

**Files:**
- Create: `lib/lyrics/qq_lyric_client.dart`
- Test: `test/lyrics/qq_lyric_client_test.dart`

- [x] Send anonymous QQ search and lyric requests with a five-second source budget.
- [x] Fetch lyrics only for the best reliable top-ten candidate.
- [x] Decrypt all tracks off the UI isolate and cache successful matches/documents with in-flight de-duplication.

### Task 4: Concurrent Source Resolver

**Files:**
- Modify: `lib/lyrics/lyric_resolver.dart`
- Modify: `lib/lyrics_view.dart`
- Modify: `lib/player_screen.dart`
- Modify: `test/lyrics/lyric_resolver_test.dart`
- Modify: `test/lyrics/lyrics_view_test.dart`

- [x] Start all providers before awaiting any result.
- [x] Enforce NetEase YRC, AMLLDB, QQ QRC, NetEase LRC priority and isolate provider failures.
- [x] Pass full `Song2` metadata from the player and preserve generation-token stale-response protection.

### Task 5: Verification And Visual Checkpoint

- [x] Run lyric tests and the complete Flutter test suite.
- [x] Run targeted static analysis and a Windows Debug build.
- [x] Verify real QQ search/QRC decryption with the accepted songs.
- [ ] Stop for user visual acceptance before beginning player-background work.
