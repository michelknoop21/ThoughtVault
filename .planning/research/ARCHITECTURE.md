# Architecture Research — People & Attribution

**Domain:** Cross-platform meeting-notes app, adding people/role context + action-point attribution
**Researched:** 2026-06-04
**Confidence:** HIGH (based on direct code inspection of all integration points)

---

## System Overview

The new milestone adds three new subsystems (PersonProfile store, PeopleDirectory, AttributionMapper)
and modifies four existing integration points. No existing flow is replaced — everything is additive.

```
┌────────────────────────────────────────────────────────────────────────────┐
│  NEW: People Subsystem (on-device, both platforms)                          │
│  ┌──────────────────┐  ┌───────────────────┐  ┌───────────────────────┐   │
│  │  PersonProfile   │  │  PeopleDirectory  │  │  PeopleContextBuilder │   │
│  │  (self-profile)  │  │  (colleagues +    │  │  (formats             │   │
│  │  SwiftData @Model│  │   externals)      │  │   {{PEOPLE_CONTEXT}}) │   │
│  │  Windows: Zustand│  │  SwiftData @Model │  │  pure function        │   │
│  │  + localStorage  │  │  Windows: Zustand │  └──────────┬────────────┘   │
│  └──────────────────┘  └───────────────────┘             │                │
└──────────────────────────────────────────────────────────│────────────────┘
                                                            │ {{PEOPLE_CONTEXT}}
            ┌───────────────────────────────────────────────┴───────────┐
            │              MODIFIED: Notule Generation                   │
            ├─────────────────────────────┬──────────────────────────────┤
            │  Local path (macOS Swift)   │  Cloud path (FastAPI + n8n)  │
            │                             │                              │
            │  buildNotuleUserContent()   │  transcription.py payload    │
            │  LLMService.swift:59-76     │  + n8n workflow              │
            │                             │  Iq3AAf8Vk8eQ9dcZ           │
            │  ADD: peopleContext param   │  ADD: people_context field   │
            └─────────────────────────────┴──────────────────────────────┘
                              │                          │
                              ▼                          ▼
            ┌─────────────────────────────────────────────────────────────┐
            │              Generated notule HTML                           │
            └──────────────────────────────┬──────────────────────────────┘
                                           │
                                           ▼
            ┌─────────────────────────────────────────────────────────────┐
            │  NEW: AttributionMapper (post-generation step)               │
            │  Scans notule HTML for known names/aliases                   │
            │  → produces [ActionPoint { owner: PersonRef? }]              │
            └──────────────────────────────┬──────────────────────────────┘
                                           │
                                           ▼
            ┌─────────────────────────────────────────────────────────────┐
            │  MODIFIED: TranscriptRecord + Windows equivalent             │
            │  + attributions: [AttributionEntry] (persisted locally)      │
            └──────────────────────────────┬──────────────────────────────┘
                                           │
                                           ▼
            ┌─────────────────────────────────────────────────────────────┐
            │  MODIFIED: NotuleResultView + TranscriptDetailView           │
            │  Owner assignment UI — editable, saved back to store         │
            └─────────────────────────────────────────────────────────────┘
```

---

## Integration Point 1: People-Context Injection

### Where and How

**Local path — `buildNotuleUserContent()` (LLMService.swift:59-76)**

The function already does placeholder substitution for `{{TRANSCRIPTION}}` and
`{{OUTPUT_TEMPLATE}}`. Adding `{{PEOPLE_CONTEXT}}` is a minimal, surgical change.
The new parameter is injected before `{{TRANSCRIPTION}}` to keep untrusted content last
(the existing security comment at line 65 explains this ordering).

Signature change:
```swift
func buildNotuleUserContent(
    notulePrompt: String,
    transcription: String,
    outputTemplate: String?,
    peopleContext: String?     // NEW — nil means no injection
) -> String
```

Injection: replace `{{PEOPLE_CONTEXT}}` with `peopleContext ?? ""` using the same
`replacingOccurrences` pattern. If the profile's `notulePrompt` does not contain
the placeholder (legacy profiles), append a short preamble before the transcription
so old profiles still benefit silently.

Call sites to update:
- `RecordingViewModel.processLocally()` (line ~727) — read from `PersonProfileStore.shared`
  and `PeopleDirectoryStore.shared` before calling `generateNotulen()`
- `RecordingViewModel.regenerateNotuleLocally()` (line ~771) — same

**Cloud path — `transcription.py` webhook payload (line 450-468)**

The existing payload dict has a fixed set of keys. Add one new optional key:

```python
"people_context": payload.people_context or None,  # NEW
```

`TranscribeTextRequest` Pydantic model needs one new field:
```python
people_context: Optional[str] = None
```

The client (macOS `APIService.swift`, Windows `api.ts`) builds the request body —
both need to read from the local people store and include `people_context` in the POST body.

**n8n workflow `Iq3AAf8Vk8eQ9dcZ`**

The workflow receives the webhook payload and constructs the prompt sent to Claude/Ollama.
A new Set or Code node inserts `{{PEOPLE_CONTEXT}}` into the `notule_prompt` string before
passing it to the LLM node. If `people_context` is absent/null, the node is a no-op.
This is a single-node addition — no structural change to the workflow.

**Contract summary:**

| Layer | Change | Backward compatible? |
|-------|--------|---------------------|
| Swift `buildNotuleUserContent` | Add `peopleContext: String?` param | Yes — default nil |
| FastAPI `TranscribeTextRequest` | Add `people_context: Optional[str] = None` | Yes — optional field |
| n8n workflow | New Set/Code node that splices context into prompt | Yes — no-op when absent |
| Windows API call | Add `people_context` to POST body | Yes — server ignores missing |

Spike warranted: verify the n8n workflow node positions before modifying (workflow JSON
`Iq3AAf8Vk8eQ9dcZ` is not in this repo; requires inspection in the n8n UI).

---

## Integration Point 2: Name Matching / Attribution

### Prompt-time vs. Post-generation — Tradeoff Analysis

**Option A: Prompt-time only (tell the LLM to assign owners)**

Inject `{{PEOPLE_CONTEXT}}` and add an instruction like "assign action points to people
from the list; use their exact name as listed." The LLM produces HTML with owner names
inline. No post-processing needed.

Pros: simple, no parsing code, leverages LLM's language understanding.
Cons: LLM hallucination — it may invent names not in the list, use inconsistent casing,
or silently fail to match aliases. No structured data results; owner assignment is buried
in HTML. Cannot support the "editable owner" requirement without parsing anyway.

**Option B: Post-generation HTML parsing (recommended)**

Run a matching pass over the completed notule HTML after generation. A lightweight
`AttributionMapper` scans for known names/aliases in action-point lines and produces
a structured `[AttributionEntry]`.

Pros: deterministic; works even when the LLM ignores the instruction; produces structured
data that can be stored, displayed, and edited independently of the HTML. The LLM's
prompt still gets `{{PEOPLE_CONTEXT}}` to improve name consistency in the text — but the
attribution data does not depend on LLM compliance.

Cons: requires a text-matching algorithm; false positives if names are common words.

**Recommendation: combine both.** Inject `{{PEOPLE_CONTEXT}}` into the prompt (improves
LLM name usage), then run post-generation `AttributionMapper` to produce structured
`[AttributionEntry]`. The HTML is the source of truth for display; attribution entries are
the source of truth for ownership and are stored separately.

### AttributionMapper design

```swift
// macos/Services/AttributionMapper.swift
actor AttributionMapper {
    /// Scans notule HTML for action-point patterns, matches against directory.
    /// Returns one entry per detected action-point mention with a person match.
    func map(html: String, directory: [PersonProfile]) -> [AttributionEntry]
}
```

Matching heuristic (keep simple for Phase 4):
1. Extract text nodes from HTML action-point `<li>` elements (detect via CSS class or
   keyword "actiepunt"/"actie:" pattern).
2. For each text node, scan for any known `name` or `aliases` entry (case-insensitive,
   longest match wins).
3. Score by: exact name > alias > partial. Threshold above which a match is accepted.
4. Unknown names produce an `AttributionEntry` with `personId: nil` — these are shown
   as "Onbekend" in the UI with a prompt to assign.

Spike warranted: the actual action-point HTML structure varies per Profile template. Before
implementing AttributionMapper, inspect two or three real notule outputs to confirm the
CSS/tag structure of action-point lists.

---

## Integration Point 3: Attribution Data Storage

### macOS — TranscriptRecord extension

`TranscriptRecord` is a SwiftData `@Model`. Add two fields:

```swift
// macos/Models/TranscriptRecord.swift
@Model
final class TranscriptRecord {
    // ... existing fields unchanged ...

    /// Structured attribution entries produced after notule generation.
    /// Stored as JSON-encoded Data; SwiftData does not support custom Codable arrays natively.
    var attributionsData: Data?

    /// Helper: decoded attributions (not persisted, computed from attributionsData)
    var attributions: [AttributionEntry] {
        get { (try? JSONDecoder().decode([AttributionEntry].self, from: attributionsData ?? Data())) ?? [] }
        set { attributionsData = try? JSONEncoder().encode(newValue) }
    }
}
```

`AttributionEntry` is a plain `Codable` struct in `Models.swift`:

```swift
struct AttributionEntry: Codable, Identifiable {
    let id: String           // UUID, stable across edits
    let actionPointText: String
    var personId: String?    // references PersonProfile.id; nil = unmatched
    var personDisplayName: String?   // denormalized for display resilience
    var isConfirmedByUser: Bool
}
```

SwiftData migration: adding nullable columns to an existing `@Model` is additive and does
not require a manual migration schema. SwiftData handles this via lightweight migration
(verified pattern in existing codebase — `source` field was added this way).

### Windows — Zustand + localStorage persistence

Windows has no SwiftData equivalent. The existing pattern for persisted stores uses
Zustand `persist` middleware with the browser `localStorage` (confirmed in `authStore.ts`,
`settingsStore.ts`, `profilesStore.ts`).

New `personProfileStore.ts` and `peopleDirectoryStore.ts` follow the same pattern:
```typescript
// windows/src/stores/personProfileStore.ts
interface PersonProfileStore {
  selfProfile: PersonProfile | null;
  setSelfProfile: (p: PersonProfile) => void;
}
// persisted via Zustand persist middleware to localStorage
```

Attribution entries live in `transcriptsStore.ts` alongside each transcript:
```typescript
interface Transcript {
  // existing fields ...
  attributions?: AttributionEntry[];
}
```

Saved via `updateTranscript()` action. No new IPC command needed — everything is in the
webview's localStorage, consistent with how Windows handles all client-state today.

---

## Integration Point 4: Attendee Seed for PeopleDirectory

### Current state

`MicrosoftGraphService.getUpcomingEvents()` (line 273) already requests
`organizer,attendees` in the `$select` query but the response decoder (`GraphCalendarResponse`)
discards them — they are not mapped to `CalendarEvent`. The JSON data is available; it is
just never read.

### Minimal change to capture attendees

1. Add `attendees` and `organizer` to the `GraphCalendarEvent` Codable struct.
2. Add `attendees: [CalendarAttendee]?` to `CalendarEvent` struct.
3. In `CalendarService`, surface attendees via `upcomingMeetings[x].attendees`.
4. When the user links a recording to a meeting (existing flow), offer a "Voeg deelnemers
   toe aan directory" prompt — a one-time optional seed, not an automatic import.

This is a read-only structural extension. No new Graph API call; no new token scope.

---

## New vs. Modified Components

### New — macOS/iOS

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| `PersonProfile` | `@Model` SwiftData | `macos/Models/PersonProfile.swift` | Self-profile + directory entry (unified model) |
| `AttributionEntry` | `Codable` struct | `macos/Models/Models.swift` | Single action-point owner record |
| `PersonDirectoryService` | `actor` | `macos/Services/PersonDirectoryService.swift` | CRUD over SwiftData `PersonProfile` entries |
| `AttributionMapper` | `actor` | `macos/Services/AttributionMapper.swift` | Post-generation name matching |
| `PeopleContextBuilder` | free function | `macos/Services/PeopleContextBuilder.swift` | Formats `{{PEOPLE_CONTEXT}}` string from directory |
| `SelfProfileOnboardingStep` | SwiftUI View | `macos/Views/Components/SelfProfileOnboardingStep.swift` | New step inserted into `OnboardingView` |
| `PeopleDirectoryView` | SwiftUI View | `macos/Views/PeopleDirectoryView.swift` | Directory CRUD screen |
| `AttributionEditorView` | SwiftUI View | `macos/Views/Components/AttributionEditorView.swift` | Inline owner assignment widget |

### Modified — macOS/iOS

| Component | File | Change |
|-----------|------|--------|
| `buildNotuleUserContent()` | `LLMService.swift` | Add `peopleContext: String?` param + substitution |
| `RecordingViewModel.processLocally()` | `RecordingViewModel.swift` | Read people context, pass to notule generation |
| `RecordingViewModel.regenerateNotuleLocally()` | `RecordingViewModel.swift` | Same |
| `TranscriptRecord` | `TranscriptRecord.swift` | Add `attributionsData: Data?` |
| `CalendarEvent` + `GraphCalendarEvent` | `CalendarService.swift` / `MicrosoftGraphService.swift` | Add attendees fields |
| `OnboardingView` | `OnboardingView.swift` | Insert self-profile step (new `OnboardingStep` case) |
| `NotuleResultView` | `NotuleResultView.swift` | Embed `AttributionEditorView` in notule tab |
| `TranscriptDetailView` | `TranscriptsView.swift` | Embed `AttributionEditorView` in notule tab |
| `SettingsView` | `SettingsView.swift` | Add "Mijn profiel" + "Mensen" settings sections |
| `ThoughtVaultApp` | `ThoughtVaultApp.swift` | Inject `PersonDirectoryService` into environment |

### New — Windows

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| `personProfileStore.ts` | Zustand store | `windows/src/stores/` | Self-profile, persisted |
| `peopleDirectoryStore.ts` | Zustand store | `windows/src/stores/` | Directory entries, persisted |
| `PeopleDirectoryPage.tsx` | Page | `windows/src/pages/` | Directory CRUD screen |
| `AttributionEditor.tsx` | Component | `windows/src/components/transcripts/` | Owner assignment widget |
| `peopleContextBuilder.ts` | Service | `windows/src/services/` | Formats `{{PEOPLE_CONTEXT}}` string |

### Modified — Windows

| Component | File | Change |
|-----------|------|--------|
| `api.ts` | `windows/src/services/api.ts` | Include `people_context` in transcribe-text POST body |
| `types.ts` | `windows/src/types.ts` | Add `PersonProfile`, `AttributionEntry`, `Transcript.attributions?` |
| `transcriptsStore.ts` | `windows/src/stores/` | Store/update attributions alongside transcripts |
| Onboarding wizard | `windows/src/components/onboarding/` | Add self-profile step |
| Transcript detail component | `windows/src/components/transcripts/` | Embed `AttributionEditor` |

### Modified — Backend

| Component | File | Change |
|-----------|------|--------|
| `TranscribeTextRequest` | `models.py` | Add `people_context: Optional[str] = None` |
| Webhook payload builder | `transcription.py:450-468` | Add `"people_context": payload.people_context or None` |
| n8n workflow `Iq3AAf8Vk8eQ9dcZ` | n8n UI | Add node to splice `people_context` into prompt before LLM call |

---

## Data Flow: Full Local Path (macOS)

```
User stops recording
        ↓
RecordingViewModel.processLocally()
        ↓
PersonDirectoryService.shared.buildContext()
        → PeopleContextBuilder.format(selfProfile, directory) → String
        ↓
LLMService.generateNotulen(
    transcription: ...,
    systemPrompt: ...,
    notulePrompt: ...,      ← contains {{PEOPLE_CONTEXT}}
    outputTemplate: ...,
    peopleContext: contextString   ← NEW
)
        ↓
buildNotuleUserContent() substitutes {{PEOPLE_CONTEXT}} → prompt sent to LLM
        ↓
HTML returned
        ↓
AttributionMapper.map(html, directory)  → [AttributionEntry]
        ↓
LocalTranscriptStore.shared.finalizeNotule(
    taskId: ..., html: ..., title: ..., attributions: ...   ← NEW
)
        ↓
TranscriptRecord.attributionsData persisted in SwiftData
```

## Data Flow: Cloud Path (macOS + Windows)

```
User stops recording / submits on-device transcription
        ↓
APIService / api.ts: POST /transcribe-text
    body includes people_context: String?   ← NEW
        ↓
transcription.py: payload dict includes "people_context"
        ↓
n8n workflow: Set/Code node splices people_context into notule_prompt
        ↓
Claude / Ollama generates HTML
        ↓
HTML returned via SSE / callback to client
        ↓
Client runs AttributionMapper.map(html, localDirectory)
        ↓
Attributions persisted to local store (TranscriptRecord / transcriptsStore)
```

Note: attribution mapping always runs on the client after receiving the HTML —
the backend never returns structured attribution data. This keeps personal directory
data local and avoids a new backend persistence concern.

---

## Architectural Patterns

### Pattern 1: Additive placeholder substitution

**What:** `{{PEOPLE_CONTEXT}}` follows the same pattern as the existing `{{TRANSCRIPTION}}`
and `{{OUTPUT_TEMPLATE}}`. The `buildNotuleUserContent()` function is the single source of
truth for all prompt assembly on the local path.

**When to use:** Always for new prompt variables. Do not concatenate context inline at
call sites — route through `buildNotuleUserContent()`.

**Trade-offs:** Profile `notulePrompt` strings need the placeholder to benefit. Legacy
profiles without it still get a fallback prepend. New milestone profiles should include it.

### Pattern 2: Client-side post-processing after LLM output

**What:** `AttributionMapper` runs after generation on both paths. The LLM produces HTML;
the client extracts structured data from it.

**When to use:** Whenever you need structured data from LLM output but cannot trust the
LLM to reliably emit structured format. Separates "what was generated" from "what was
interpreted."

**Trade-offs:** Requires HTML parsing. Fragile if the template changes radically. Mitigated
by inspecting a few real outputs before implementing (spike).

### Pattern 3: Denormalized display name in AttributionEntry

**What:** `AttributionEntry` stores both `personId` and `personDisplayName`. If the user
later deletes a person from the directory, the display name is still readable in old
transcripts.

**When to use:** Any time you store a reference to a user-editable directory entry in a
persistent record that must remain readable independently.

**Trade-offs:** Name changes in the directory are not retroactively reflected. Acceptable
here — the transcript is a historical record.

---

## Anti-Patterns

### Anti-Pattern 1: Putting PersonProfile inside the existing Profile model

**What people do:** Reuse `Profile` (notule-style template) to hold personal info.
**Why it's wrong:** `Profile` = notule style. Mixing them would corrupt the profile picker,
the backend API, and all prompt-building logic.
**Do this instead:** New `PersonProfile` model, new service, new UI sections. Zero overlap.

### Anti-Pattern 2: Sending the full directory to the backend

**What people do:** POST the entire local people directory to the backend with every
transcription to enable server-side attribution.
**Why it's wrong:** Violates the privacy/local-first constraint. Personal data should not
leave the device.
**Do this instead:** Format `{{PEOPLE_CONTEXT}}` as a short anonymization-friendly text
snippet (name + role only, no email/phone). The snippet travels inside the prompt — same
risk profile as the transcription itself, which the user already accepts in cloud mode.

### Anti-Pattern 3: Running AttributionMapper inside the LLM streaming callback

**What people do:** Try to parse attribution incrementally as HTML chunks arrive.
**Why it's wrong:** HTML is not valid until the stream is complete; chunk boundaries are
arbitrary.
**Do this instead:** Run `AttributionMapper.map()` once after `generateNotulen()` returns
the complete string.

### Anti-Pattern 4: Two separate SwiftData models for self-profile and directory entries

**What people do:** Create `SelfProfile` and `DirectoryPerson` as separate `@Model` types.
**Why it's wrong:** They share identical fields (name, aliases, role, org, intern/extern);
self is just `isSelf = true`. Maintenance burden doubles with no benefit.
**Do this instead:** Single `PersonProfile @Model` with a `isSelf: Bool` flag. Query
`isSelf == true` for self-profile, `isSelf == false` for directory. Max one `isSelf` record
enforced at the service layer.

---

## Build Order (Respecting Dependencies)

```
Phase 1 — PersonProfile model + self-profile onboarding
    Deliverables: PersonProfile @Model, PersonDirectoryService, SelfProfileOnboardingStep,
                  Settings section for editing, Windows personProfileStore + UI
    Dependencies: none — pure new model + UI
    Gate: self-profile is saved on-device, readable, editable, survives restart

Phase 2 — PeopleDirectory + attendee seed
    Deliverables: directory CRUD UI, B-01/B-02/B-03, CalendarEvent.attendees surface
    Dependencies: Phase 1 (PersonProfile model reused for directory entries)
    Gate: add/edit/delete person, seed from calendar event, survives restart

Phase 3 — Context injection (both paths)    *** spike first ***
    Deliverables: PeopleContextBuilder, buildNotuleUserContent() change, backend payload
                  change, n8n workflow node
    Dependencies: Phase 1 (need a self-profile to inject), Phase 2 (directory entries)
    Spike: inspect n8n workflow Iq3AAf8Vk8eQ9dcZ node structure before implementing;
           test with empty directory (no-op) before testing with populated one
    Gate: notule generated with people context; old profiles without placeholder still work

Phase 4 — Attribution mapping + editable toewijzing    *** highest uncertainty ***
    Deliverables: AttributionMapper, AttributionEntry model, TranscriptRecord extension,
                  AttributionEditorView in both NotuleResultView + TranscriptDetailView,
                  Windows equivalents
    Dependencies: Phase 3 (need real notule HTML with context to test matcher),
                  Phase 1+2 (need directory to match against)
    Spike: inspect 3-5 real notule HTML outputs to confirm action-point tag/class structure
           before writing the matcher
    Gate: owner shown per action point, editable, persisted, survives app restart;
          both viewer paths (NotuleResultView + TranscriptDetailView) show consistent UI
```

**Ordering rationale:**

- Phase 1 first because `PersonProfile` is the foundation — both directory and context
  injection depend on it. Model-first avoids rework in later phases.
- Phase 2 before Phase 3 so context injection can be tested with real people, not just
  the self-profile stub.
- Phase 3 before Phase 4 because the attribution mapper needs real LLM output that was
  generated with people context to be representative. Testing the matcher on prompts that
  had no context will produce misleading results.
- Phase 4 last because it has the highest uncertainty (HTML structure is LLM-dependent,
  UI in two divergent views) and depends on all prior phases being correct.

---

## Scaling Considerations

This feature is local-only by design. The only scaling concern is the `{{PEOPLE_CONTEXT}}`
string size as the directory grows.

| Directory size | Context string approach |
|----------------|------------------------|
| 0-20 people | Full list: name + role for everyone |
| 20-100 people | Filter to meeting attendees first (if calendar link available); else full list |
| 100+ people | Limit to 50 most-recently-used + always include self; flag in UI |

The LLM context window is the constraint. Ollama/local models vary (8k-128k). Keep
`PeopleContextBuilder` responsible for truncation; add a `maxEntries: Int` param defaulting
to 50. This is not needed until Phase 3 and can be deferred to Phase 4 if the realistic
user base stays under 30 people.

---

## Sources

- Direct code inspection: `macos/Services/LLMService.swift:53-76` (prompt assembly)
- Direct code inspection: `macos/ViewModels/RecordingViewModel.swift:646-753` (local path)
- Direct code inspection: `macos/Models/TranscriptRecord.swift` (SwiftData model)
- Direct code inspection: `macos/Services/MicrosoftGraphService.swift:260-324` (Graph events, attendees discarded)
- Direct code inspection: `macos/Services/CalendarService.swift` (CalendarEvent struct, no attendees field)
- Direct code inspection: `thoughtvault-backend/src/.../routes/transcription.py:450-468` (webhook payload)
- Direct code inspection: `windows/src/types.ts`, `windows/src/stores/transcriptsStore.ts` (Windows persistence)
- `.planning/codebase/ARCHITECTURE.md` + `STRUCTURE.md` (verified 2026-06-03)
- `.planning/MILESTONE-CONTEXT.md`, `.planning/PROJECT.md` (milestone scope)

---

*Architecture research for: People & Attribution milestone, ThoughtVault v1.1*
*Researched: 2026-06-04*
