# macOS Parity and macOS GO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring every platform-neutral behaviour built for the Windows pilot into the macOS app, fix the macOS data-loss bugs, make a Developer ID build shippable, and reach a macOS GO through the M0-M14 gates.

**Architecture:** Work happens on `feat/macos-parity`, branched from a recorded SHA of `codex/pilot-readiness-20261105` after `main` is fast-forwarded to it. Windows TypeScript in `windows/src/services/` is the behavioural reference; the Swift ports are pure functions where possible (testable without a model or audio device), wired into the existing `RecordingViewModel` through one new shared `NotuleGenerator` instead of the two duplicated generation paths that exist today.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, actors, SwiftData, AVFoundation, ScreenCaptureKit/CoreAudio taps, WhisperKit, Sparkle 2, XCTest, `xcodebuild`, `notarytool`.

**Spec:** the approved plan in this session's transcript (`~/.claude/projects/-Volumes-SSD-Projects-thoughtvault-native/1beeb394-f11f-4b02-946c-d8b6bb3c696d.jsonl`, section "macOS parity with the Windows pilot work, and a macOS GO"). The sections Phase 0-4 below map 1:1 onto it.

## Global Constraints

- `@Observable` only, never `ObservableObject`/`@Published`; `async/await`, no Combine or completion handlers; ViewModels `@MainActor class`, services `actor` or pure `enum` namespaces.
- UI strings Dutch via `Localizable.strings`; code and comments English; no em-dashes in any user-facing copy.
- Design tokens `TS.Spacing`, `TS.Font`, `TS.Radius`; colours `Color.brandPrimary`, `Color.labelPrimary`.
- Bundle ID `com.buildmind.ThoughtVault` (verified: pbxproj line 942, `/Applications/ThoughtVault.app` 1.0.270, container `~/Library/Containers/com.buildmind.ThoughtVault`). `nl.prezent.ThoughtVault` in `scripts/env.sh`, `.gitlab-ci.yml` and the CLAUDE.md store gotcha is wrong.
- Always build sandboxed and signed locally: `-allowProvisioningUpdates`, team `XL9KN38ATX`.
- Every heavy command through `heavy run --label <name> -- <cmd>`.
- Test command (referred to below as **MACTEST**): `heavy run --label tv-mactest -- xcodebuild test -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS' -allowProvisioningUpdates` (append `-only-testing:ThoughtVaultTests/<Class>` for a single class).
- iOS build check (**IOSBUILD**): `heavy run --label tv-ios -- xcodebuild build -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Any new file is added to the correct target in `ThoughtVault.xcodeproj/project.pbxproj` (app files to `ThoughtVault`, tests to `ThoughtVaultTests`); a test file outside the target is a FAIL, which is exactly the bug found in three files today.
- Files above ~400 lines are not grown: new behaviour goes into a new file or a `RecordingViewModel+<Topic>.swift` extension (`RecordingViewModel.swift` is 1844 lines, `TranscriptsView.swift` 2484).
- Notule copy is ported verbatim from the Windows reference, Dutch strings included, so both apps reject on the same text.
- Commits: one per task, author Michel Knoop, no AI attribution, `/verify` before each commit. Never push `main` and never publish a release without explicit approval in the conversation.
- Context7 (`resolve-library-id` then `query-docs`) before first use of: WhisperKit `DecodingOptions`, `AVURLAsset.loadTracks`/`AVAssetReader`, `AVAudioRecorder` finalisation, SwiftUI `fileExporter`/`fileImporter`, `WKWebView.printOperation`, Sparkle 2.10 `sign_update`, `notarytool --key`.

## Review Focus

1. **A recording that survives a crash but whose WAV header says 0 bytes.** A user force-quits mid-meeting; after relaunch the recording must be listed and playable with its full length. Pinned in Task 4 (`testRepairsUnfinalizedInt16Header`, `testRepairsUnfinalizedFloat32Header`).
2. **The audit rejects and the user loses the good notule they already had.** Regenerating with another profile fails the audit; the previously approved notule must stay intact and the draft must appear separately. Pinned in Task 10 (`testRejectedRegenerationKeepsApprovedNotule`).
3. **A notule with decimal numbers ("15.000 euro", "1.5 uur") is split into broken sentences** and the audit reports false "missing" verdicts. Pinned in Task 8 (`testUnitsKeepDecimalDots`, `testConstraintSentencesKeepDecimalDots`).
4. **Importing an MP4 without an audio track, or a silent file.** User expects a clear Dutch error, not a crash or an empty transcript. Pinned in Task 19 (`testVideoWithoutAudioTrackThrowsReadableError`) and Task 20 (`testLongSilenceProducesNoHallucinatedText`).
5. **Two recordings finishing at the same time with on-device transcription.** The second must wait, not cancel the first or load WhisperKit twice. Pinned in Task 17 (`testJobsRunOneAtATimeInFIFOOrder`).

---

## Phase 0: Base

### Task 0: Preflight, fast-forward main, baseline

Facts measured on 2026-11-09: `origin/main` = `eefbe0f`, local `main` = `2e212ea` (behind origin by 97, no own commits), pilot = `6d03290` (83 ahead of `origin/main`, 0 behind, so the merge is a fast-forward with no conflicts). `feat/cloud-transcription` = `eefbe0f` = `origin/main`, so it is already contained and needs no rebase. The pilot worktree `/Volumes/SSD/codex-worktrees/thoughtvault-pilot-20261105` is locked and owned by another session; it keeps moving.

- [ ] **Step 1:** `git fetch --all --prune`, `git worktree list`, `ListAgents`. Re-measure the four refs above; if pilot gained commits, record the new SHA as `BASE_SHA`. If `origin/main` is no longer an ancestor of pilot, stop and ask.
- [ ] **Step 2:** `git worktree add /Volumes/SSD/Projects/thoughtvault-macos-parity -b feat/macos-parity <BASE_SHA>`. All later tasks run there.
- [ ] **Step 3:** Baseline: MACTEST, IOSBUILD, `cd windows && npx vitest run && npx tsc --noEmit`, `cd windows/src-tauri && heavy run --label tv-cargo -- cargo test`, `python3 scripts/tests/test_sparkle_platforms.py`, `python3 scripts/test-publish-release.py`. Write the pass/fail counts and the list of red tests to `docs/qa/macos-go-2026-11-09/BASELINE.md`. Expected red: `testAllFourHostedProvidersAreOffered` (fixed in Task 1).
- [ ] **Step 4:** Ask the user: "Fast-forward `main` to `<BASE_SHA>` and push?" Only on yes: `git push origin <BASE_SHA>:main`. On no, continue on `feat/macos-parity` and leave `main` alone.
- [ ] **Step 5:** Commit `BASELINE.md` on `feat/macos-parity`: `git commit -m "Record macOS parity baseline at <BASE_SHA>"`.

---

## Phase 1: macOS data-safety fixes

### Task 1: Test target hygiene

**Files:**
- Modify: `ThoughtVault.xcodeproj/project.pbxproj` (add `AuthViewModelTests.swift`, `TranscriptDecoderTests.swift`, `TranscriptsViewModelTests.swift` to `ThoughtVaultTests` Sources)
- Modify or delete: `macos/ViewModels/TranscriptsViewModel.swift`, `ThoughtVaultTests/TranscriptsViewModelTests.swift`
- Modify: the test file containing `testAllFourHostedProvidersAreOffered` (find with `grep -rn testAllFourHostedProvidersAreOffered ThoughtVaultTests`)

- [ ] **Step 1:** Add the three files to the test target, run MACTEST, note which fail to compile or fail.
- [ ] **Step 2:** `TranscriptsViewModel`: `grep -rn "TranscriptsViewModel" macos` outside its own file. If nothing instantiates it, delete the class and its test file (dead code removal is part of the approved plan). If something does, fix the tests to the current API.
- [ ] **Step 3:** Rename the stale test to `testOllamaCloudIsReachableThroughOllamaTile` and assert that the hosted provider list offered in settings contains `.ollama` with Ollama Cloud reachable via the Ollama tile (base URL `OpenAICompatibleLLMService.ollamaCloudBaseURL` with an API key), instead of asserting four separate hosted tiles.
- [ ] **Step 4:** MACTEST. Expected: 0 failures.
- [ ] **Step 5:** Commit `Add orphaned test files to the test target and fix stale provider test`.

### Task 2: System audio is written to Recordings, not tmp

**Files:**
- Modify: `macos/Services/SystemAudioCapture.swift:58-62` (`startCapture`)
- Modify: `macos/ViewModels/RecordingViewModel.swift` (stop path for `.systemAudio` mode, mix completion)
- Test: `ThoughtVaultTests/SystemAudioStorageTests.swift` (new)

**Interfaces:**
- Produces: `static func outputURL(in directory: URL, date: Date) -> URL` on `SystemAudioCapture`, returning `<Documents>/Recordings/system_audio_<yyyyMMdd-HHmmss>.wav`. `AudioRecorder.recordingsDirectoryURL() -> URL` (make the existing private `recordingsDirectory()` a `static` internal helper so both recorders share it).

- [ ] **Step 1:** Test `testSystemOutputURLIsInRecordingsDirectory`: `SystemAudioCapture.outputURL(in: AudioRecorder.recordingsDirectoryURL(), date: fixed)` has parent `Recordings` and extension `wav`; `AudioRecorder.savedRecordingURLs()` includes a file created at that URL.
- [ ] **Step 2:** Test `testSystemTempRemovedOnlyAfterVerifiedMix`: create a system WAV and a mic WAV, mix, call `AudioRecorder.removeSourceIfMixIsComplete(sourceURL:combinedURL:expectedFrames:)` for the system file; assert system file is gone and combined file exists. Then with `expectedFrames` wrong, assert the source stays.
- [ ] **Step 3:** Run, expect compile failure (no `outputURL`).
- [ ] **Step 4:** Implement: `startCapture` writes to `outputURL(in:date:)`. In the view model, a system-only stop (`selectedMode == .systemAudio`) goes through the same `dispatchProcessing(url:profile:participants:)` and `loadSavedRecordings()` as a mic stop, so it is listed, retryable and uploaded. After `mixAudioFiles` succeeds, remove the system source with `removeSourceIfMixIsComplete` (the mic source keeps its existing rule).
- [ ] **Step 5:** MACTEST `-only-testing:ThoughtVaultTests/SystemAudioStorageTests`, then full MACTEST.
- [ ] **Step 6:** Commit `Store system audio in Recordings so system-only sessions survive`.

### Task 3: cancelRecording only deletes the current session

**Files:**
- Modify: `macos/Services/AudioRecorder.swift:266-295` (`stopRecording`)
- Modify: `macos/ViewModels/RecordingViewModel.swift:611-640` (`cancelRecording`)
- Test: `ThoughtVaultTests/CancelRecordingTests.swift` (new)

- [ ] **Step 1:** Test `testStopClearsCurrentRecordingURL`: start/stop an `AudioRecorder` against a temp directory (or call the state transition directly if the recorder cannot run headless; then test the extracted `func finishSession() -> URL?` that returns the URL and sets `currentRecordingURL = nil`). Assert the returned URL is non-nil and `currentRecordingURL == nil` afterwards.
- [ ] **Step 2:** Test `testCancelDeletesOnlyThisSessionsFiles`: a previous recording file in Recordings plus a session file; cancel deletes only the session file.
- [ ] **Step 3:** Run, expect FAIL.
- [ ] **Step 4:** Implement: `stopRecording` returns the URL and resets `currentRecordingURL`. `cancelRecording` uses the URL returned by `stopRecording()` (and the `CaptureResult` URLs), never reads `audioRecorder.currentRecordingURL` after stop.
- [ ] **Step 5:** MACTEST.
- [ ] **Step 6:** Commit `Limit recording cancellation to the current session's files`.

### Task 4: Crash recovery for unfinalised WAVs

**Files:**
- Create: `macos/Services/RecordingRecovery.swift`
- Modify: `macos/Services/AudioRecorder.swift:447-475` (`cleanupOldRecordings`, `getOrphanedRecordings`)
- Modify: app launch path (where `cleanupOldRecordings` is called today; `grep -rn cleanupOldRecordings macos`)
- Test: `ThoughtVaultTests/RecordingRecoveryTests.swift` (new)

**Interfaces:**
- Produces: `enum RecordingRecovery { static func repairHeaderIfNeeded(at url: URL) throws -> Bool; static func recoverOrphans(_ urls: [URL]) -> [URL] }`. `repairHeaderIfNeeded` rewrites the RIFF chunk size (offset 4) and the `data` chunk size to match the file length when they disagree, and returns whether it changed the file. It must locate the `data` chunk by walking chunks (AVAudioRecorder and AVAudioFile may write `FLLR`/`fact` chunks before `data`), not assume offset 40.
- Produces: `AudioRecorder.cleanupOldRecordings(protecting:knownRecordingNames:)`, where `knownRecordingNames: Set<String>` is the set of `filename`s with a `TranscriptRecord`; files not in the set are never deleted.

- [ ] **Step 1:** Tests `testRepairsUnfinalizedInt16Header` (16 kHz mono 16-bit, header sizes zeroed, 1 s of samples) and `testRepairsUnfinalizedFloat32Header` (16 kHz mono Float32, as written by `SystemAudioCapture`): after repair `AVAudioFile(forReading:).length == 16_000`. `testLeavesValidHeaderUntouched` returns `false` and the bytes are unchanged. `testIgnoresNonWav` on an `.m4a` returns `false`.
- [ ] **Step 2:** Test `testCleanupSkipsRecordingsWithoutTranscript`: an 8-day-old file not in `knownRecordingNames` survives; an 8-day-old file in the set is deleted.
- [ ] **Step 3:** Run, expect FAIL.
- [ ] **Step 4:** Implement `RecordingRecovery`. At launch: `getOrphanedRecordings()` → `recoverOrphans` → `loadSavedRecordings()` so they appear under "Opgeslagen opnames" as unprocessed. Pass `knownRecordingNames` from `LocalTranscriptStore` to `cleanupOldRecordings`. Context7 checkpoint: AVAudioRecorder file finalisation.
- [ ] **Step 5:** MACTEST.
- [ ] **Step 6:** Commit `Recover unfinalised recordings at launch and never clean up unprocessed audio`.

### Task 5: Combined recording survives sleep

**Files:**
- Modify: `macos/ViewModels/RecordingViewModel.swift:313-336` (`handleWillSleep`, `handleDidWake`)

- [ ] **Step 1:** Extract the stop-and-mix sequence used by the normal stop into `private func finishCombinedSession() async -> URL?` (in a new `macos/ViewModels/RecordingViewModel+Sleep.swift` together with the two sleep handlers, moving them out of the main file).
- [ ] **Step 2:** `handleWillSleep` calls `finishCombinedSession()` and stores its result in `sleepInterruptedFileURL` before setting `.idle`. The mixed file is listed as a saved recording; it is not processed automatically.
- [ ] **Step 3:** Test `testSleepStoresMixedURL` in `ThoughtVaultTests/SleepRecoveryTests.swift`: drive `finishCombinedSession` with two fixture WAVs; assert the returned URL is a `combined_*.wav` in Recordings. If the view model cannot be constructed in tests, test the mix step through the function Task 18 extracts and verify the sleep wiring manually in M10.
- [ ] **Step 4:** MACTEST. Commit `Mix combined recordings before sleep instead of dropping system audio`.

### Task 6: Floating widget cleanup

**Files:**
- Delete: `macos/Services/FloatingWidgetController.swift` (duplicate of the class in `macos/Views/FloatingWidgetPanel.swift:14`; confirm which file the target compiles, remove the other from pbxproj)
- Modify: `macos/Views/Components/RecordingWidgetView.swift`, `macos/ViewModels/RecordingViewModel.swift` (upload path)

- [ ] **Step 1:** Remove the duplicate; build.
- [ ] **Step 2:** Set `uploadProgress` from the upload progress callback in the cloud upload path (find with `grep -n "uploadProgress" macos/ViewModels/RecordingViewModel.swift`), so the widget ring moves.
- [ ] **Step 3:** The widget cancel button calls `cancelRecording()` (behind the existing "Opname annuleren?" confirmation) instead of a no-op.
- [ ] **Step 4:** MACTEST plus a manual widget check recorded for M5. Commit `Remove duplicate widget controller and wire widget progress and cancel`.

---

## Phase 2: Port platform-neutral Windows behaviour

Reference files (read from the base SHA, never edit them): `windows/src/services/notuleAudit.ts`, `windows/src/services/llm.ts:26-27,170-255`, `windows/src/services/localPipeline.ts:155-181`, `windows/src/utils/htmlToMarkdown.ts:8-13`, tests in `windows/src/services/__tests__/{notuleAudit,auditResponse,sourceAudit,llm.audit-integration,llm.decimal-constraints,llm.quality-contract,notuleValidation,textExport}.test.ts`, `windows/src/utils/__tests__/htmlToPlainText.test.ts`.

Contract sharing decision: the Swift tests copy the Windows test inputs and expected strings verbatim, with a comment naming the source test file. A shared JSON fixture would require changing the Windows suite, which is outside this plan.

### Task 7: HTMLPlainText helper

**Files:**
- Create: `macos/Services/HTMLPlainText.swift`
- Modify: TXT export and copy in `macos/Views/TranscriptsView.swift:2268-2310` and `macos/Views/NotuleResultView.swift:529`
- Test: `ThoughtVaultTests/HTMLPlainTextTests.swift`

**Interfaces:**
- Produces: `enum HTMLPlainText { static func from(_ html: String) -> String }`. Rules from `htmlToPlainText`: remove `style`/`script`/`head` blocks with content; newline after `<br>` and after closing `p, h1-h6, li, div, section, blockquote, tr`; tab after closing `td, th`; strip remaining tags; decode `&amp; &lt; &gt; &nbsp; &quot; &#39;` and numeric entities; trim each line; collapse 3+ newlines to 2; trim.

- [ ] **Step 1:** Test `testSeparatesBlocksWithoutLeakingStyles` with the exact input and expected output of `htmlToPlainText.test.ts` (`"Kern\nEen besluit & actie.\nActies\nAlex begint.\nMaandag."`). Port the cases of `textExport.test.ts` as `testTextExport*`.
- [ ] **Step 2:** Run, FAIL. **Step 3:** Implement with `NSRegularExpression`/`Regex`; no WebKit (must run off the main actor).
- [ ] **Step 4:** Replace the current ad-hoc stripping in TXT export and copy with `HTMLPlainText.from`. MACTEST.
- [ ] **Step 5:** Commit `Add shared HTML-to-text conversion with paragraph structure for TXT export and copy`.

### Task 8: NotuleAudit (pure port)

**Files:**
- Create: `macos/Services/NotuleAudit.swift`
- Test: `ThoughtVaultTests/NotuleAuditTests.swift`, `ThoughtVaultTests/NotuleConstraintTests.swift`

**Interfaces:**
- Consumes: `HTMLPlainText.from` (Task 7).
- Produces:
  - `typealias AuditRequest = @Sendable (_ system: String, _ user: String) async throws -> String`
  - `struct NotuleReviewError: LocalizedError { let reason: String; let draftHtml: String }` (`errorDescription` = `reason`)
  - `enum NotuleAudit` with:
    - `static let factualityRules: String` (verbatim `FACTUALITY_RULES` from `llm.ts:27`)
    - `static func units(_ text: String, prefix: String) -> [(id: String, text: String)]` using the regex `(?:[^.!?\n]|(?<=\d)\.(?=\d))+[.!?]?`, whitespace-normalised, empties dropped, ids `\(prefix)\(index + 1)`
    - `static func constraintSentences(_ text: String) -> [String]` (unique, order kept; sentence regex as above; keyword regex `\b(niet|geen|niets|nooit|zonder|vervalt|vervallen|afgewezen|afgekeurd|afwezig|onbeslist|onbekend|not|never|without|cancelled|canceled)\b|open vraag`, case-insensitive)
    - `static func parseAuditResponse(_ text: String) throws -> Any` (one complete fenced block allowed, regex `^```(?:json)?[ \t]*\r?\n([\s\S]*?)\r?\n```$`, then `JSONSerialization`)
    - `static func draftForReview(_ html: String) -> String` (drop `script/style/template/head` with content, drop every tag not in `TEXT_TAGS`, drop all attributes from kept tags)
    - `static func auditSource(source: String, quickNote: String, request: AuditRequest) async throws`
    - `static func auditNotule(source: String, html: String, quickNote: String, request: AuditRequest, requiredSentences: [String] = []) async throws`
  - Error messages, system prompts, user-message prefixes (`"Broncontrole (zonder notule):\n"`, `"Inhoudsaudit (geen generatie):\n"`), the 64 000-character and 400-unit limits, the verdict status sets, the derived reverse evidence graph and the final "onderbouwt geen feiten" check are copied verbatim from `notuleAudit.ts`. JSON payloads use sorted-key-independent encoding but the same field names (`source`, `quickNote`, `notes`, `id`, `text`).
  - Formatting gate (Swift replacement for the DOMPurify step): first remove `script`, `template` and comments with content (DOMPurify does this before the gate, which is why the `<script>Verberg</script>` test passes); then reject when the HTML contains `<style`, any tag outside `TEXT_TAGS`, or any `style`, `class`, `hidden` or `aria-hidden="true"` attribute.

- [ ] **Step 1:** Port every case of `notuleAudit.test.ts` (16 tests, including the `it.each` rows) to XCTest using an `AuditRequest` fixture that builds the complete report from the user message, with a call counter. Names: `testMissingSourceInformationIsReported`, `testContradictionIsReported`, `testIdentityShortcutSkipsModel`, `testAcceptsParaphrases_<n>`, `testRejectsSourceStatus_<status>`, `testRejectsNoteStatus_<status>`, `testRejectsForgedAudit_<kind>`, `testMalformedJSONIsNotApproval`, `testUntrustedInputsArePassedAsData`, `testSizeLimits`, `testHiddenEvidenceRejected_<n>`, `testAllNonFactualRejected`, `testEmptyIdentityRejected`, `testMediaMarkupRejected_<tag>`, `testDraftForReviewIsSafe`, `testCanonicalEvidenceAccepted`, `testSourceWithoutSupportingNoteRejected`. Expected messages verbatim, for example `"De notule mist broninformatie: Joris belt maandag."`.
- [ ] **Step 2:** Port `auditResponse.test.ts` and `sourceAudit.test.ts` cases. Port `llm.decimal-constraints.test.ts` as `testConstraintSentencesKeepDecimalDots` (`"15.000"`, `"1.500.000"`, `"15.5"` stay inside one sentence) plus `testUnitsKeepDecimalDots`.
- [ ] **Step 3:** Run, FAIL (no `NotuleAudit`).
- [ ] **Step 4:** Implement. `auditNotule` is `async` but holds no state; no actor.
- [ ] **Step 5:** MACTEST `-only-testing:ThoughtVaultTests/NotuleAuditTests -only-testing:ThoughtVaultTests/NotuleConstraintTests`. Expected: all green, model-call counts identical to Windows (1 per audit, 0 for identity and size failures).
- [ ] **Step 6:** Commit `Port the notule fact audit from the Windows pilot`.

### Task 9: Prompt rules, chunk guard and a plain completion call

**Files:**
- Modify: `macos/Services/LLMService.swift:33-90,338-390`
- Modify: `macos/Services/AnthropicLLMService.swift`, `macos/Services/AppleFoundationModelService.swift`
- Test: `ThoughtVaultTests/LLMChunkingTests.swift` (extend), `ThoughtVaultTests/NotulePromptTests.swift` (new)

**Interfaces:**
- Produces on `protocol LLMService`: `func complete(system: String, user: String) async throws -> String`. Implemented by `OpenAICompatibleLLMService` (non-streaming wrapper over `streamChatCompletion` with a no-op progress), `AnthropicLLMService`, `AppleFoundationModelService`. `MissingAPIKeyLLMService` and `CloudLLMServiceStub` throw the same error their `generateNotulen` throws.
- Produces: `func notuleSystemPrompt(_ profileSystemPrompt: String) -> String` = profile prompt + `"\n\nBrongetrouwheid gaat vóór beknoptheid en de template. "` + `NotuleAudit.factualityRules` + the two extra sentences from `llm.ts:184` verbatim. (The spec wrote "voor"; the Windows source has "vóór". Use the Windows text.)
- `buildNotuleUserContent` gains `constraints: [String]` and appends the "Verplicht te behouden bronzinnen" block from `llm.ts:239-240` verbatim when non-empty.
- `summarizeInChunks`: chunk system prompt = `"Je vat transcripties samen. Bewaar namen, feiten, besluiten, actiepunten, eigenaren en termijnen. Verzin niets. " + factualityRules`; after joining, if the summary is not shorter than the input, throw `LLMError.generationFailed("De notule-generator verkort de lange transcriptie onvoldoende. De transcriptie is bewaard; kies een ander model en probeer opnieuw.")`.
- `AnthropicLLMService`: apply the same length guard as `OpenAICompatibleLLMService` (chunk above its `maxChunkCharacters`, then the same not-shorter check).

- [ ] **Step 1:** Tests: `testSystemPromptStartsWithSourceFidelity` (contains "Brongetrouwheid gaat vóór beknoptheid" and the full rules), `testConstraintBlockAppendedOnlyWhenPresent`, `testChunkSummaryMustShrink` (stub stream returns the input unchanged; expect the exact Dutch error), `testChunkPromptCarriesFactualityRules`. Port `llm.quality-contract.test.ts` assertions that concern prompt content.
- [ ] **Step 2:** Run, FAIL. **Step 3:** Implement. To test `summarizeInChunks` without a network, inject the streaming function through an internal initializer parameter that defaults to the real one.
- [ ] **Step 4:** MACTEST. Commit `Carry factuality rules through every notule prompt and fail loudly on non-shrinking chunks`.

### Task 10: NotuleGenerator and the rejected-draft flow

**Files:**
- Create: `macos/Services/NotuleGenerator.swift`
- Create: `macos/ViewModels/RecordingViewModel+Notule.swift` (moves `processLocallyWorker` step 3 and `regenerateNotuleLocally` here)
- Modify: `macos/Models/TranscriptRecord.swift`, `macos/Services/LocalTranscriptStore.swift`
- Modify: `macos/ViewModels/RecordingViewModel.swift:838-1100` (remove the moved code; `hasUsableNotule` loses the `\[[^\]]+\]` rule)
- Test: `ThoughtVaultTests/NotuleGeneratorTests.swift`, `ThoughtVaultTests/MigrationTests.swift` (extend)

**Interfaces:**
- Consumes: `NotuleAudit` (Task 8), `LLMService.complete`, `notuleSystemPrompt`, `buildNotuleUserContent(…constraints:)` (Task 9).
- Produces: `struct NotuleGenerator { let service: any LLMService; func generate(transcription: String, profile: Profile, participants: [Participant], quickNote: String?, createdAt: Date, corrections: [PersonalCorrection]) async throws -> String }`. Order: corrected source → `constraintSentences` → one `generateNotulen` call (no progress streaming of the unverified draft into the task) → `stripCodeFences` → `hasUsableNotule` → `ensureNotesSection` → `injectDate` → `PersonalCorrections.html` → `auditSource` → `auditNotule(…requiredSentences: constraints)`. Any audit error becomes `NotuleReviewError(reason: "Feiten, acties en beperkingen konden niet worden bevestigd: \(message)", draftHtml: candidate)`. Move `stripCodeFences`, `injectDate`, `injectParticipants` and `hasUsableNotule` into `NotuleGenerator` as `static` and keep thin forwarding only if other callers need them.
- `TranscriptRecord` gains `var notuleDraftHtml: String?` and `var notuleReviewReason: String?` (optional, default nil, the same additive pattern as `participantsJSON`; no new schema version, because `AppSchemaV1-3` all reference the live type).
- `LocalTranscriptStore`: `func saveRejectedDraft(taskId: String, html: String, reason: String) throws` (does not touch `notuleHtml`), and `finalizeNotule` clears both draft fields.

- [ ] **Step 1:** Tests with a stub `LLMService` whose `generateNotulen` returns fixed HTML and whose `complete` returns the audit fixture: `testApprovedNotuleIsReturned`, `testRejectedDraftThrowsReviewErrorWithDraft`, `testNoProgressChunksEmitted`, `testUsabilityCheckRunsBeforeNotesSectionIsAdded` (generated HTML of under 20 alphanumerics plus a quick note must still be rejected as unusable), `testBracketTextIsNoLongerRejected` (`"[onverstaanbaar]"` in the HTML no longer fails `hasUsableNotule`). Port the flow assertions of `llm.audit-integration.test.ts` and `notuleValidation.test.ts`.
- [ ] **Step 2:** Tests in the view-model layer (or `LocalTranscriptStore` with an in-memory container): `testRejectedDraftIsStoredSeparately` (record `notuleHtml` stays `""`, `notuleDraftHtml` set, task error message ends with `". Het concept is apart bewaard voor beoordeling; er is geen nieuwe goedgekeurde notule opgeslagen."`), `testRejectedRegenerationKeepsApprovedNotule`.
- [ ] **Step 3:** `MigrationTests`: `testV3StoreOpensWithDraftFields` opens a store created before the change (fixture written by the current model minus the two fields, or a copied 1.0.270 store under `ThoughtVaultTests/Fixtures/`) and reads `notuleDraftHtml == nil`.
- [ ] **Step 4:** Run, FAIL. **Step 5:** Implement; both `processLocallyWorker` and `regenerateNotuleLocally` call `NotuleGenerator.generate`. On `NotuleReviewError`, call `saveRejectedDraft` and fail the task with the message from Step 2; if saving fails, append `". Het concept kon niet worden bewaard. De transcriptie en opname zijn niet vervangen."` (both strings from `localPipeline.ts:171-176`).
- [ ] **Step 6:** Verify `macos/Resources/ProfileTemplates.json` equals the pilot's synced copy (`git diff <BASE_SHA> -- macos/Resources/ProfileTemplates.json` is empty).
- [ ] **Step 7:** MACTEST. Commit `Generate notules once, audit them, and keep rejected drafts apart from approved notules`.

### Task 11: Draft review section in the detail view

**Files:**
- Create: `macos/Views/Components/DraftReviewSection.swift`
- Modify: the transcript detail view in `macos/Views/TranscriptsView.swift` (insert the section only; no other layout changes) and `macos/Views/TranscriptDetail+iOS.swift`

- [ ] **Step 1:** `DraftReviewSection(reason: String, draftHtml: String)`: a `DisclosureGroup` collapsed by default, title "Concept, niet gevalideerd", the reason as secondary text, the HTML rendered through `NotuleAudit.draftForReview` in the existing `HTMLWebView`. Shown only when `notuleDraftHtml != nil`. Strings in `Localizable.strings`.
- [ ] **Step 2:** Build, then screenshots at 1920, 1440, 1280 window widths (macOS) and 390, 320 (iOS Simulator) via the background screenshot route (`open -g` with launch args, `screencapture -l`), only after asking whether the running ThoughtVault may be closed. Store under `docs/qa/macos-go-2026-11-09/screens/draft-review-*.png`.
- [ ] **Step 3:** Commit `Show rejected notule drafts for review in the transcript detail`.

### Task 12: Pipeline errors and imported duration

**Files:**
- Modify: `macos/Services/LocalTranscriber.swift:243-260,380-420`, `macos/Services/WhisperModelStore.swift`
- Modify: `macos/ViewModels/RecordingViewModel.swift:573-610` (`importAudioFile`)
- Test: `ThoughtVaultTests/LocalPipelineTests.swift` (new)

**Interfaces:**
- Produces: `WhisperModelStore.isInstalled(_ variant: String) -> Bool`. `LocalTranscriber` throws `LocalTranscriberError.modelNotInstalled(variant)` with Dutch text "Het spraakmodel is nog niet gedownload. Download het in Instellingen; de opname blijft bewaard." instead of starting a download.
- `TranscriptRecord` gains `var durationSeconds: Double?` (same additive pattern), filled from `AVURLAsset(url:).load(.duration)` on import and from recorder duration on record.

- [ ] **Step 1:** Tests `testMissingModelThrowsWithoutDownload` (store reports not installed; transcriber throws `.modelNotInstalled`, no download call on an injected downloader), `testImportStoresDuration` (1 s fixture → 1.0 ± 0.05), `testNativeErrorTextIsPreserved` (the task error message equals the thrown error's `localizedDescription`, no generic replacement; port `localPipeline.retry.test.ts` assertions that apply).
- [ ] **Step 2:** FAIL, implement, MACTEST, commit `Never download speech models implicitly and keep native error text`.

### Task 13: Content search

**Files:**
- Modify: `macos/Views/TranscriptsView.swift:83` (`filteredTranscripts`), `macos/Views/TranscriptsView+iOS.swift`
- Create: `macos/Services/TranscriptSearch.swift`
- Test: `ThoughtVaultTests/TranscriptSearchTests.swift`

**Interfaces:**
- Produces: `enum TranscriptSearch { static func matches(_ query: String, title: String, transcript: String, notuleHtml: String, tags: [String]) -> Bool }`: case- and diacritic-insensitive (`localizedStandardContains`), every whitespace-separated term must match one of the fields, notule matched via `HTMLPlainText.from` (never the raw markup, so `"style"` does not match every styled notule).

- [ ] **Step 1:** Tests: title hit, transcript-only hit, notule-text hit, tag hit, `"style"` no hit on a styled notule, two-term AND, `"cafe"` matches `"café"`.
- [ ] **Step 2:** FAIL, implement, wire both views, MACTEST, commit `Search transcripts by title, transcript, notule text and tags`.

### Task 14: Export and print

**Files:**
- Create: `macos/Services/ExportFile.swift`
- Modify: export menu code in `macos/Views/TranscriptsView.swift:2235-2310`, `macos/Views/NotuleResultView.swift:497-540`, the app's `Commands` (find with `grep -rn "CommandGroup\|\.commands" macos`)
- Test: `ThoughtVaultTests/ExportFileTests.swift`

**Interfaces:**
- Produces: `enum ExportFile { static func filename(title: String, ext: String) -> String; static func contentType(ext: String) -> UTType; static func transcriptHTML(_ raw: String) -> String }`. `filename` removes `/ \ : * ? " < > |` and control characters, trims, caps at 120 characters, falls back to "Notule". `contentType("md")` = `UTType(filenameExtension: "md") ?? .plainText`, `"txt"` = `.plainText`, `"pdf"` = `.pdf`, `"html"` = `.html`. `transcriptHTML` escapes `& < > " '` and turns newlines into `<br>`.

- [ ] **Step 1:** Tests for all three functions, including `transcriptHTML("<script>")` producing `&lt;script&gt;`.
- [ ] **Step 2:** FAIL, implement. Use `NSSavePanel` with `nameFieldStringValue = filename(...)` and `allowedContentTypes = [contentType(ext)]` everywhere a panel is used; the PDF path uses `transcriptHTML` for the raw transcript.
- [ ] **Step 3:** Add a ⌘P menu command "Afdrukken…" that prints the selected notule through `WKWebView.printOperation(with:)` (reuse the existing code at `TranscriptsView.swift:2235`, moved into one function). iOS keeps `UIPrintInteractionController`. Context7 checkpoint: WKWebView printing.
- [ ] **Step 4:** MACTEST, IOSBUILD. Commit `Sanitise export filenames and types, escape raw transcripts, add print command`.

### Task 15: Confirmations and cloud task recovery

**Files:**
- Modify: `macos/Views/TranscriptsView.swift` (dialogs at :161, :173, :966), `macos/ViewModels/RecordingViewModel.swift:1554` (`checkPendingTasks`)
- Test: `ThoughtVaultTests/PendingTaskRecoveryTests.swift`

- [ ] **Step 1:** Inventory: list every destructive action (delete transcript, delete older than 7 days, stop without processing, cancel recording, delete saved recording) with the file:line of its `confirmationDialog`. Add a `confirmationDialog` where one is missing; write the inventory into the Task 24 STATUS row M9.
- [ ] **Step 2:** Extract `nonisolated static func tasksToResume(_ tasks: [TranscriptTask]) -> [TranscriptTask]`: active statuses only, de-duplicated by `taskId`. Test `testTerminalTasksAreNotResumed` and `testResultsAreMatchedByTaskId` (two active tasks with different ids each get their own stream; a completed one triggers no fetch). Compare with `windows/src/services/__tests__/uploadAndTrack.terminal.test.ts` and port its applicable cases.
- [ ] **Step 3:** FAIL, implement, MACTEST, commit `Confirm every destructive action and resume only active cloud tasks`.

### Task 16: Processing advice never overrides the user

**Files:**
- Modify: `macos/Services/ProcessingAdvisor.swift:60-110`
- Test: `ThoughtVaultTests/ProcessingAdvisorTests.swift`

- [ ] **Step 1:** Port `windows/src/services/__tests__/processingAdvice.test.ts`: `transcription(for:)` returns `nil` advice when specs are unknown (memory 0 or chip empty); thresholds match Windows; `notuleProvider(current:)` returns `current` whenever the user chose it explicitly (store an explicit-choice flag where the setting is written), and advice is only shown, never applied.
- [ ] **Step 2:** FAIL, implement (return type becomes `TranscriptionAdvice?`), fix callers, MACTEST, commit `Make processing advice advisory and silent on unknown hardware`.

### Task 17: LocalTranscriptionQueue

**Files:**
- Create: `macos/Services/LocalTranscriptionQueue.swift`
- Modify: `macos/ViewModels/RecordingViewModel.swift` (`processLocallyWorker` step 1 goes through the queue)
- Test: `ThoughtVaultTests/LocalTranscriptionQueueTests.swift`

**Interfaces:**
- Produces: `actor LocalTranscriptionQueue { static let shared: LocalTranscriptionQueue; func run<T: Sendable>(id: String, _ work: @Sendable () async throws -> T) async throws -> T; func position(of id: String) -> Int? }`. FIFO, one at a time, cancellation of a waiting job removes it without running it.

- [ ] **Step 1:** Tests `testJobsRunOneAtATimeInFIFOOrder` (three jobs with sleeps record start/end order; no overlap), `testCancelledWaitingJobNeverRuns`, `testFailureReleasesQueue`.
- [ ] **Step 2:** FAIL, implement with a continuation queue (no polling), wire in, show "Wacht op vorige transcriptie" while `position > 0`. MACTEST. Commit `Run on-device transcriptions one at a time`.

### Task 18: Mixing by averaging with offset alignment

**Files:**
- Create: `macos/Services/AudioMixer.swift` (move `mixAudioFiles` out of `RecordingViewModel.swift:1711`)
- Test: `ThoughtVaultTests/AudioMixerTests.swift`

**Interfaces:**
- Produces: `enum AudioMixer { static func mix(micURL: URL, systemURL: URL, systemStartOffset: TimeInterval, into outputURL: URL) throws -> AVAudioFramePosition }`. Sample = `(mic + sys) / 2`, clamped to −1…1; system samples are shifted by `round(offset * 16_000)` frames (positive offset = system started later, pad with silence; negative = drop leading system frames). Output 16 kHz mono Int16 as today. `SystemAudioCapture` and `AudioRecorder` expose their start `Date`; the view model passes the difference.

- [ ] **Step 1:** Tests: `testAverageOfTwoSines` (0.5 and 0.5 → 0.5), `testNoClipping` (1.0 + 1.0 → 1.0), `testPositiveOffsetPadsSystem` (offset 0.5 s: first 8 000 frames equal mic/2), `testNegativeOffsetDropsSystemLead`, `testLengthIsMaxOfAlignedInputs`.
- [ ] **Step 2:** FAIL, implement, MACTEST, commit `Mix microphone and system audio by averaging with aligned start`.

### Task 19: MP4 and video import

**Files:**
- Create: `macos/Services/AudioExtractor.swift`
- Modify: `fileImporter` in `macos/Views/RecordingView+Studio.swift:133`, `macos/Views/RecordingView+iOS.swift:99`; `AudioRecorder.savedRecordingURLs` extension set (`AudioRecorder.swift:412`); the cloud upload Content-Type in `macos/Services/APIService.swift`
- Test: `ThoughtVaultTests/AudioExtractorTests.swift`, fixture `ThoughtVaultTests/Fixtures/tone-1s.mp4` and `ThoughtVaultTests/Fixtures/video-no-audio.mp4` (generate with `ffmpeg` via `zwaar`, commit them, each under 100 KB)

**Interfaces:**
- Produces: `enum AudioExtractor { static func extractAudio(from videoURL: URL, to wavURL: URL) async throws }` using `AVURLAsset.loadTracks(withMediaType: .audio)`, `AVAssetReader` with `AVAssetReaderTrackOutput` settings 16 kHz mono 16-bit linear PCM, written through `AVAudioFile`. No audio track → `AudioExtractorError.noAudioTrack` with Dutch text "Deze video bevat geen geluidsspoor." Context7 checkpoint: `loadTracks`, `AVAssetReader`.
- Importer types: `[.audio, .audiovisualContent, .movie, .mpeg4Movie]`. `savedRecordingURLs` adds `"mp4", "m4v", "mov"` only if originals are kept; preferred: the extracted WAV is stored in Recordings and the original video is not copied.
- Upload Content-Type from `UTType(filenameExtension:)?.preferredMIMEType ?? "application/octet-stream"`.

- [ ] **Step 1:** Tests `testExtractsOneSecondFromMP4` (WAV length 16 000 ± 160 frames, 16 kHz, mono), `testVideoWithoutAudioTrackThrowsReadableError`, `testUploadContentTypeForMP4IsVideoMP4`, `testInvalidFileThrows` (a `.mp4` containing text).
- [ ] **Step 2:** FAIL, implement, wire `importAudioFile` to extract first when the type conforms to `.audiovisualContent` but not `.audio`. MACTEST, IOSBUILD. Commit `Import video files by extracting their first audio track`.

### Task 20: WhisperKit silence and repetition thresholds

**Files:**
- Modify: `macos/Services/LocalTranscriber.swift:401` (`DecodingOptions`)
- Test: `ThoughtVaultTests/WhisperSilenceTests.swift`; fixture copied from `windows/src-tauri/tests/fixtures/dutch-qa.wav` plus a generated 60 s silence WAV

- [ ] **Step 1:** Context7 `WhisperKit` → `DecodingOptions`: confirm the property names and defaults of `compressionRatioThreshold`, `noSpeechThreshold`, `logProbThreshold` in the version pinned in `Package.resolved`. Set them to the documented OpenAI-Whisper defaults (2.4, 0.6, −1.0) unless the docs give different recommended values; record the source in a one-line comment.
- [ ] **Step 2:** Tests (skipped with `XCTSkip` when the model is not installed, so CI without models stays green; M4 runs them on the candidate machine): `testLongSilenceProducesNoHallucinatedText` (silence + 2 s of `dutch-qa.wav`: output contains no sentence repeated more than twice and no text before the speech), `testDutchClipStillTranscribes` (output non-empty and contains at least one word from the fixture's known transcript).
- [ ] **Step 3:** Implement, MACTEST, commit `Tune WhisperKit decoding thresholds against silence and repetition`.

### Task 21: Keychain write errors reach the UI

**Files:**
- Modify: `macos/Services/KeychainService.swift:17-40` (`save`), every caller (`grep -rn "KeychainService.shared.save" macos`)
- Test: `ThoughtVaultTests/KeychainServiceTests.swift`

**Interfaces:**
- `func save(_ value: String, for key: String) throws` throwing `KeychainError.writeFailed(OSStatus)` with Dutch text "De sleutel kon niet veilig worden opgeslagen (code \(status)). Probeer opnieuw of controleer de sleutelhanger."

- [ ] **Step 1:** Test with an injected `SecItem` add/update function returning `errSecInteractionNotAllowed`: `save` throws `.writeFailed(errSecInteractionNotAllowed)`; success path still round-trips.
- [ ] **Step 2:** FAIL, implement; settings screens show the error inline next to the key field (existing error text style). MACTEST, IOSBUILD, commit `Surface keychain write failures in settings`.

---

## Phase 4: Distribution (before the GO gates, because M1/M2 depend on it)

### Task 22: Release script, bundle ID and CI

**Files:**
- Restore: `scripts/build-macos-release.sh` from `d942b18` (`git show d942b18:scripts/build-macos-release.sh > scripts/build-macos-release.sh; chmod +x`)
- Modify: `scripts/env.sh:20,29`, `.gitlab-ci.yml:46,54` and the `build-macos`/`deploy` jobs, `CLAUDE.md` store-path gotcha, `docs/RELEASE.md`
- Test: `scripts/tests/test_macos_release.py` (new)

- [ ] **Step 1:** Bundle IDs: production `com.buildmind.ThoughtVault`, dev `com.buildmind.ThoughtVault.dev`. Before choosing the dev ID, check whether a dev build with another ID was ever shipped (`/tmp`-free check: `mdfind "kMDItemCFBundleIdentifier == '*ThoughtVault*'"`); a changed ID means a new sandbox container, so ask the user if a shipped dev ID differs.
- [ ] **Step 2:** Release script: replace `--keychain-profile "$APPLE_NOTARY_PROFILE"` with `--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER"` (both submit calls), require those three variables at the top, and keep the Developer ID check. Context7 checkpoint: `notarytool` with API key, Sparkle `sign_update`.
- [ ] **Step 3:** `scripts/tests/test_macos_release.py`: asserts `env.sh` exports `com.buildmind.ThoughtVault` for production, the release script contains `notarytool submit` twice, `stapler staple` twice, `sign_update`, and never `CODE_SIGNING_ALLOWED=NO`; asserts `.gitlab-ci.yml` macOS jobs call `scripts/build-macos-release.sh` and `scripts/publish-release.py` and contain no ad-hoc signing.
- [ ] **Step 4:** CI: `build-macos` runs the release script with the API key from a protected CI variable (file type); `deploy` only runs `publish-release.py`. Fix the CLAUDE.md container path to `com.buildmind.ThoughtVault`.
- [ ] **Step 5:** `python3 scripts/tests/test_macos_release.py`, `python3 scripts/tests/test_sparkle_platforms.py`, `python3 scripts/test-publish-release.py`. Commit `Restore Developer ID release script, fix macOS bundle ID and CI signing`.

### Task 23: Signing and notarisation dry run

Blocked inputs (ask the user at the start of this task, not earlier): the App Store Connect **issuer ID** for key `NA27NHZ724`; confirmation that the key at `~/Downloads/Software/Certificaten-en-sleutels/AuthKey_NA27NHZ724.p8` may be copied to a protected location (`~/.appstoreconnect/private_keys/`).

- [ ] **Step 1:** `security find-identity -v -p codesigning | grep "Developer ID Application"`. If absent, try cloud-managed signing: run the archive and `-exportArchive` steps of the release script with `-allowProvisioningUpdates` and the API key flags (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`).
- [ ] **Step 2:** If Apple refuses cloud-managed Developer ID signing, stop and tell the user: the Account Holder must create a Developer ID Application certificate at developer.apple.com (Certificates → + → Developer ID Application) and install it in the login keychain. This is the only blocker that stays with the user.
- [ ] **Step 3:** With a certificate: run `scripts/build-macos-release.sh` without upload. Evidence: `codesign -dv --verbose=4` shows `Authority=Developer ID Application: … (XL9KN38ATX)` and `flags=0x10000(runtime)`; `spctl -a -vvv -t exec` says `source=Notarized Developer ID`; `xcrun stapler validate` passes on app and DMG; the `.sparkle.json` exists. Save outputs in `docs/qa/macos-go-2026-11-09/M2.txt`.
- [ ] **Step 4:** Commit the evidence file only: `Record Developer ID signing and notarisation evidence`.

---

## Phase 3: macOS GO gates

### Task 24: GO report and gate execution

**Files:**
- Create: `docs/qa/macos-go-2026-11-09/STATUS.md` (format copied from the Windows N01-N17 report on the pilot branch: `grep -rln "N17" docs/qa` at `BASE_SHA`)

Rules: one fixed candidate (commit SHA + DMG SHA-256 written at the top); each row PASS, FAIL, BLOCKED or NOT TESTED with commit, file hash, steps, expected and actual; a re-build after a fix restarts every row that the change can affect. Partial results never count as PASS. GO only when M0-M13 are PASS; M14 follows GO.

- [ ] **M0 source green:** MACTEST, IOSBUILD, `test_sparkle_platforms.py`, `test-publish-release.py`, `test_macos_release.py`, Windows `npx vitest run`, `tsc --noEmit`, `cargo test`. Paste counts.
- [ ] **M1 bundle ID:** `defaults read <app>/Contents/Info.plist CFBundleIdentifier` = `com.buildmind.ThoughtVault`; `grep -rn "nl.prezent.ThoughtVault" scripts .gitlab-ci.yml docs CLAUDE.md` returns nothing outside history docs.
- [ ] **M2 signing:** evidence from Task 23 on the candidate DMG.
- [ ] **M3 content:** the Windows content gate run on macOS with Ollama Cloud, model Kimi K2.6 (name exactly as in the Windows report): 6/6 audit cases, 3/3 meetings; per case the decision (approved or draft) matches the Windows result. Needs `/grant OLLAMA_CLOUD_API`; ask when reached.
- [ ] **M4 ASR fixed clip:** `dutch-qa.wav` through WhisperKit with the advised model; text compared to the Windows reference transcript; Task 20 tests run unskipped.
- [ ] **M5 short real mic recording:** 2 minutes, mic only and combined; widget ring and cancel (Task 6) observed.
- [ ] **M6 imports:** WAV, M4A, MP3, MP4 with audio, MP4 without audio, silent WAV, a renamed text file; expected messages from Tasks 12, 19.
- [ ] **M7 one hour:** 60-minute combined recording; memory peak (`ps -p <pid> -o rss`) recorded every 10 minutes; transcript and notule produced; chunk guard not triggered or triggered with the Dutch message.
- [ ] **M8 ten consecutive runs:** ten imports queued at once; Task 17 order observed; zero failures.
- [ ] **M9 export/edit/reopen:** TXT, MD, PDF, HTML, print; edit notule, quit, reopen, content intact; the confirmation inventory from Task 15.
- [ ] **M10 force-quit recovery:** `kill -9` during a recording at 3 minutes; after relaunch the recording is listed with full length (Task 4). Repeat during sleep (Task 5) with `pmset sleepnow`.
- [ ] **M11 fresh macOS user:** new local macOS account; install the DMG; onboarding, permissions, first recording, first notule.
- [ ] **M12 upgrade and rollback:** back up `~/Library/Containers/com.buildmind.ThoughtVault` (tar with date), install over 1.0.270, data intact; Sparkle update from candidate N to N+1 on a test feed; rollback by reinstalling 1.0.270 and restoring the container backup.
- [ ] **M13 publish:** only through `scripts/publish-release.py`, only after the user says "publiceer" in the conversation; verify the appcast entry and DMG download hash.
- [ ] **M14 pilot:** after GO; pilot users and duration decided by the user.
- [ ] **Final:** commit `STATUS.md` per gate batch: `Record macOS GO gate results for <SHA>`. Report GO or NO-GO to the user with the table.

---

## Out of scope

Android; backend changes; Windows-only engines (whisper.cpp, Parakeet, Faster-Whisper), the WebView CORS proxy and the RDP waveform setting (macOS already honours Reduce Motion); visual density work. Changing the Windows test suite to read shared fixtures.

## Open questions for the user (asked when the owning task starts)

1. Push the fast-forwarded `main` (Task 0, Step 4).
2. Apple Intelligence as notule provider: with the 1:1 audit the on-device model must also pass the audit through `complete(system:user:)`. If its JSON output proves unreliable in M3, should Apple Intelligence results be stored as drafts only, or should the provider be hidden?
3. App Store Connect issuer ID and permission to move the `.p8` key (Task 23).
4. Whether the running ThoughtVault may be closed for screenshots and M5-M10.
