# Testing Patterns

**Analysis Date:** 2026-06-03

---

## Platform Overview

Testing is split across two platforms with different frameworks:
- **macOS** — Swift Testing (modern) + XCTest (legacy)
- **Windows** — Vitest

---

## macOS — Swift Testing

### Framework

**Primary runner:** Swift Testing (`import Testing`)
**Legacy tests:** XCTest (`import XCTest`) — one file still uses XCTest assertions
**Config:** Xcode scheme `ThoughtVault.xcscheme`, test target `ThoughtVaultTests`

**Run commands:**
```bash
# All tests
xcodebuild test -project ThoughtVault.xcodeproj -scheme ThoughtVaultTests

# (No watch mode available outside Xcode)
```

### Test File Organization

**Location:** `ThoughtVaultTests/` at repo root (separate from source)

**Files:**
- `ThoughtVaultTests.swift` — XCTest-style, core model decoding (legacy)
- `AuthViewModelTests.swift` — Swift Testing, `@Suite`-based
- `TranscriptDecoderTests.swift` — Swift Testing, JSON decode/encode coverage
- `TranscriptsViewModelTests.swift` — Swift Testing, ViewModel behavior

**Naming:** `<TypeUnderTest>Tests.swift`

### Test Structure (Swift Testing)

```swift
import Testing
import Foundation
@testable import ThoughtVault

@Suite("AuthViewModel Tests")
struct AuthViewModelTests {

    // MARK: - <Feature Group>

    @Test("Descriptive sentence describing what is expected")
    @MainActor
    func descriptiveFunctionName() {
        // Arrange
        let vm = AuthViewModel()
        // Act + Assert
        #expect(vm.isAuthenticated == false)
    }
}
```

**Key patterns:**
- `@Suite("Human-readable suite name")` on the struct
- `@Test("Full sentence describing expected behavior")` on each test function
- `#expect(...)` for assertions — not `XCTAssert*`
- `@MainActor` on any test that touches `@Observable` ViewModels
- `async` test functions for async operations: `@Test(...) @MainActor func name() async { ... }`
- `throws` test functions for Codable decode tests: `func name() throws { ... }`

### Setup and Teardown

No `setUp`/`tearDown` methods used. Setup is inline; cleanup uses `defer`:
```swift
@Test("...")
@MainActor
func someTest() {
    KeychainService.shared.save("test-token", for: "authToken")
    defer { KeychainService.shared.delete(for: "authToken") }

    let vm = AuthViewModel()
    #expect(vm.isAuthenticated == true)
}
```

### MARK Sections

Tests are grouped by `// MARK: - <Feature>` comments within each suite:
```swift
// MARK: - Initial State
// MARK: - Logout
// MARK: - Error State
// MARK: - 2FA State
```

### Mocking

**No mock framework used.** Tests interact with real implementations where possible:
- `KeychainService.shared` is used directly (real Keychain in test environment)
- `UserDefaults.standard` is mutated inline with `defer` cleanup to restore original values
- Network errors are triggered by setting an unreachable server URL

**Server URL override pattern for network tests:**
```swift
let originalURL = UserDefaults.standard.string(forKey: "serverURL")
UserDefaults.standard.set("https://localhost:1", forKey: "serverURL")
defer {
    if let url = originalURL {
        UserDefaults.standard.set(url, forKey: "serverURL")
    } else {
        UserDefaults.standard.removeObject(forKey: "serverURL")
    }
}
```

### Test Data

**Inline JSON literals** for decoder tests:
```swift
let json = """
{
    "id": "abc-123",
    "title": "Testgesprek",
    "date": "2026-03-01T10:00:00.000Z",
    "tags": ["vergadering"]
}
""".data(using: .utf8)!

let transcript = try JSONDecoder().decode(Transcript.self, from: json)
```

**Direct struct initialization** for ViewModel tests:
```swift
vm.transcripts = [
    Transcript(id: "1", title: "Vergadering A", tags: ["werk"]),
    Transcript(id: "2", title: "Gesprek B", tags: ["privé"]),
]
```

### Async Testing

```swift
@Test("Error message is cleared on new login attempt")
@MainActor
func errorMessageClearedOnLogin() async {
    let vm = AuthViewModel()
    await vm.login(email: "test@test.nl", password: "wachtwoord")
    #expect(vm.isLoading == false)
}
```

Brief delays for notification propagation:
```swift
try? await Task.sleep(for: .milliseconds(50))
```

### What Is Tested (macOS)

- JSON decode/encode roundtrips for all core models (`Transcript`, `TranscriptTask`, `Profile`, `TranscriptsResponse`)
- `TaskStatus` computed properties (`isActive`, `progress`)
- `UploadFailureReason.isRetryable`
- `AuthViewModel` initial state, logout idempotency, 2FA state, error clearing
- `TranscriptsViewModel` filtering (text, tag, combined), sorting, tag deduplication, local deletion, pagination defaults

### What Is NOT Tested (macOS)

- `RecordingViewModel` — no test file (largest ViewModel, 1309 lines)
- `APIService` — no integration/unit tests
- All Services (`AudioRecorder`, `LLMService`, `KeychainService`, etc.)
- All SwiftUI Views — no UI tests
- No snapshot tests, no performance tests

---

## Windows — Vitest

### Framework

**Runner:** Vitest `^4.1.0`
**Config:** Inline in `windows/vite.config.ts` (no separate `vitest.config.*` file detected; vitest picks up vite config)
**No `test` script** defined in `windows/package.json` — run via:

```bash
cd windows && npx vitest run            # Run all tests
cd windows && npx vitest               # Watch mode
cd windows && npx vitest --coverage    # Coverage (not configured)
```

### Test File Organization

**Location:** Co-located under `windows/src/services/__tests__/`

**Files:**
- `api.upload.test.ts` — covers `uploadRecording` and `uploadRecordingWithProgress`
- `offlineQueue.test.ts` — covers offline queue retry policy

**Naming:** `<module>.test.ts`

### Test Structure

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";

describe("uploadRecording", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorageMap.clear();
    mockGetState.mockReturnValue({ token: "test-token-123" });
  });

  it("calls proxy_upload with correct arguments", async () => {
    mockInvoke.mockResolvedValueOnce({ status: 200, body: JSON.stringify({ task_id: "task-abc" }), headers: {} });
    const result = await api.uploadRecording("/path/test.wav", "profile-1", "combined");
    expect(mockInvoke).toHaveBeenCalledWith("proxy_upload", { ... });
    expect(result).toEqual({ task_id: "task-abc" });
  });
});
```

### Mocking

**Framework:** `vi` from Vitest

**All external dependencies are mocked at the module level before imports:**

```typescript
// Mock Tauri invoke
const mockInvoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => mockInvoke(...args),
}));

// Mock Zustand store (getState pattern)
const mockGetState = vi.fn();
vi.mock("../../stores/authStore", () => ({
  useAuthStore: { getState: () => mockGetState() },
}));

// Mock Tauri plugin
vi.mock("@tauri-apps/plugin-store", () => ({
  Store: {
    load: async () => ({
      get: async (key: string) => memory.get(key),
      set: async (key: string, value: unknown) => { memory.set(key, value); },
      save: async () => {},
    }),
  },
}));

// Import after mocks
import { api } from "../api";
```

**localStorage mock:** In-memory `Map<string, string>` stubbed via `vi.stubGlobal("localStorage", {...})`.

**What to mock:**
- All Tauri APIs (`@tauri-apps/api/core`, `@tauri-apps/plugin-store`, `@tauri-apps/plugin-fs`)
- Zustand stores accessed via `getState()` in services
- `localStorage`

**What NOT to mock:**
- The module under test itself
- Pure utility functions (tested directly)

### Fake Timers

Used for retry/backoff tests:
```typescript
vi.useFakeTimers();
vi.setSystemTime(new Date("2026-04-28T10:00:00Z"));
// ... run processQueue() ...
vi.setSystemTime(new Date("2026-04-28T10:00:31Z")); // advance past backoff
```
Always restored in `afterEach`:
```typescript
afterEach(() => {
  vi.useRealTimers();
});
```

### Reset Pattern

```typescript
beforeEach(() => {
  vi.clearAllMocks();
  localStorageMap.clear();
  memory.clear();
  uploadMock.mockReset();
  Object.values(queueStoreState).forEach((fn) => fn.mockReset?.());
});
```

### What Is Tested (Windows)

- `api.uploadRecording`: correct `invoke` args, HTTP error mapping, Rust error propagation, empty file, invalid JSON response, unauthenticated token, custom server URL
- `api.uploadRecordingWithProgress`: progress callback, abort signal, Rust error propagation, HTTP error
- `offlineQueue` retry policy: 422 → no retry (permanent fail), 401 → retry with backoff, network error → exponential backoff (30s → 2m → ...), MAX_RETRIES (5) → permanent fail, legacy items without `next_retry_at` processed immediately

### What Is NOT Tested (Windows)

- React components (no component tests)
- Zustand stores directly
- `sse.ts`, `meetingNotifications.ts`, `crashReporter.ts`, `microsoftGraph.ts`
- Pages and hooks
- No E2E tests

---

## Coverage

**macOS:** No coverage enforcement configured. No targets defined.

**Windows:** Coverage not configured (no `--coverage` in scripts, no `c8`/`istanbul` setup).

---

## Test Types Summary

| Type | macOS | Windows |
|------|-------|---------|
| Unit (models/logic) | Yes — `TranscriptDecoderTests`, `ThoughtVaultTests` | Partial — service layer only |
| ViewModel | Yes — `AuthViewModelTests`, `TranscriptsViewModelTests` | No |
| Service/API | No | Yes — `api.upload.test.ts` |
| Queue/retry | No | Yes — `offlineQueue.test.ts` |
| UI/Snapshot | No | No |
| E2E | No | No |

---

*Testing analysis: 2026-06-03*
