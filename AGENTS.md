<claude-mem-context>
# Memory Context

# [transcript-studio-native] recent context, 2026-06-02 10:07am GMT+2

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 30 obs (13,112t read) | 486,822t work | 97% savings

### Apr 2, 2026
15243 12:40p 🟣 macOS and Windows task lists now display username for admin users
15244 12:41p 🟣 Admin task user visibility feature fully implemented across backend and clients
15245 " ✅ macOS build verification passed after username field implementation
### Apr 3, 2026
15622 2:52p 🔵 Windows TranscriptDetail implements inline title editing
15624 " 🔵 macOS uses alert-based title editing vs Windows inline editing
15625 2:53p 🔵 Comprehensive UX comparison reveals macOS title editing requires 3 steps vs Windows 1 step
15626 " ✅ Added isEditingTitle state variable to macOS TranscriptDetailView
15627 " 🟣 Implemented inline title editing for macOS matching Windows UX pattern
15628 2:54p 🔴 Wrapped NSCursor hover effects in macOS compiler directive and improved empty state
15648 3:23p 🔄 Consolidated header bar and tab bar into single compact toolbar
15649 3:24p 🟣 Implemented compact Windows-style tab toggle in toolbar
15650 " 🔄 Removed orphaned tab bar code after migration to compact toggle
### May 5, 2026
19749 11:53a 🔵 python-multipart Library Changes Between Versions 0.0.17 and 0.0.22
19750 12:23p 🔵 Root cause identified: python-multipart 0.0.17 boundary-parsing bug with large files
19762 12:52p ✅ Reproduction test tool scaffolded with reqwest
19763 " ✅ Reproduction harness implementation with three diagnostic subcommands
19800 1:41p ✅ Add tempfile and sha2 dependencies for upload refactor
19801 1:42p 🔴 Comprehensive refactor of proxy_upload to eliminate Windows race conditions and file mutation issues
19802 " ✅ Backend forensic logging for multipart upload failures
19831 2:35p 🔴 Fix `.gitlab-ci.yml` YAML syntax error in Windows build script
### May 6, 2026
20228 2:02p 🔴 Windows upload pipeline hardened against recurring 422 on 90+ MB files
20229 " ⚖️ DEC-059: Hardened Windows Upload Pipeline via Empirical Root-Cause Analysis
S4661 Execute safe disk cleanup without data loss — remove unused Docker artifacts, caches, and build debris while preserving running services (May 6 at 5:03 PM)
S4662 Identify and categorize additional home directory and application cache cleanup opportunities with safety assessment and cost/benefit analysis (May 6 at 5:04 PM)
S7503 Implement dynamic cloud model loading for Ollama Cloud integration in SettingsView (May 6 at 5:05 PM)
### Jun 1, 2026
25081 3:52p ⚖️ TranscriptStudio macOS app: Hybrid local-first architecture with optional cloud fallback
25082 3:53p 🟣 SwiftData TranscriptRecord model for local storage
25083 " 🟣 LocalTranscriptStore singleton for SwiftData CRUD operations
**25084** 3:54p ✅ **Inject LocalTranscriptStore into SwiftUI environment**
Completed the SwiftData infrastructure integration for Phase 1. The .modelContainer() modifier on the root WindowGroup ensures the LocalTranscriptStore's ModelContainer is injected into the SwiftUI environment, making TranscriptRecord queries and mutations available throughout the app without manual passing. This is the standard pattern for SwiftData in SwiftUI apps — child views can now use @Query(sort: …) to fetch local records and mutate them directly without fetching through LocalTranscriptStore manually.
~289t 🛠️ 8,599

**25085** " 🟣 **Transcripts tab now displays local history + optional server merge**
Completed the integration of local storage into the Transcripts tab (Phase 1). The loadTranscripts() method now always succeeds by prioritizing local SwiftData records; if the server is unreachable, the user sees their offline history without friction. This satisfies the offline requirement: when the backend is down for cost reduction, users can still see and reprocess their previous recordings without any server dependency. The merge strategy prefers local records on taskId collision, so users' local edits are never overwritten by stale server data.
~330t 🛠️ 4,389

**25086** " ✅ **Delete logic updated to handle local vs server transcripts separately**
Updated deleteTranscript() to handle the hybrid transcript list (local + server records). The logic distinguishes between locally-stored records and server-synced records: local records are removed only from SwiftData, while server records attempt a best-effort server deletion. This avoids unnecessary network calls for records that don't exist on the server and keeps local deletions working even if the server is down.
~297t 🛠️ 8,441

**25087** " ✅ **Xcode project configuration updated for new source files**
Registered the four new Swift files with Xcode's build system by adding them to the project.pbxproj manifest. This ensures the compiler discovers and includes TranscriptRecord.swift, LocalTranscriptStore.swift, LocalTranscriber.swift, and NotuleTitleExtractor.swift in the build. The project file changes are mechanical but necessary for Xcode to recognize these files as part of the target.
~244t 🛠️ 81,562

**25094** " 🟣 **Add Local Processing Settings Section to SettingsView**
User added a complete "Local Processing" settings section to SettingsView.swift, enabling offline transcription and LLM inference configuration. The feature allows users to switch between cloud (server-based) and local processing modes via a segmented picker. When local processing is selected, users configure:
    
    1. **Transcription Engine**: Choose between WhisperKit and Apple Speech Recognition via LocalTranscriberEngine picker
    2. **WhisperKit Model**: Optional text field to specify model name (e.g., "base", "small", "medium")
    3. **Ollama Configuration**: URL, model name, and API key fields for local or cloud-hosted Ollama LLM endpoints
    
    The implementation includes async connection testing—users can click "Verbinding testen" (Test Connection) to verify Ollama endpoint accessibility. The test uses OpenAICompatibleLLMService, checking the `isAvailable` property and displaying a success/failure indicator with appropriate icons and colors (green checkmark for success, red X for failure).
    
    Settings are persisted via @AppStorage and conditional rendering ensures configuration UI appears only when relevant. The section footer explains the local vs. cloud trade-off and hints at Ollama Cloud support via API key.
~584t 🛠️ 25,025

S7512 Commit dynamic Ollama Cloud model loading feature to main branch (Jun 1 at 4:00 PM)
S7525 Execute Codex code review on local-mode transcription feature; assess findings and plan targeted fixes for highest-impact bugs (Jun 1 at 4:34 PM)
S7549 User reports login failure in deployed 1.0.127 release; assess and investigate authentication issue (Jun 1 at 4:42 PM)
S7515 Fix CI archive build failure in v1.0.125 caused by global xcodebuild overrides leaking into WhisperKit dependencies (Jun 1 at 4:42 PM)
S7517 Code review of local-mode transcription feature via Codex; assess and prioritize findings for fixes (Jun 1 at 4:42 PM)
### Jun 2, 2026
S7536 Fix critical and minor Codex code review findings; redesign local processing UI for Ollama Cloud discoverability (Jun 2 at 9:23 AM)
S7557 Complete local-mode implementation for Transcript Studio Native app (v1.0.128) (Jun 2 at 10:02 AM)
**Investigated**: Identified two critical blockers: (1) entire app gated behind login requiring server connectivity, (2) local notes couldn't be opened, edited, or regenerated due to server-only implementation of detail view and management functions

**Learned**: App architecture supports dual modes: cloud (login + server) and local (SwiftData store). Local regeneration of transcription notes uses Ollama on cached transcript data. Home view initially filtered out local records. Graceful degradation acceptable for features requiring external integration (custom profiles, calendar sync, YouTube, admin panel, 2FA, Tasks tab, SSE).

**Completed**: Release 1.0.128 shipped with: local-first mode enabled by default on app launch (no login required); local note management fully functional (open, edit title/tags/content, delete, regenerate); Home feed now displays local records alongside cloud records; login screen includes fallback button to "Use Locally (without server)"; full offline user journey verified (record → transcribe → notarize → view/edit/delete/regenerate) working without network or account

**Next Steps**: Awaiting 1.0.128 deployment to test environment. Optional: block n8n.prezent.nl via /etc/hosts to verify complete offline functionality in real conditions.


Access 487k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>