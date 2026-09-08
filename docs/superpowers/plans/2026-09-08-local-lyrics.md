# Local Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display embedded or same-name local lyrics in sync with HiMusic playback on mobile and desktop.

**Architecture:** Add a lyrics domain beside metadata and waveform: a pure parser, source-aware repository, bounded cache, and controller that follows the current queue entry. UI consumes controller state and never reads files directly. Existing `MusicSource` implementations gain a bounded sidecar-read operation so SMB, local directories, and explicitly selected mobile files keep their current access rules.

**Tech Stack:** Flutter/Dart, `just_audio`, `metadata_audio`, `file_selector`, Flutter unit/widget/integration tests

**Spec:** `docs/superpowers/specs/2026-09-08-local-lyrics-design.md`

## Global Constraints

- Support embedded synchronized lyrics, same-name `.lrc`, and embedded plain lyrics in that priority order.
- Support `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, repeated timestamps, and signed millisecond `[offset:]`.
- Decode UTF-8 and UTF-8 BOM first; fall back to GB18030 only after strict UTF-8 fails.
- Read at most 2 MiB for one sidecar lyric file and cache at most 128 parsed songs.
- Never access an iOS or Android sibling file that the system picker did not explicitly grant.
- Lyrics failures must not stop playback or metadata loading.
- Do not add online lookup, translation, word-level timing, editing, or desktop floating lyrics.

---

### Task 1: Lyrics model and LRC parser

**Files:**
- Create: `lib/lyrics/lyrics_document.dart`
- Create: `lib/lyrics/lrc_parser.dart`
- Create: `test/lrc_parser_test.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: raw LRC bytes.
- Produces: `LyricsDocument`, `TimedLyricLine`, `LyricsSource`, and `LrcParser.parse(Uint8List bytes)`.

- [ ] **Step 1: Write failing model and parser tests**

Cover UTF-8 BOM, `[01:02]`, `[01:02.34]`, `[01:02.345]`, two timestamps on one line, signed offset, negative-time clamping, information-tag removal, stable duplicate ordering, plain text, empty input, and a checked-in GB18030 byte fixture.

```dart
test('parses repeated timestamps and applies offset', () {
  final document = LrcParser().parse(
    Uint8List.fromList(utf8.encode('[offset:-500]\n[00:01.00][00:02.00]你好')),
  );
  expect(document.lines.map((line) => line.timestamp), [
    const Duration(milliseconds: 500),
    const Duration(milliseconds: 1500),
  ]);
  expect(document.lines.map((line) => line.text), ['你好', '你好']);
});
```

- [ ] **Step 2: Run the parser test and verify failure**

Run: `./scripts/flutter.sh test test/lrc_parser_test.dart`

Expected: FAIL because `lyrics_document.dart` and `lrc_parser.dart` do not exist.

- [ ] **Step 3: Implement the immutable model**

```dart
enum LyricsSource { embeddedSynced, sidecarLrc, embeddedPlain }

class TimedLyricLine {
  const TimedLyricLine({required this.timestamp, required this.text});
  final Duration timestamp;
  final String text;
}

class LyricsDocument {
  const LyricsDocument({
    required this.source,
    this.lines = const [],
    this.plainText,
    this.offset = Duration.zero,
  });
  final LyricsSource source;
  final List<TimedLyricLine> lines;
  final String? plainText;
  final Duration offset;
  bool get hasTimedLines => lines.isNotEmpty;
}
```

- [ ] **Step 4: Implement strict decoding and LRC parsing**

Add `charset_codec: ^0.1.1` to `pubspec.yaml`; it exposes the same GB18030 decoder API on Android, iOS, macOS, and Windows. `LrcParser` must first call `utf8.decode(bytes, allowMalformed: false)`, then `decodeBytes(bytes, encoding: 'gb18030')` on `FormatException`. Reject empty/only-information-tag content with `const FormatException('没有可显示的歌词')`. Parse timestamps with a compiled regular expression and stable-sort by `(timestamp, originalOrder)`.

- [ ] **Step 5: Run parser tests**

Run: `./scripts/flutter.sh test test/lrc_parser_test.dart`

Expected: PASS for every encoding and timing case.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/lyrics/lyrics_document.dart lib/lyrics/lrc_parser.dart test/lrc_parser_test.dart
git commit -m "feat: parse local LRC lyrics"
```

### Task 2: Bounded sidecar access through every music source

**Files:**
- Modify: `lib/sources/music_source.dart`
- Modify: `lib/sources/local_source.dart`
- Modify: `lib/sources/smb_source.dart`
- Modify: `lib/sources/selected_files_source.dart`
- Modify: `lib/ui/library_page.dart`
- Modify: fake `MusicSource` classes under `test/` and `integration_test/`
- Create: `test/lyrics_sidecar_source_test.dart`

**Interfaces:**
- Consumes: a `MusicEntry`, extension `.lrc`, and byte limit.
- Produces: `Future<Uint8List?> readSidecar(MusicEntry entry, String extension, {required int maxBytes})` on `MusicSource`.

- [ ] **Step 1: Write failing source contract tests**

Create temporary directories and `XFile` lists proving exact basename matching is case-insensitive, unrelated LRC files are ignored, oversized files throw `FileSystemException`, and unselected mobile siblings remain inaccessible.

```dart
final bytes = await source.readSidecar(
  song,
  '.lrc',
  maxBytes: 2 * 1024 * 1024,
);
expect(utf8.decode(bytes!), contains('第一句'));
```

- [ ] **Step 2: Run source tests and verify failure**

Run: `./scripts/flutter.sh test test/lyrics_sidecar_source_test.dart test/selected_files_source_test.dart`

Expected: FAIL because `MusicSource.readSidecar` is missing.

- [ ] **Step 3: Implement source-specific lookup**

`LocalSource` resolves the parent directory through its existing traversal guard, lists siblings without following links, checks size before reading, and returns null on no exact match. `SmbSource` lists only the song's parent path, finds one matching file, checks remote size, and calls `readFileRange`. `SelectedFilesSource` searches only `_files`; maintain a map from each exposed audio entry path to its original `XFile` index so an accompanying selected `.lrc` can be read without exposing it in `list()`.

- [ ] **Step 4: Allow explicit LRC selection on mobile**

Change the `XTypeGroup` in `LibraryPage.addLocal()` to include `lrc` and `public.text` alongside the existing audio types. The visible source listing must continue to contain audio files only.

- [ ] **Step 5: Update all test doubles and run tests**

Run: `./scripts/flutter.sh test test/lyrics_sidecar_source_test.dart test/music_entry_filter_test.dart test/selected_files_source_test.dart`

Expected: PASS; `.lrc` remains absent from track rows while available through `readSidecar`.

- [ ] **Step 6: Commit**

```bash
git add lib/sources lib/ui/library_page.dart test integration_test
git commit -m "feat: read authorized sidecar lyrics"
```

### Task 3: Embedded lyrics reader and prioritized repository

**Files:**
- Create: `lib/lyrics/embedded_lyrics_reader.dart`
- Create: `lib/lyrics/lyrics_repository.dart`
- Create: `test/embedded_lyrics_reader_test.dart`
- Create: `test/lyrics_repository_test.dart`
- Modify: `lib/metadata/track_metadata_reader.dart`

**Interfaces:**
- Consumes: `MusicSource` and `MusicEntry`.
- Produces: `EmbeddedLyricsReader.read(...)`, returning synchronized and plain candidates; `LyricsRepository.load(...)`, returning `Future<LyricsDocument?>`.

- [ ] **Step 1: Write failing priority and cache tests**

Use fake readers to prove synchronized embedded lyrics beat sidecar LRC, sidecar beats embedded plain text, no content returns null, failures fall through to the next source, and the 129th cache entry evicts the least recently used entry.

```dart
expect(
  (await repository.load(source, song))!.source,
  LyricsSource.embeddedSynced,
);
```

- [ ] **Step 2: Run repository tests and verify failure**

Run: `./scripts/flutter.sh test test/embedded_lyrics_reader_test.dart test/lyrics_repository_test.dart`

Expected: FAIL because the readers and repository do not exist.

- [ ] **Step 3: Share one metadata parse operation shape**

Extract the current `AudioBridge.start` plus `metadata_audio.parseUrl` sequence into a reusable private helper or reader service so metadata and embedded lyrics do not create inconsistent parsers. Map supported native synchronized fields to timed lines and common/native unsynchronized fields to plain text. Fix supported tag keys with fixture tests instead of guessing at runtime.

- [ ] **Step 4: Implement repository priority and cache**

Use cache key `source.cacheNamespace|entry.path|entry.size|entry.modified?.millisecondsSinceEpoch`. Keep an insertion-ordered LRU map capped at 128 entries. Sidecar reads always pass `maxBytes: 2 * 1024 * 1024`. Catch source-specific parse/read errors per candidate and continue priority resolution; expose a final load error only when content existed but every candidate failed.

- [ ] **Step 5: Run repository and existing metadata tests**

Run: `./scripts/flutter.sh test test/embedded_lyrics_reader_test.dart test/lyrics_repository_test.dart test/track_metadata_reader_test.dart`

Expected: PASS with existing cover and credit extraction unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/lyrics lib/metadata/track_metadata_reader.dart test
git commit -m "feat: resolve embedded and sidecar lyrics"
```

### Task 4: Playback-aware lyrics controller

**Files:**
- Create: `lib/lyrics/lyrics_controller.dart`
- Create: `test/lyrics_controller_test.dart`
- Modify: `lib/playback/player_controller.dart`

**Interfaces:**
- Consumes: current `MusicSource`, current `MusicEntry`, `AudioPlayer.positionStream`, and seek callback.
- Produces: `LyricsController.document`, `status`, `currentLineIndex`, `load(source, entry)`, `updatePosition(Duration)`, `retry()`, and `clear()`.

- [ ] **Step 1: Write failing state and race tests**

Test loading/success/empty/failure, binary-search selection, forward progression, end-of-song selection, retry, and a slow first-song future that returns after a fast second-song future.

```dart
await controller.load(source, secondSong);
firstCompleter.complete(firstLyrics);
await pumpEventQueue();
expect(controller.entry, secondSong);
```

- [ ] **Step 2: Run controller tests and verify failure**

Run: `./scripts/flutter.sh test test/lyrics_controller_test.dart`

Expected: FAIL because `LyricsController` does not exist.

- [ ] **Step 3: Implement controller state and generation cancellation**

Use a monotonically increasing generation for `load` and `clear`; discard results whose generation is stale. Notify listeners only when status, document, entry, or active line changes. `updatePosition` applies `document.offset` once and uses binary search after seeks.

- [ ] **Step 4: Integrate with PlayerController lifecycle**

Construct `lyrics` beside `metadata` and `waveform`. On `currentIndexStream`, load the current entry after `_syncWaveform`; subscribe to `positionStream` and pass positions to lyrics. Clear lyrics on source changes and dispose it during shutdown. Expose `seekToLyric(TimedLyricLine line) => seek(line.timestamp - document.offset)` with zero clamping.

- [ ] **Step 5: Run controller and playback tests**

Run: `./scripts/flutter.sh test test/lyrics_controller_test.dart test/audio_bridge_test.dart test/waveform_controller_test.dart`

Expected: PASS with no extra parsing on ordinary position events.

- [ ] **Step 6: Commit**

```bash
git add lib/lyrics/lyrics_controller.dart lib/playback/player_controller.dart test/lyrics_controller_test.dart
git commit -m "feat: synchronize lyrics with playback"
```

### Task 5: Responsive lyrics experience

**Files:**
- Create: `lib/lyrics/lyrics_view.dart`
- Create: `lib/ui/now_playing_page.dart`
- Create: `test/lyrics_view_test.dart`
- Create: `test/now_playing_page_test.dart`
- Modify: `lib/ui/library_page.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `LyricsController` and `PlayerController`.
- Produces: reusable `LyricsView`, responsive `NowPlayingPage`, and player-bar lyrics entry button.

- [ ] **Step 1: Write failing LyricsView tests**

Verify current-line key and style, tap-to-seek, plain text, loading, empty, error/retry, user-scroll suspension, “回到当前歌词”, and four-second follow recovery. Inject a clock/timer seam so the test uses `tester.pump(const Duration(seconds: 4))`.

- [ ] **Step 2: Run LyricsView tests and verify failure**

Run: `./scripts/flutter.sh test test/lyrics_view_test.dart`

Expected: FAIL because `LyricsView` does not exist.

- [ ] **Step 3: Implement efficient synchronized scrolling**

Use `ScrollablePositionedList` only if an existing Flutter primitive cannot reliably jump by row index; otherwise use `ListView.builder` with measured fixed lyric-line extent. Scroll only when `currentLineIndex` changes. Use semantic labels `当前歌词：<text>` and `跳转到 <time>`.

- [ ] **Step 4: Write failing responsive page tests**

At 390 px, assert cover/lyrics switching, no overflow, and the lyrics button opening the lyrics view. At 1200 px, assert artwork/details and lyrics appear side by side. At a narrow desktop width, assert the single-column switcher.

- [ ] **Step 5: Implement NowPlayingPage and entry points**

Tapping `_NowPlayingInfo` opens `NowPlayingPage` on mobile. Add an `IconButton` with tooltip `歌词` to `PlayerBar`; it opens directly to lyrics. Use `LayoutBuilder`: width at least 980 renders two panes; smaller widths render a page view or segmented cover/lyrics switch. Preserve current playback, waveform, volume, loop, output-device, and metadata details.

- [ ] **Step 6: Run UI tests**

Run: `./scripts/flutter.sh test test/lyrics_view_test.dart test/now_playing_page_test.dart test/mobile_layout_test.dart test/connected_mobile_layout_test.dart`

Expected: PASS with zero overflow exceptions.

- [ ] **Step 7: Commit**

```bash
git add lib/lyrics/lyrics_view.dart lib/ui/now_playing_page.dart lib/ui/library_page.dart lib/main.dart test
git commit -m "feat: add synchronized lyrics interface"
```

### Task 6: Cross-platform regression and real-device acceptance

**Files:**
- Create: `integration_test/lyrics_acceptance_test.dart`
- Add: `test/fixtures/lyrics/embedded-synced.flac`
- Add: `test/fixtures/lyrics/sidecar-song.*`
- Add: `test/fixtures/lyrics/sidecar-song.lrc`
- Modify: `docs/DEVELOPMENT.md`

**Interfaces:**
- Consumes: the complete lyrics subsystem and three local fixtures.
- Produces: reproducible macOS/iOS acceptance evidence and documented limitations.

- [ ] **Step 1: Create legal, generated fixtures and an end-to-end test**

Generate a short silent or tone audio file with original test text, one embedded synchronized lyric sample, one same-name LRC sample, and one no-lyrics sample. The test starts playback muted, asserts source priority and active-line progression, seeks by tapping a line, switches tracks, and verifies old lyrics disappear.

- [ ] **Step 2: Run all automated checks**

Run:

```bash
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/flutter.sh test integration_test/lyrics_acceptance_test.dart -d macos
```

Expected: analyzer clean, all unit/widget tests pass, macOS integration passes.

- [ ] **Step 3: Build release artifacts**

Run:

```bash
./scripts/flutter.sh build macos --release
./scripts/flutter.sh build ios --release
./scripts/flutter.sh build apk --release
```

Expected: macOS, signed iOS device build, and Android release APK succeed. If Flutter reports an obsolete iOS output path while `build/ios/Release-iphoneos/Runner.app` exists, verify that bundle directly and record the Flutter tooling mismatch.

- [ ] **Step 4: Verify macOS with real lyric fixtures**

Open the exact newly built `.app`, select the fixture directory, capture the lyrics view, seek through a lyric line, and confirm sidecar files never appear as tracks.

- [ ] **Step 5: Verify corlin17mx**

Build and run from `ios/Runner.xcworkspace` with destination `corlin17mx`. Stop any stale paused Xcode session first. Select the audio and LRC fixtures together, verify synchronized scrolling, tap-to-seek, plain/no-lyrics states, background/foreground recovery, and capture a device screenshot plus process evidence.

- [ ] **Step 6: Verify SMB read-only behavior**

Place or identify an authorized same-name LRC on the test SMB share, load it through `SmbSource`, verify the LRC is not listed as a track, and confirm no write API is invoked. If no suitable remote fixture is available, report this acceptance item as unverified rather than substituting a mock.

- [ ] **Step 7: Document evidence and commit**

Update `docs/DEVELOPMENT.md` with exact test counts, artifact paths, device/OS, fixture provenance, screenshots, and any unverified SMB boundary.

```bash
git add integration_test test/fixtures docs/DEVELOPMENT.md
git commit -m "test: verify local lyrics across devices"
```

- [ ] **Step 8: Final review and publication**

Run `git diff --check`, inspect every staged path, push the implementation branch or requested target branch, and verify local HEAD equals the remote ref exactly.
