# TranscriptStudio — Production Optimization Plan

**Created:** 2026-03-07
**Version:** 1.0.22
**Scope:** macOS (Swift 6/SwiftUI) + Windows (Tauri 2/React 19)
**Total findings:** 60 issues (9 Critical, 13 High, 23 Medium, 15 Low)

---

## Audit Corrections

- **OAuth CSRF (Windows):** Verified as properly implemented — PKCE + state validation present in microsoftGraph.ts:53-75. Downgraded from Critical to informational.
- **Multipart UTF-8 (macOS):** Force unwraps on `.data(using: .utf8)!` are technically safe (UTF-8 encoding of ASCII literals never fails), but should be cleaned up as a pattern issue. Downgraded from Critical to Medium.

---

## Phase 1: Security Hardening

**Priority:** CRITICAL — Must complete before any release
**Scope:** 8 Critical + 5 security-related High issues
**Estimated effort:** 1-2 sessions

### 1.1 Windows: Enable Content Security Policy

**File:** `transcript-studio-windows/src-tauri/tauri.conf.json:27-29`

**Current:**
```json
"security": {
  "csp": null
}
```

**Change to:**
```json
"security": {
  "csp": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' https://n8n.prezent.nl https://graph.microsoft.com https://login.microsoftonline.com; img-src 'self' data:; font-src 'self'; form-action 'self'; frame-ancestors 'none'"
}
```

**Verification:** App loads without CSP violations in DevTools console. All API calls, SSE streams, and OAuth flows still work.

### 1.2 Windows: Sanitize HTML Rendering (XSS)

**File:** `transcript-studio-windows/src/pages/TranscriptsPage.tsx`

**Step 1:** Install DOMPurify
```bash
cd transcript-studio-windows && npm install dompurify @types/dompurify
```

**Step 2:** Sanitize all 3 instances:

| Line | Current | Fix |
|------|---------|-----|
| 788 | `dangerouslySetInnerHTML={{ __html: editedHTML }}` | Sanitize `editedHTML` with `DOMPurify.sanitize()` before setting |
| 791-794 | `__html: selected.notule_html.startsWith("<") ? selected.notule_html : marked(...)` | Wrap entire expression in `DOMPurify.sanitize()` |
| 248 | `${transcript.notule_html}` in print window | Sanitize before injecting into print document |

**Pattern:**
```typescript
import DOMPurify from "dompurify";
// ...
dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(editedHTML) }}
```

**Verification:** Inject `<img src=x onerror=alert(1)>` into a notule via backend — should be stripped.

### 1.3 Windows: Move Token Out of SSE URL

**File:** `transcript-studio-windows/src/services/sse.ts:23-25`

**Current:**
```typescript
const urlWithAuth = this.token
  ? `${this.url}?token=${encodeURIComponent(this.token)}`
  : this.url;
```

**Change:** Use EventSource with custom headers via Tauri's HTTP client, or use the existing `X-User-Token` header pattern. Since native EventSource doesn't support custom headers, the SSE client already uses manual fetch — add the token as a header instead of query param.

**Verification:** SSE stream connects. Token no longer visible in network URLs.

### 1.4 Windows: Secure Token Storage

**Files:**
- `transcript-studio-windows/src/stores/authStore.ts:28-30`
- `transcript-studio-windows/src/services/api.ts:99-110`
- `transcript-studio-windows/src/services/sse.ts:78-89`

**Current:** Token in localStorage via Zustand persist.

**Change:** Use Tauri's `tauri-plugin-store` with encrypted storage, or invoke a Rust command that stores/retrieves from the OS keyring (already have keyring in Cargo.toml for other auth). Remove `persist` middleware from authStore or switch to sessionStorage-only.

**Verification:** Token not visible in localStorage after login. Token survives page reload (if using Tauri store) or requires re-login (if sessionStorage).

### 1.5 Windows: Validate File Size Before Upload

**File:** `transcript-studio-windows/src-tauri/src/commands/http.rs:78-82`

**Current:**
```rust
let file_bytes = tokio::fs::read(&file_path).await?;
let file_size = file_bytes.len();
```

**Change:** Check file metadata first before reading into memory:
```rust
let metadata = tokio::fs::metadata(&file_path).await?;
let file_size = metadata.len();
if file_size > MAX_UPLOAD_SIZE {
    return Err(format!("File too large: {} bytes (max: {})", file_size, MAX_UPLOAD_SIZE).into());
}
let file_bytes = tokio::fs::read(&file_path).await?;
```

**Also add client-side check in:** `transcript-studio-windows/src/services/api.ts` before calling `invoke("http_upload_file")`.

**Verification:** Upload a file >500MB — should get clear error, not OOM.

### 1.6 macOS: Fix Force Unwraps on Audio Buffer Data

**File:** `TranscriptStudio/ViewModels/RecordingViewModel.swift:861-863`

**Current:**
```swift
let micData = micBuffer.floatChannelData![0]
let sysData = sysBuffer.floatChannelData![0]
let mixData = mixBuffer.floatChannelData![0]
```

**Change:**
```swift
guard let micData = micBuffer.floatChannelData?[0],
      let sysData = sysBuffer.floatChannelData?[0],
      let mixData = mixBuffer.floatChannelData?[0] else {
    logger.error("Audio mixing failed: nil channel data")
    return // or throw
}
```

**Verification:** Build succeeds. Combined recording still produces mixed audio.

### 1.7 macOS: Fix Force Unwraps on Calendar Dates

**File:** `TranscriptStudio/Views/TranscriptsView.swift:90,93`

**Current:**
```swift
let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
```

**Change:**
```swift
guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { break }
// ...
guard let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) else { break }
```

**Verification:** Build succeeds. Date filters still work.

### 1.8 macOS: Fix Force Unwrap in Model ID Init

**File:** `TranscriptStudio/Models/Models.swift:258`

**Current:**
```swift
self.id = decodedId?.isEmpty == false ? decodedId! : (decodedTaskId.isEmpty ? UUID().uuidString : decodedTaskId)
```

**Change:**
```swift
self.id = decodedId.flatMap { $0.isEmpty ? nil : $0 } ?? (decodedTaskId.isEmpty ? UUID().uuidString : decodedTaskId)
```

**Verification:** Build succeeds. Transcripts load correctly.

### 1.9 macOS: SSE HTTPS Validation

**File:** `TranscriptStudio/Services/APIService.swift:790`

**Change:** Add URL scheme check in SSEClient before starting stream:
```swift
guard url.scheme?.lowercased() == "https" else {
    onEvent?(.error(URLValidationError.httpsRequired))
    return
}
```

**Verification:** SSE connects to production (HTTPS). Rejects HTTP URLs.

### 1.10 Windows: Input Validation on Search/Admin

**Files:**
- `transcript-studio-windows/src/services/api.ts:200-204` — max length on search params
- `transcript-studio-windows/src/pages/AdminPage.tsx:82-90` — validate email/role
- `transcript-studio-windows/src/pages/AccountPage.tsx:64-86` — password complexity

**Changes:** Add validation before API calls:
- Search: `params.search.slice(0, 255)` max length
- Admin create: email regex, role in `["user", "admin"]`, password length >= 8
- Password change: length >= 8, not equal to email

**Verification:** Invalid inputs show clear error messages instead of 400 from backend.

### Phase 1 Verification Checklist
- [ ] `npm run tauri build` succeeds (Windows)
- [ ] `xcodebuild build` succeeds (macOS)
- [ ] CSP active — no `csp: null` in tauri.conf.json
- [ ] XSS test: `<script>alert(1)</script>` in notule is stripped
- [ ] Token not in SSE URL query params
- [ ] Token not in localStorage (or encrypted)
- [ ] Large file upload shows clear error
- [ ] No force unwraps (`!`) on optional values in changed files
- [ ] SSE rejects HTTP URLs
- [ ] Invalid admin email shows validation error

---

## Phase 2: Stability & Error Handling

**Priority:** HIGH — Fix before production rollout
**Scope:** Remaining 8 High issues + 8 reliability Medium issues
**Estimated effort:** 1-2 sessions

### 2.1 macOS: Fix nonisolated(unsafe) Concurrent Access

**File:** `TranscriptStudio/ViewModels/RecordingViewModel.swift:105-115`

**Current:** 4 properties marked `nonisolated(unsafe)` accessed from multiple actors.

**Change:** Since RecordingViewModel is `@MainActor`, these should be accessed only on MainActor. Options:
- Remove `nonisolated(unsafe)` and ensure all access is from `@MainActor` context
- Or wrap in a serial queue/lock if cross-actor access is needed

**Specific issues:**
- Line 789-794: `pendingRemovalTasks` dict mutated in detached Task — wrap mutation in `Task { @MainActor in ... }`
- Line 722: Unguarded `self` after suspension — change to `self?.isLiveTranscribing = false` or guard

### 2.2 macOS: Replace try? with Proper Error Logging

**File:** `TranscriptStudio/ViewModels/AuthViewModel.swift:99,102,145,209`

**Change:** Replace `try?` with do-catch that logs the error:
```swift
do {
    let userInfo = try await APIService.shared.getCurrentUser()
    currentUser = userInfo
} catch {
    logger.error("Failed to fetch user info: \(error.localizedDescription)")
    // Continue — user is authenticated but profile data unavailable
}
```

### 2.3 macOS: Fix Upload Progress Thread Safety

**File:** `TranscriptStudio/ViewModels/RecordingViewModel.swift:465-468`

**Current:** Progress callback creates `Task { @MainActor in }` — this is actually correct for Swift concurrency. Verify the closure is `@Sendable` to suppress warnings.

### 2.4 macOS: Biometric Token Expiry

**File:** `TranscriptStudio/Services/BiometricService.swift:73-99`

**Change:** Store expiry timestamp alongside token. Check before returning:
```swift
func getStoredToken() async throws -> String? {
    guard let data = try retrieveFromKeychain() else { return nil }
    let wrapper = try JSONDecoder().decode(TokenWrapper.self, from: data)
    guard wrapper.expiresAt > Date() else {
        removeBiometricToken()
        return nil
    }
    return wrapper.token
}
```

### 2.5 Windows: Event Listener Error Handling

**File:** `transcript-studio-windows/src/pages/RecordingPage.tsx:82-105`

**Change:** Wrap `listen<>()` calls in try-catch, ensure unlisten runs in finally:
```typescript
let unlisten: (() => void) | undefined;
try {
  unlisten = await listen<...>("recording-stopped", handler);
} catch (e) {
  console.error("Failed to register listener:", e);
}
// In cleanup: unlisten?.();
```

### 2.6 Windows: Upload Race Condition / Deduplication

**File:** `transcript-studio-windows/src/pages/RecordingPage.tsx:156-208`

**Change:** Add `isUploading` ref to prevent double-submissions:
```typescript
const isUploadingRef = useRef(false);
// In upload handler:
if (isUploadingRef.current) return;
isUploadingRef.current = true;
try { /* upload */ } finally { isUploadingRef.current = false; }
```

**Also:** On upload failure, add to offline queue instead of just showing error.

### 2.7 Windows: Client-Side Rate Limiting on Admin

**File:** `transcript-studio-windows/src/services/api.ts:349-530`

**Change:** Add debounce/throttle to admin endpoints. Simple approach: cache responses with 3s TTL:
```typescript
private adminCache = new Map<string, { data: any; ts: number }>();
private CACHE_TTL = 3000;
```

### 2.8 Windows: 2FA Code Validation

**File:** `transcript-studio-windows/src/pages/AccountPage.tsx:100-158`

**Change:** Validate 2FA code is exactly 6 digits before sending:
```typescript
if (!/^\d{6}$/.test(code)) {
  setError("Code moet exact 6 cijfers zijn");
  return;
}
```

### 2.9 macOS: SSE Reconnection Notification

**File:** `TranscriptStudio/Services/APIService.swift:859-861`

**Change:** After max reconnect attempts, post a notification:
```swift
NotificationCenter.default.post(name: .sseConnectionFailed, object: nil)
```
Handle in RecordingViewModel to show user feedback.

### 2.10 macOS: Task Removal Race Condition

**File:** `TranscriptStudio/ViewModels/RecordingViewModel.swift:789-795`

**Change:** Ensure `pendingRemovalTasks` mutation happens on MainActor:
```swift
pendingRemovalTasks[taskId]?.cancel()
pendingRemovalTasks[taskId] = Task { @MainActor in
    try? await Task.sleep(nanoseconds: 3_000_000_000)
    guard !Task.isCancelled else { return }
    self.removeTask(taskId)
    self.pendingRemovalTasks.removeValue(forKey: taskId)
}
```

### 2.11 Windows: Upload Retry / Offline Queue Integration

**File:** `transcript-studio-windows/src/pages/RecordingPage.tsx:201-207`

**Change:** On upload error, automatically enqueue to offline queue:
```typescript
catch (err) {
  // Add to offline queue for retry
  offlineQueue.enqueue({ filePath, profileId, timestamp: Date.now() });
  setError("Upload mislukt. Wordt automatisch opnieuw geprobeerd.");
}
```

### 2.12 Windows: JWT Expiration Handling

**File:** `transcript-studio-windows/src/stores/authStore.ts`

**Change:** Decode JWT expiry on login, set timer for auto-logout:
```typescript
setToken: (token) => {
  const payload = JSON.parse(atob(token.split('.')[1]));
  const expiresAt = payload.exp ? payload.exp * 1000 : Date.now() + 24 * 60 * 60 * 1000;
  set({ token, isAuthenticated: true, expiresAt });
}
```
Check expiry before each request in api.ts.

### Phase 2 Verification Checklist
- [ ] No `nonisolated(unsafe)` without synchronization
- [ ] No `try?` without logging in AuthViewModel
- [ ] Biometric tokens rejected after expiry
- [ ] Double-click upload doesn't create duplicates
- [ ] Failed upload goes to offline queue
- [ ] 2FA code validates as 6 digits before send
- [ ] SSE reconnection failure shows user message
- [ ] Admin tab switch doesn't spam API (check network tab)

---

## Phase 3: Accessibility & UX

**Priority:** MEDIUM — Required for production quality
**Scope:** 11 accessibility + UX issues
**Estimated effort:** 1-2 sessions

### 3.1 Windows: Add aria-labels to All Icon Buttons

**Files:** All pages with icon-only buttons:
- `src/pages/RecordingPage.tsx` — back button (~247), recording controls (~566-599)
- `src/pages/AdminPage.tsx` — delete, copy buttons
- `src/pages/TranscriptsPage.tsx` — tag remove, edit buttons
- `src/components/FeedbackWidget.tsx` — close button
- `src/components/ui/InfoBar.tsx` — dismiss button

**Pattern:**
```tsx
<button aria-label="Terug naar startpagina" className="icon-btn">
```

### 3.2 macOS: Add VoiceOver Labels

**File:** `TranscriptStudio/Views/RecordingView.swift`

**Lines:** ~413 (close warning), ~527-531 (recording mode buttons), ~882-911 (control buttons)

**Pattern:**
```swift
Button { ... }
    .accessibilityLabel("Start opname")
    .accessibilityHint("Dubbelklik om de opname te starten")
```

### 3.3 macOS: Dynamic Type Support

**File:** `TranscriptStudio/Extensions/Theme.swift`

**Change:** Use `.scaledFont` or `@ScaledMetric` for custom font sizes:
```swift
@ScaledMetric(relativeTo: .body) static var bodySize: CGFloat = 15
```

### 3.4 Windows: Settings URL Validation + Test Connection

**File:** `transcript-studio-windows/src/pages/SettingsPage.tsx:29-33`

**Change:** Validate URL format and add "Test verbinding" button:
```typescript
const testConnection = async () => {
  try {
    const res = await fetch(`${serverUrl}/health`);
    if (res.ok) setConnectionStatus("success");
  } catch {
    setConnectionStatus("error");
  }
};
```

### 3.5 macOS: URL Validation in Settings

**File:** `TranscriptStudio/Views/SettingsView.swift:95-125`

**Change:** Validate URL scheme (HTTPS) and format before saving.

### 3.6 Windows: HTML Metadata

**File:** `transcript-studio-windows/index.html`

**Change:** Add proper meta tags, replace vite.svg with app icon:
```html
<meta name="description" content="TranscriptStudio - Vergaderopnames en notulen">
<meta name="theme-color" content="#E50074">
<link rel="icon" href="/icon.png" type="image/png">
```

### 3.7 macOS: Profile Loading Timeout

**File:** `TranscriptStudio/Views/RecordingView.swift:122-134`

**Change:** Add timeout and retry button:
```swift
.task {
    do {
        try await withTimeout(seconds: 10) {
            await recordingVM.loadProfiles()
        }
    } catch {
        showProfileLoadError = true
    }
}
```

### 3.8 Windows: Settings Save Error Recovery

**File:** `transcript-studio-windows/src/pages/SettingsPage.tsx`

**Change:** Show error if invalid URL, prevent save of unreachable server.

### 3.9 Windows: Profile System Prompt Validation

**File:** `transcript-studio-windows/src/pages/ProfilesPage.tsx:72-100`

**Change:** Max length 5000 chars, character counter in UI.

### 3.10 macOS: Offline Queue Error Exposure

**File:** `TranscriptStudio/Services/OfflineQueue.swift:105-115`

**Change:** Expose `lastPersistError` to the UI or retry failed persists.

### Phase 3 Verification Checklist
- [ ] Run accessibility audit (axe-core for Windows, Accessibility Inspector for macOS)
- [ ] All icon buttons have descriptive aria-label / accessibilityLabel
- [ ] Tab through all pages with keyboard only (Windows)
- [ ] VoiceOver reads all interactive elements (macOS)
- [ ] Font sizes scale with system settings
- [ ] "Test verbinding" button works in Settings
- [ ] Invalid URL prevented from saving

---

## Phase 4: Performance Optimization

**Priority:** MEDIUM-LOW — Improves user experience
**Scope:** 8 performance issues
**Estimated effort:** 1 session

### 4.1 Windows: Remove Console.log Statements

**File:** `transcript-studio-windows/src/services/api.ts:125,144,356,358`

**Change:** Remove or wrap in dev-only check:
```typescript
if (import.meta.env.DEV) {
  console.log(`[API] ${method} ${path} -> ${response.status}`);
}
```

### 4.2 Windows: Virtual Scrolling for Transcript List

**File:** `transcript-studio-windows/src/pages/TranscriptsPage.tsx`

**Change:** Use `@tanstack/react-virtual` for large lists. Add pagination to API (limit=50).

### 4.3 Windows: Memoize Expensive Components

**Files:** RecordingPage.tsx, HomePage.tsx, TranscriptsPage.tsx

**Change:** Wrap stable event handlers in `useCallback`, derived data in `useMemo`. Wrap list items in `React.memo`.

### 4.4 macOS: Extract AdminView Subsections

**File:** `TranscriptStudio/Views/AdminView.swift`

**Change:** Split 1000+ line view into:
- `AdminOverviewSection.swift`
- `AdminUsersList.swift`
- `AdminInvitationsSection.swift`
- `AdminFeedbackSection.swift`

### 4.5 macOS: Cache Validated Base URL

**File:** `TranscriptStudio/Services/APIService.swift:145-155`

**Change:** Cache the URL result instead of re-parsing on every request:
```swift
private var cachedBaseURL: URL?
private var cachedRawURL: String?

private func validatedBaseURL() throws -> URL {
    let raw = serverURL()
    if raw == cachedRawURL, let cached = cachedBaseURL { return cached }
    // ... validation ...
    cachedBaseURL = url
    cachedRawURL = raw
    return url
}
```

### 4.6 macOS: Live Transcription Race Guard

**File:** `TranscriptStudio/ViewModels/RecordingViewModel.swift:696-724`

**Change:** Add flag to prevent concurrent starts:
```swift
guard !isStartingLiveTranscription else { return }
isStartingLiveTranscription = true
defer { isStartingLiveTranscription = false }
```

### 4.7 Windows: Stale Settings in LLM Service

**File:** `transcript-studio-windows/src/services/llm.ts:14-35`

**Change:** Read settings store directly instead of caching on init.

### Phase 4 Verification Checklist
- [ ] No console.log in production build (check bundle output)
- [ ] Transcript list scrolls smoothly with 500+ items
- [ ] AdminView renders without lag
- [ ] Settings changes reflect immediately in LLM service

---

## Phase 5: Code Quality & Polish

**Priority:** LOW — Nice-to-have improvements
**Scope:** 15 Low issues
**Estimated effort:** 1 session

### 5.1 Windows: Localize Error Messages to Dutch

**Files:** `src/services/crashReporter.ts`, error messages throughout.

### 5.2 Windows: Improve API Error Messages

**File:** `src/services/api.ts:140-155` — Better fallback messages by status code.

### 5.3 Windows: Add Version Check on Startup

**File:** `src/App.tsx` — Call `api.checkVersion()` on mount, show upgrade banner.

### 5.4 Windows: Replace Vite Favicon

**File:** `index.html` — Use actual app icon.

### 5.5 Windows: Remove Hardcoded Localhost URLs

**File:** `src/types.ts:328-330` — Remove Ollama/LM Studio defaults or show config prompt.

### 5.6 Windows: Add Skeleton Loaders

**Files:** AdminPage, TranscriptsPage, HomePage — Show placeholder UI during loads.

### 5.7 macOS: Improve Offline Status Persistence

**File:** `TranscriptStudio/ViewModels/RecordingViewModel.swift:559-572` — Keep message visible until queue processes.

### 5.8 macOS: Add Decoding Error Context to Logs

**File:** `TranscriptStudio/Services/APIService.swift:436-450` — Log actual decoding errors.

### 5.9 macOS: Cache Transcript List

**File:** Add TTL-based cache in APIService for transcript list to reduce API calls.

### 5.10 macOS: Multipart Encoding Cleanup

**File:** `TranscriptStudio/Services/APIService.swift:355-366` — Replace force unwraps with safe Data extension:
```swift
extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
```

### Phase 5 Verification Checklist
- [ ] Error messages display in Dutch
- [ ] Version check shows banner when outdated
- [ ] App icon visible in title bar (not Vite logo)
- [ ] Skeleton loaders during data fetch
- [ ] No force unwraps on `.data(using: .utf8)!`

---

## Execution Order

| Phase | Issues | Priority | Depends On |
|-------|--------|----------|------------|
| 1. Security Hardening | 13 | CRITICAL | — |
| 2. Stability & Error Handling | 16 | HIGH | Phase 1 (CSP must be enabled first) |
| 3. Accessibility & UX | 11 | MEDIUM | — (can run parallel to Phase 2) |
| 4. Performance | 8 | MEDIUM-LOW | Phase 2 (error handling before optimization) |
| 5. Code Quality | 12 | LOW | Any order |

## Files Changed Per Phase

| Phase | Windows Files | macOS Files |
|-------|--------------|-------------|
| 1 | tauri.conf.json, TranscriptsPage.tsx, sse.ts, authStore.ts, api.ts, http.rs, AccountPage.tsx, AdminPage.tsx | RecordingViewModel.swift, TranscriptsView.swift, Models.swift, APIService.swift |
| 2 | RecordingPage.tsx, api.ts, AccountPage.tsx, authStore.ts | RecordingViewModel.swift, AuthViewModel.swift, BiometricService.swift, APIService.swift |
| 3 | All pages (aria-labels), SettingsPage.tsx, ProfilesPage.tsx, index.html | RecordingView.swift, SettingsView.swift, Theme.swift, OfflineQueue.swift |
| 4 | api.ts, TranscriptsPage.tsx, RecordingPage.tsx, HomePage.tsx, llm.ts | AdminView.swift (split), APIService.swift, RecordingViewModel.swift |
| 5 | crashReporter.ts, api.ts, App.tsx, index.html, types.ts, multiple pages | RecordingViewModel.swift, APIService.swift |
