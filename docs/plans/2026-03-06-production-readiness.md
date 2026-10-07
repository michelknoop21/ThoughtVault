> Historische documentatie. Actuele desktoparchitectuur en builds: [project-README](/README.md), [releaseproces](/docs/RELEASE.md). Dit document is geen deploy-instructie.

# Production Readiness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all production readiness issues found in the security, code quality, and UX audits.

**Architecture:** Targeted fixes across Services, Views, and project config. No new architecture — surgical edits to existing files.

**Tech Stack:** Swift 6, SwiftUI, macOS 14+, WKWebView

---

## Phase 1: Critical Blockers

### Task 1: Fix force unwraps in MicrosoftGraphService

**Files:**
- Modify: `ThoughtVault/Services/MicrosoftGraphService.swift:110,170,220,237`

**Step 1: Replace force unwrap on line 110**

Change:
```swift
var components = URLComponents(string: "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/authorize")!
```
To:
```swift
guard var components = URLComponents(string: "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/authorize") else {
    throw MicrosoftGraphError.invalidURL
}
```

**Step 2: Replace force unwrap on line 170**

Change:
```swift
let tokenURL = URL(string: "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/token")!
```
To:
```swift
guard let tokenURL = URL(string: "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/token") else {
    throw MicrosoftGraphError.invalidURL
}
```

**Step 3: Replace force unwrap on line 220**

Change:
```swift
var request = URLRequest(url: URL(string: "\(graphBase)/me")!)
```
To:
```swift
guard let meURL = URL(string: "\(graphBase)/me") else {
    throw MicrosoftGraphError.invalidURL
}
var request = URLRequest(url: meURL)
```

**Step 4: Replace force unwrap on line 237**

Change:
```swift
var components = URLComponents(string: "\(graphBase)/me/calendarView")!
```
To:
```swift
guard var components = URLComponents(string: "\(graphBase)/me/calendarView") else { return [] }
```

**Step 5: Build to verify**

Run: `xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Commit**
```
fix: replace force unwraps with safe URL construction in MicrosoftGraphService
```

---

### Task 2: Add confirmation dialog for swipe-delete and context menu delete

**Files:**
- Modify: `ThoughtVault/Views/TranscriptsView.swift`

**Step 1: Add state variable for single-delete confirmation**

After line 61 (`@State private var showBulkDeleteConfirm = false`), add:
```swift
@State private var transcriptToDelete: Transcript? = nil
@State private var showSingleDeleteConfirm = false
```

**Step 2: Replace direct delete in swipe action (line 612-617)**

Change:
```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) {
        Task { await deleteTranscript(transcript) }
    } label: {
        Label("Verwijderen", systemImage: "trash")
    }
}
```
To:
```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) {
        transcriptToDelete = transcript
        showSingleDeleteConfirm = true
    } label: {
        Label("Verwijderen", systemImage: "trash")
    }
}
```

**Step 3: Replace direct delete in context menu (line 626-629)**

Change:
```swift
Button(role: .destructive) {
    Task { await deleteTranscript(transcript) }
} label: {
    Label("Verwijderen", systemImage: "trash")
}
```
To:
```swift
Button(role: .destructive) {
    transcriptToDelete = transcript
    showSingleDeleteConfirm = true
} label: {
    Label("Verwijderen", systemImage: "trash")
}
```

**Step 4: Add confirmation dialog on the list container**

Find the `.confirmationDialog` for bulk delete (around line 160) and add a second one nearby:
```swift
.confirmationDialog(
    "Transcriptie verwijderen?",
    isPresented: $showSingleDeleteConfirm,
    titleVisibility: .visible
) {
    Button("Verwijderen", role: .destructive) {
        if let transcript = transcriptToDelete {
            Task { await deleteTranscript(transcript) }
        }
        transcriptToDelete = nil
    }
    Button("Annuleren", role: .cancel) {
        transcriptToDelete = nil
    }
} message: {
    Text("Deze transcriptie wordt permanent verwijderd.")
}
```

**Step 5: Build to verify**

Run: `xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Commit**
```
fix: add confirmation dialog for swipe-delete and context menu delete
```

---

### Task 3: Add confirmation dialog for cancel recording

**Files:**
- Modify: `ThoughtVault/Views/RecordingView.swift`

**Step 1: Add state for cancel confirmation**

After line 25 (`@State private var showNoteField = false`), add:
```swift
@State private var showCancelConfirm = false
```

**Step 2: Replace direct cancel on line 766-768**

Change:
```swift
controlButton(icon: "xmark", label: "Annuleer", color: Color.labelSecondary) {
    Task { await recordingVM.cancelRecording() }
}
```
To:
```swift
controlButton(icon: "xmark", label: "Annuleer", color: Color.labelSecondary) {
    showCancelConfirm = true
}
```

**Step 3: Add confirmation dialog on the activeRecordingView**

At the end of the `activeRecordingView` computed property (after the ScrollView closing brace around line 560), add:
```swift
.confirmationDialog(
    "Opname annuleren?",
    isPresented: $showCancelConfirm,
    titleVisibility: .visible
) {
    Button("Annuleer opname", role: .destructive) {
        Task { await recordingVM.cancelRecording() }
    }
    Button("Doorgaan met opnemen", role: .cancel) {}
} message: {
    Text("Je huidige opname wordt verwijderd. Dit kan niet ongedaan worden gemaakt.")
}
```

**Step 4: Build to verify**

Run: `xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

**Step 5: Commit**
```
fix: add confirmation dialog before canceling active recording
```

---

### Task 4: Add Privacy Manifest

**Files:**
- Create: `ThoughtVault/PrivacyInfo.xcprivacy`

**Step 1: Create the privacy manifest file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

**Step 2: Add file to Xcode project**

Add `PrivacyInfo.xcprivacy` to the ThoughtVault target in the project navigator. The file must be included in the app bundle's resources.

**Step 3: Commit**
```
feat: add Privacy Manifest (PrivacyInfo.xcprivacy) for App Store compliance
```

---

### Task 5: Add local network entitlement

**Files:**
- Modify: `ThoughtVault/ThoughtVault.entitlements`

**Step 1: Add the entitlement**

Before the closing `</dict>`, add:
```xml
<key>com.apple.security.network.local</key>
<true/>
```

**Step 2: Commit**
```
feat: add local network entitlement for on-device LLM (Ollama/LM Studio)
```

---

### Task 6: Hide retranscription stub button

**Files:**
- Modify: `ThoughtVault/Views/TranscriptsView.swift`

**Step 1: Find the retranscribe button in the detail view toolbar**

Search for where `profileSheetMode = .retranscribe` is set — this is the button that triggers the unimplemented feature. If there's no such line (only `.regenerate` is set), then the retranscribe is only accessible via the ProfileSelectionSheet.

The button is triggered via the `ProfileSelectionSheet` with `mode: profileSheetMode`. The `startRetranscribe` function on line 1608 is the stub. Since `.retranscribe` mode is available in the `ProfileSheetMode` enum but never triggered from the UI (no `profileSheetMode = .retranscribe` assignment found), the feature is already hidden from UI buttons.

However, the `startRetranscribe` function still exists and shows an error message. No UI change needed — the button is not exposed. Skip this task.

---

## Phase 2: Security Hardening

### Task 7: Surface delete errors in HomeView

**Files:**
- Modify: `ThoughtVault/Views/HomeView.swift`

**Step 1: Add delete error state**

After line 31 (`@State private var showAllRecent = false`), add:
```swift
@State private var deleteError: String? = nil
```

**Step 2: Replace empty catch block (line 479-485)**

Change:
```swift
private func deleteTranscript(_ transcript: Transcript) async {
    do {
        try await APIService.shared.deleteTranscript(id: transcript.id)
        recentTranscripts.removeAll { $0.id == transcript.id }
    } catch {
        // TODO: surface error to user
    }
}
```
To:
```swift
private func deleteTranscript(_ transcript: Transcript) async {
    do {
        try await APIService.shared.deleteTranscript(id: transcript.id)
        recentTranscripts.removeAll { $0.id == transcript.id }
    } catch {
        loadError = "Verwijderen mislukt: \(error.localizedDescription)"
    }
}
```

This reuses the existing `loadError` state which already has an error banner with retry button in the UI.

**Step 3: Build to verify**

**Step 4: Commit**
```
fix: surface delete errors to user in HomeView
```

---

### Task 8: Sanitize HTML in EditableHTMLWebView

**Files:**
- Modify: `ThoughtVault/Views/Components/EditableHTMLWebView.swift:161`

**Step 1: Add HTML sanitization helper**

Before the `styledHTML` method, add a private static helper:
```swift
private static func sanitizeHTML(_ html: String) -> String {
    // Strip script tags and event handlers to prevent XSS
    var sanitized = html
    // Remove <script>...</script> blocks
    sanitized = sanitized.replacingOccurrences(
        of: "<script[^>]*>[\\s\\S]*?</script>",
        with: "",
        options: .regularExpression
    )
    // Remove on* event handler attributes
    sanitized = sanitized.replacingOccurrences(
        of: "\\s+on\\w+\\s*=\\s*\"[^\"]*\"",
        with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    sanitized = sanitized.replacingOccurrences(
        of: "\\s+on\\w+\\s*=\\s*'[^']*'",
        with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    // Remove javascript: URLs
    sanitized = sanitized.replacingOccurrences(
        of: "javascript:",
        with: "",
        options: .caseInsensitive
    )
    return sanitized
}
```

**Step 2: Apply sanitization in styledHTML (line 161)**

Change:
```swift
<div id="content" \(editableAttr)>\(html)</div>
```
To:
```swift
<div id="content" \(editableAttr)>\(sanitizeHTML(html))</div>
```

**Step 3: Build to verify**

**Step 4: Commit**
```
fix: sanitize HTML content in EditableHTMLWebView to prevent XSS
```

---

### Task 9: Validate OAuth state parameter

**Files:**
- Modify: `ThoughtVault/Services/MicrosoftGraphService.swift`

**Step 1: Store the state parameter**

Add a private property after line 45 (`private var codeVerifier: String?`):
```swift
private var oauthState: String?
```

**Step 2: Save state before auth (in initiateAuth, around line 108)**

After `let state = UUID().uuidString`, add:
```swift
await service.setOAuthState(state)
```

**Step 3: Add setter method**

After the `setCodeVerifier` method (line 156-158), add:
```swift
private func setOAuthState(_ state: String) {
    self.oauthState = state
}
```

**Step 4: Validate state in callback (around line 147)**

Change:
```swift
guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
    throw MicrosoftGraphError.noAuthCode
}
```
To:
```swift
guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
    throw MicrosoftGraphError.noAuthCode
}

// Validate state parameter to prevent CSRF
let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
let expectedState = await service.oauthState
if returnedState != expectedState {
    throw MicrosoftGraphError.invalidURL
}
```

**Step 5: Clear state after use**

In `exchangeCodeForTokens`, after `self.codeVerifier = nil` (line 204), add:
```swift
self.oauthState = nil
```

**Step 6: Build to verify**

**Step 7: Commit**
```
fix: validate OAuth state parameter to prevent CSRF attacks
```

---

### Task 10: Add error banner dismissal in TranscriptsView

**Files:**
- Modify: `ThoughtVault/Views/TranscriptsView.swift`

**Step 1: Add dismiss button to the load error banner (line 482-506)**

Change the error banner to include a dismiss button:
```swift
@ViewBuilder
private var errorBanner: some View {
    if let error = loadErrorMessage {
        HStack(spacing: TS.Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.statusError)
            Text(error)
                .font(TS.Font.footnote)
                .foregroundStyle(Color.statusError)
            Spacer()
            Button("Opnieuw") {
                Task { await loadTranscripts() }
            }
            .font(TS.Font.footnoteSemibold)
            .foregroundStyle(Color.brandPrimary)
            Button {
                loadErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.labelTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(TS.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                .fill(Color.statusError.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: TS.Radius.sm, style: .continuous)
                        .stroke(Color.statusError.opacity(0.25), lineWidth: 1)
                }
        }
    }
}
```

**Step 2: Build to verify**

**Step 3: Commit**
```
fix: add dismiss button to error banner in TranscriptsView
```

---

### Task 11: Add ProcessingView timeout detection

**Files:**
- Modify: `ThoughtVault/Views/ProcessingView.swift`

**Step 1: Add timeout state**

After line 24 (`@State private var shimmerPhase: CGFloat = -1.0`), add:
```swift
@State private var isStalled = false
@State private var lastStatusChange = Date()
@State private var stalledCheckTask: Task<Void, Never>? = nil
```

**Step 2: Track status changes**

In the existing `.onChange(of: task.status)` (line 38), add at the top of the closure:
```swift
lastStatusChange = Date()
isStalled = false
```

**Step 3: Add stall detection on appear**

In the `.onAppear` block (line 51), add after the existing code:
```swift
stalledCheckTask = Task {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled else { return }
        if task.status != .completed && task.status != .error {
            let elapsed = Date().timeIntervalSince(lastStatusChange)
            if elapsed > 120 {
                await MainActor.run { isStalled = true }
            }
        }
    }
}
```

Add `.onDisappear`:
```swift
.onDisappear {
    stalledCheckTask?.cancel()
}
```

**Step 4: Show stalled indicator**

In `processingContent`, after the `transcriptPreviewPanel` (line 106), add:
```swift
if isStalled {
    HStack(spacing: TS.Spacing.sm) {
        Image(systemName: "clock.badge.exclamationmark")
            .foregroundStyle(Color.brandOrange)
        VStack(alignment: .leading, spacing: 2) {
            Text("Verwerking lijkt vast te zitten")
                .font(TS.Font.footnoteMedium)
                .foregroundStyle(.white)
            Text("Laatste update was meer dan 2 minuten geleden")
                .font(TS.Font.caption)
                .foregroundStyle(Color.white.opacity(0.6))
        }
        Spacer()
        Button("Sluiten") {
            onDismiss()
        }
        .buttonStyle(SecondaryButtonStyle())
    }
    .padding(TS.Spacing.md)
    .background(Color.brandOrange.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: TS.Radius.md))
    .overlay {
        RoundedRectangle(cornerRadius: TS.Radius.md)
            .stroke(Color.brandOrange.opacity(0.30), lineWidth: 1)
    }
}
```

**Step 5: Build to verify**

**Step 6: Commit**
```
feat: add timeout detection for stalled processing in ProcessingView
```

---

## Phase 3: Error Surfacing & Resilience

### Task 12: Surface offline queue persistence errors

**Files:**
- Modify: `ThoughtVault/Services/OfflineQueue.swift`

**Step 1: Add error state**

After line 32 (`var isEmpty: Bool { items.isEmpty }`), add:
```swift
private(set) var lastPersistError: String? = nil
```

**Step 2: Set error on persist failure (line 104-110)**

Change:
```swift
private func persist() {
    do {
        let data = try JSONEncoder().encode(items)
        try data.write(to: storageURL, options: .atomic)
    } catch {
        logger.error("OfflineQueue: failed to persist — \(error.localizedDescription)")
    }
}
```
To:
```swift
private func persist() {
    do {
        let data = try JSONEncoder().encode(items)
        try data.write(to: storageURL, options: .atomic)
        lastPersistError = nil
    } catch {
        lastPersistError = error.localizedDescription
        logger.error("OfflineQueue: failed to persist — \(error.localizedDescription)")
        CrashReporter.shared.recordError(error, context: "OfflineQueue.persist")
    }
}
```

**Step 3: Set error on corrupt load (line 122-127)**

Change:
```swift
} catch {
    logger.error("OfflineQueue: failed to load persisted queue — \(error.localizedDescription)")
    items = []
    try? FileManager.default.removeItem(at: storageURL)
}
```
To:
```swift
} catch {
    logger.error("OfflineQueue: failed to load persisted queue — \(error.localizedDescription)")
    lastPersistError = "Wachtrij kon niet geladen worden en is gewist."
    CrashReporter.shared.recordError(error, context: "OfflineQueue.load")
    items = []
    try? FileManager.default.removeItem(at: storageURL)
}
```

**Step 4: Build to verify**

**Step 5: Commit**
```
fix: track and report offline queue persistence errors
```

---

### Task 13: Log errors with CrashReporter in silent catch blocks

**Files:**
- Modify: `ThoughtVault/Services/MicrosoftGraphService.swift:207,297`

**Step 1: Add CrashReporter to token save (line 207)**

Change:
```swift
try? await APIService.shared.saveCalendarTokens(
    accessToken: tokenResponse.access_token,
    refreshToken: tokenResponse.refresh_token ?? "",
    tokenExpiry: expiry.timeIntervalSince1970,
    email: email
)
```
To:
```swift
do {
    try await APIService.shared.saveCalendarTokens(
        accessToken: tokenResponse.access_token,
        refreshToken: tokenResponse.refresh_token ?? "",
        tokenExpiry: expiry.timeIntervalSince1970,
        email: email
    )
} catch {
    logger.error("Failed to sync calendar tokens to backend: \(error.localizedDescription)")
    CrashReporter.shared.recordError(error, context: "MicrosoftGraphService.saveCalendarTokens")
}
```

**Step 2: Add CrashReporter to token delete (line 297)**

Change:
```swift
try? await APIService.shared.deleteCalendarTokens()
```
To:
```swift
do {
    try await APIService.shared.deleteCalendarTokens()
} catch {
    logger.error("Failed to delete calendar tokens from backend: \(error.localizedDescription)")
    CrashReporter.shared.recordError(error, context: "MicrosoftGraphService.deleteCalendarTokens")
}
```

**Step 3: Build to verify**

**Step 4: Commit**
```
fix: log silent API failures with CrashReporter in MicrosoftGraphService
```

---

## Phase 4: Build Verification

### Task 14: Full build and verify

**Step 1: Run full build**

```bash
xcodebuild -project ThoughtVault.xcodeproj -scheme ThoughtVault -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 2: Commit all remaining changes if any**

```
chore: production readiness phase 1-3 complete
```

---

## Summary of Changes

| Task | File | Type | Issue |
|------|------|------|-------|
| 1 | MicrosoftGraphService.swift | fix | Force unwraps → guard let |
| 2 | TranscriptsView.swift | fix | Swipe/context delete confirmation |
| 3 | RecordingView.swift | fix | Cancel recording confirmation |
| 4 | PrivacyInfo.xcprivacy | feat | Privacy Manifest for App Store |
| 5 | ThoughtVault.entitlements | feat | Local network for Ollama/LM Studio |
| 7 | HomeView.swift | fix | Surface delete errors |
| 8 | EditableHTMLWebView.swift | fix | HTML sanitization (XSS) |
| 9 | MicrosoftGraphService.swift | fix | OAuth state validation |
| 10 | TranscriptsView.swift | fix | Error banner dismiss button |
| 11 | ProcessingView.swift | feat | Stall/timeout detection |
| 12 | OfflineQueue.swift | fix | Persist error tracking |
| 13 | MicrosoftGraphService.swift | fix | CrashReporter for silent failures |
