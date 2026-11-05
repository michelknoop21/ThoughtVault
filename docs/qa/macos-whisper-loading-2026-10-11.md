# macOS Whisper model loading regression, 11 October 2026

Scope: crash in macOS 1.0.270 at 9 October 2026 15:50:25 CEST. Matching archive dSYM UUID C78BFD0F-943F-3294-B230-E0FFC6E28017 resolves the crash to `WhisperMLModel.loadModel`, reached from `WhisperKit.runTranscribeTask`. VAD workers may concurrently lazy-load the same unloaded pipeline.

## Change

Initialize WhisperKit with `load: true` before invoking VAD transcription. Keep parallel decoding after models are loaded. Cached model files do not imply Core ML specialization is ready: use the existing 300-second preparation allowance for both cached and downloaded models. The timeout is cooperative; Core ML can finish loading before cancellation is observed. Error text no longer incorrectly attributes cached model loading to an internet problem.

## Actual hardware test

Signed sandboxed Debug test host, Apple Silicon, macOS 27.0.1 (26A434), Xcode Swift 6.4. Installed app was not running before tests and was not replaced. No microphone capture or user meeting audio was used.

Synthetic WAV: 71.821125 seconds, six repeated speech segments separated by silence, 16 kHz mono PCM. Real cached model: `openai_whisper-large-v3-v20240930_626MB`. New opt-in `WhisperLoadingTests.testCachedModelTranscribesMultipleVADWindowsTwice` invokes the actual app transcriber twice and asserts nonempty output.

- First actual run: failed after 111.428 seconds because the old cached-model allowance was only 60 seconds. No segmentation fault. This exposed the insufficient allowance after enabling eager model loading.
- Retest after changing preparation allowance: passed in 23.032 seconds, both transcriptions completed; 1 passed, 0 skipped, 0 failed, no runtime warnings in the xcresult summary.
- Remaining macOS suite: 68 passed, 2 skipped, 1 failed. Failure: `CloudProviderTests.testAllFourHostedProvidersAreOffered`, `XCTAssertTrue failed - ollamaCloud`. The unchanged test expects a standalone `.ollamaCloud` choice; the unchanged `NotulenProvider.studioChoices` in `SettingsView+Studio.swift` instead contains `.ollama`. This is outside the model-loading fix and remains unresolved. The full suite is not green.
- `git diff --check` passed.

Test results:

- `/tmp/thoughtvault-whisper-fix-20261011/Logs/Test/Test-ThoughtVault-2026.10.11_08-50-33-+0200.xcresult` (initial timeout)
- `/tmp/thoughtvault-whisper-fix-20261011/Logs/Test/Test-ThoughtVault-2026.10.11_08-54-36-+0200.xcresult` (real inference passed)
- `/tmp/thoughtvault-whisper-fix-20261011/Logs/Test/Test-ThoughtVault-2026.10.11_08-56-13-+0200.xcresult` (remaining suite)

To explicitly run inference, set `TEST_RUNNER_THOUGHTVAULT_WHISPER_SMOKE_WAV` to synthetic audio longer than 60 seconds and `TEST_RUNNER_THOUGHTVAULT_WHISPER_SMOKE_MODEL` to the cached model variant when invoking `xcodebuild test -only-testing:ThoughtVaultTests/WhisperLoadingTests`. The inference test skips ordinary runs without these variables.

Limits: original segmentation fault not deliberately reproduced; passing synthetic inference does not establish stability for hours-long meetings, every model or all hardware. Production `/Applications/ThoughtVault.app` remains 1.0.270. No installer/release publication or merge was performed.
