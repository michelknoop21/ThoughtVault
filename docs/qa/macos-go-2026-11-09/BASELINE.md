# macOS parity baseline

Base: `6d03290` (`codex/pilot-readiness-20261105`, fast-forwarded onto `origin/main` on 2026-11-09). Measured on the Mac candidate machine before any parity change.

| Suite | Command | Result |
|---|---|---|
| macOS XCTest | `xcodebuild test -scheme ThoughtVault -destination 'platform=macOS'` | 72 tests: 69 passed, 3 skipped, 0 failed. `** TEST SUCCEEDED **` |
| Sparkle platforms | `python3 scripts/tests/test_sparkle_platforms.py` | 3 passed |
| Publish script | `python3 scripts/test-publish-release.py` | 2 passed |
| Windows vitest | `npx vitest run` | 53 files, 237 passed, 1 skipped |
| Windows types | `npx tsc --noEmit` | clean |
| Windows Rust | `cargo test` in `windows/src-tauri` | NOT RUN on macOS: build script stops on `resources/nemo-speech-0.2.0/**/*` (Windows-only resource, absent on this machine). Runs on the Windows runner. |

Skipped XCTests (need live audio hardware or an installed Whisper model):

- `AudioEnvelopeProcessorTests.testLiveSystemAudioDrivesWaveform`
- `AudioEnvelopeProcessorTests.testMicrophonePCMIsPublishedWithoutLongWriterDelay`
- `WhisperLoadingTests.testCachedModelTranscribesMultipleVADWindowsTwice`

Not in the test target at this base (never ran): `AuthViewModelTests.swift`, `TranscriptDecoderTests.swift`, `TranscriptsViewModelTests.swift`. Fixed in Task 1.

The stale test `testAllFourHostedProvidersAreOffered` named in the plan no longer exists at this base.
