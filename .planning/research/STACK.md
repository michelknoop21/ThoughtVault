# Stack Research — People & Attribution

**Milestone:** People & Attribution (v1.1)
**Researched:** 2026-06-04
**Overall confidence:** HIGH (all critical choices verified via Context7 / official Apple docs / npm)

---

## Summary

Three focused questions: (1) on-device data model + persistence on macOS and Windows, (2) name/alias fuzzy-matching per platform, (3) owner-assignment persistence. No new infrastructure, no sync, no new native plugins. The existing stack handles everything with small, surgical additions.

---

## 1. On-Device Data Model & Persistence

### macOS — SwiftData

**Recommendation: Extend the existing `ModelContainer` with two new `@Model` classes. No new container.**

`LocalTranscriptStore` creates its container explicitly:
```swift
container = try ModelContainer(for: TranscriptRecord.self, configurations: config)
```
SwiftData `ModelContainer` accepts an array of model types. Adding `PersonProfile.self` and `PersonDirectoryEntry.self` to that array is an additive, lightweight schema change. SwiftData performs automatic lightweight migration for new models and new optional properties (verified: Apple docs, `ModelContainer` overview — "the container performs automatic migrations … so it remains consistent with the app's model classes").

**New models (both in `macos/Models/`):**

`PersonProfile.swift` — `@Model final class` for the installing user's self-profile. Fields: `id: String` (@Attribute .unique), `fullName: String`, `aliases: [String]`, `role: String`, `organisation: String`, `meetingTypes: [String]`, `createdAt: Date`, `updatedAt: Date`. Singleton by convention (only one record will exist).

`PersonDirectoryEntry.swift` — `@Model final class` for each known colleague/external. Fields: `id: String` (@Attribute .unique), `fullName: String`, `aliases: [String]`, `role: String`, `organisation: String`, `isInternal: Bool`, `source: String` ("manual" | "calendar" | "transcript"), `createdAt: Date`. No relationship to `TranscriptRecord` at model level — linking is done by storing matched person IDs on the `TranscriptRecord` extensions (see §3).

**Container update in `LocalTranscriptStore`:**
```swift
container = try ModelContainer(
    for: TranscriptRecord.self, PersonProfile.self, PersonDirectoryEntry.self,
    configurations: config
)
```
This is a new schema version. SwiftData's automatic migration handles purely additive changes (new model types, new optional properties). A `SchemaMigrationPlan` is NOT needed for this milestone because no existing field is renamed or removed.

**Concurrency:** `LocalTranscriptStore` is already `@MainActor`. Add `PersonDirectoryStore` as a separate `@MainActor final class` following the exact same pattern — no actor gymnastics, no shared state between them.

**`TranscriptRecord` extension** for attribution (§3): add optional `attributionJson: String?` to `TranscriptRecord` — a JSON-encoded `[String: String]` mapping action-item index → `PersonDirectoryEntry.id`. Optional property = automatic lightweight migration, no migration plan needed.

**What NOT to do on macOS:**
- Do NOT add a CloudKit configuration — this milestone is local-only.
- Do NOT create a second/separate `ModelContainer` for people data — multiple containers add coordination complexity for zero benefit here.
- Do NOT use `@Relationship` between `TranscriptRecord` and `PersonDirectoryEntry` — cross-record relationships in SwiftData require careful cascade configuration and complicate the existing store migration. A JSON attribute on `TranscriptRecord` is simpler and sufficient.
- Do NOT add `CoreData` — SwiftData is the established choice.

### Windows (Tauri) — Zustand + `tauri-plugin-store` (already installed)

**Recommendation: Two new Zustand persist stores backed by `tauri-plugin-store`. No SQLite, no new Rust crates.**

The project already has `tauri-plugin-store = "2"` in `Cargo.toml` and `@tauri-apps/plugin-fs` in `package.json`. The existing `settingsStore.ts` uses `zustand/middleware persist` with `localStorage` (Tauri webview). For people data, use `tauri-plugin-store` as the storage backend instead of `localStorage` — this writes JSON to a named file in the app data directory, which is OS-aware and survives app reinstalls more reliably.

Custom Zustand storage adapter wrapping `tauri-plugin-store` (the pattern is documented in Zustand's `StateStorage` custom storage API, verified via Context7):

```typescript
import { Store } from '@tauri-apps/plugin-store'
import { createJSONStorage, StateStorage } from 'zustand/middleware'

const tauriStorage = (filename: string): StateStorage => ({
  getItem: async (name) => {
    const store = await Store.load(filename)
    return (await store.get<string>(name)) ?? null
  },
  setItem: async (name, value) => {
    const store = await Store.load(filename)
    await store.set(name, value)
    await store.save()
  },
  removeItem: async (name) => {
    const store = await Store.load(filename)
    await store.delete(name)
    await store.save()
  },
})
```

**New stores:**
- `windows/src/stores/personProfileStore.ts` — single `PersonProfile` object, persisted to `person-profile.json` via `tauri-plugin-store`.
- `windows/src/stores/peopleDirectoryStore.ts` — `PersonDirectoryEntry[]`, persisted to `people-directory.json`.

**Type definitions** (add to `windows/src/types.ts`):
```typescript
export interface PersonProfile {
  id: string
  fullName: string
  aliases: string[]
  role: string
  organisation: string
  meetingTypes: string[]
  createdAt: string
  updatedAt: string
}

export interface PersonDirectoryEntry {
  id: string
  fullName: string
  aliases: string[]
  role: string
  organisation: string
  isInternal: boolean
  source: 'manual' | 'calendar' | 'transcript'
  createdAt: string
}
```

**Why not SQLite/rusqlite?** The dataset is small (tens to hundreds of entries at most), never queried relationally, and the Windows app already has zero Rust-side persistence beyond `tauri-plugin-store`. Adding `rusqlite` + migrations to Rust for this is massive over-engineering. Zustand + `tauri-plugin-store` stays consistent with `settingsStore.ts`.

**Why not `localStorage` (default Zustand persist)?** Tauri's webview `localStorage` is wiped when the webview is reset or the app bundle changes. `tauri-plugin-store` writes to a named JSON file in the OS app-data directory — more durable, inspectable, consistent with how Tauri apps are expected to persist data.

**What NOT to do on Windows:**
- Do NOT add `rusqlite` or any SQLite crate — no relational queries needed.
- Do NOT use the third-party `/ferreira-tb/tauri-store` library — the official `@tauri-apps/plugin-store` (already in the project) is sufficient and already permitted.
- Do NOT store people data in the existing `settings-store` key — keep concerns separated.

---

## 2. Name / Alias Fuzzy-Matching

### macOS — NaturalLanguage framework + hand-rolled Jaro-Winkler (zero new dependencies)

**For name extraction from notule HTML:** Use Apple's `NLTagger` with the `.nameType` scheme (available since macOS 10.14, verified stable through macOS 14+). This identifies person-name spans in free text — no dependencies, ships with the OS.

```swift
import NaturalLanguage

func extractPersonNames(from text: String) -> [String] {
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = text
    var names: [String] = []
    tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                         unit: .word, scheme: .nameType,
                         options: [.omitWhitespace, .joinNames]) { tag, range in
        if tag == .personalName {
            names.append(String(text[range]))
        }
        return true
    }
    return names
}
```

**For matching extracted names to `PersonDirectoryEntry`:** Implement Jaro-Winkler similarity inline (< 30 lines of Swift, no SPM dependency). Threshold: 0.85 for a confident match, 0.75–0.85 for a suggested match requiring user confirmation. This handles the main real-world cases: nickname vs full name ("Michel" matching "Michel Knoop"), initials, typos in transcripts.

**Internal/external heuristic:** `isInternal` on `PersonDirectoryEntry` is set at entry-creation time. When `NLTagger` finds an unrecognised name, it goes into a "unmatched" bucket displayed to the user for manual assignment — no auto-classification of unknowns.

**What NOT to add on macOS:**
- Do NOT add `StringMetric.swift` or `FuzzyMatching` as an SPM dependency — Jaro-Winkler is a one-time 25-line implementation. External SPM packages add review burden and update churn.
- Do NOT use `NSLinguisticTagger` — it is deprecated in favour of `NLTagger` since macOS 12.

### Windows (TypeScript) — Fuse.js

**Recommendation: Fuse.js 7.x (latest stable: 7.4.0 as of June 2026, verified via npm).**

Fuse.js is already the obvious choice for this stack: zero runtime dependencies, TypeScript-native, < 10 KB gzipped. Configure it to search over `fullName` and `aliases` fields in the `PersonDirectoryEntry[]` array.

```typescript
import Fuse from 'fuse.js'

const fuse = new Fuse(entries, {
  keys: [
    { name: 'fullName', weight: 2 },
    { name: 'aliases', weight: 1.5 },
  ],
  threshold: 0.35,   // lower = stricter; 0.35 catches initials/nicknames
  includeScore: true,
  useExtendedSearch: false,
})

const results = fuse.search(extractedName)
// results[0].score < 0.35 → confident match; 0.35–0.5 → suggest to user
```

`Fuse` operates in-memory on the `PersonDirectoryEntry[]` array already held in Zustand — no extra DB query, no async. Rebuild the `Fuse` instance when the directory changes (Zustand subscriber or React `useMemo`).

**Installation:**
```bash
cd windows && npm install fuse.js@^7.4.0
```

**What NOT to add on Windows:**
- Do NOT add a full-text search engine (Lunr, MiniSearch) — the dataset is tiny, Fuse.js is sufficient.
- Do NOT call into Rust for fuzzy matching — all data is already in the React layer.

---

## 3. Editable Owner-Assignment Persistence

### macOS

Add one optional property to `TranscriptRecord`:

```swift
// In TranscriptRecord.swift
/// JSON-encoded [actionItemKey: personDirectoryEntryId]
/// actionItemKey = stable string identifying the action item (e.g. its index or a hash of text)
var attributionJson: String?
```

`attributionJson` is decoded/encoded as `[String: String]` in `LocalTranscriptStore` helpers. Automatic lightweight SwiftData migration handles adding an optional property to an existing model.

No new `@Model` type needed. No `@Relationship`. Assignment is edited via a helper on `LocalTranscriptStore`:
```swift
func updateAttribution(taskId: String, attribution: [String: String]) throws
```

### Windows

Extend `Transcript` in `types.ts`:
```typescript
export interface Transcript {
  // ... existing fields ...
  attribution?: Record<string, string>  // actionItemKey → personDirectoryEntryId
}
```

Attribution is part of the `Transcript` object in `transcriptsStore.ts` (which is already `updateTranscript`-able). Persist by calling `updateTranscript` — the store is already persisted if cloud transcripts are local-cached, or written to the `people-directory.json` store if needed. Since attribution is per-transcript and transcripts already live in `transcriptsStore`, store it there via `updateTranscript(id, { attribution })`. No new store needed.

---

## 4. Context Injection into Notule Prompt (`{{PEOPLE_CONTEXT}}`)

**No new library needed.** The existing `buildNotuleUserContent` function in `LLMService.swift` already performs placeholder substitution. Add one branch:

```swift
.replacingOccurrences(of: "{{PEOPLE_CONTEXT}}", with: peopleContext)
```

`peopleContext` is a plain-text block assembled by a new `PeopleContextBuilder` service (a simple `struct` or free function, no actor needed — it only reads from `LocalTranscriptStore` and `PersonDirectoryStore`). Format: structured plain text, e.g.:

```
Aanwezig / bekende deelnemers:
- Michel Knoop (intern, product lead) — aliassen: Michel, MK
- Petra de Vries (extern, klant) — aliassen: Petra
```

For the cloud path: the n8n webhook payload (`transcription.py`, line ~465) receives `profile_id`, `requested_by`, etc. Add `people_context: str` as an additional field. The n8n workflow substitutes `{{PEOPLE_CONTEXT}}` in the prompt template on the workflow side. No new infrastructure, just an extra JSON field in the existing payload.

---

## 5. Complete "New Dependencies" Accounting

| Dependency | Platform | Version | How Added | Why |
|---|---|---|---|---|
| `fuse.js` | Windows/npm | `^7.4.0` | `npm install fuse.js` | Fuzzy name matching in TS |
| `NaturalLanguage` (NLTagger) | macOS | OS-built-in | `import NaturalLanguage` | Name extraction, ships with macOS 14+ |
| `tauri-plugin-store` | Windows | already installed | already in `Cargo.toml` + `package.json` | People data persistence via named JSON file |

**No new Rust crates. No new SPM packages. No new Tauri plugins.**

---

## 6. Explicit "Do NOT Add" List

| What | Reason |
|---|---|
| SQLite / `rusqlite` on Windows | No relational queries; overkill for < 500 rows |
| CloudKit or iCloud sync | Out of scope (privacy/local-first) |
| Second `ModelContainer` on macOS | Coordination complexity for zero gain |
| `@Relationship` between `TranscriptRecord` and `PersonDirectoryEntry` | Cascade rules complicate migrations; JSON attribute is sufficient |
| `SchemaMigrationPlan` for this milestone | Only additive changes (new types, new optional fields) — SwiftData auto-migrates |
| `NSLinguisticTagger` | Deprecated since macOS 12; use `NLTagger` |
| External Swift fuzzy-match SPM package | 25-line Jaro-Winkler is all that's needed |
| Spreker-diarisatie / audio-level speaker ID | Out of scope (PROJECT.md) |
| `localStorage` for people data on Windows | Less durable than `tauri-plugin-store` file-based persistence |
| `ObservableObject` / `Combine` / completion handlers | Forbidden by CLAUDE.md / project conventions |

---

## Sources

- SwiftData `@Model`, `ModelContainer`, migration: https://developer.apple.com/documentation/swiftdata (via Context7 `/websites/developer_apple_swiftdata`)
- SwiftData automatic migration / additive schema: https://developer.apple.com/documentation/swiftdata/modelcontainer/migrationplan (Context7 confirmed: additive changes auto-migrate)
- `NLTagger` / `.nameType` / `.personalName`: https://developer.apple.com/documentation/naturallanguage/nltagger (macOS 10.14+, stable through 14+)
- `tauri-plugin-store` v2 JavaScript API: https://github.com/tauri-apps/plugins-workspace/tree/v2/plugins/store (Context7 `/tauri-apps/plugins-workspace`)
- Zustand `persist` + custom `StateStorage`: https://github.com/pmndrs/zustand/blob/main/docs/reference/integrations/persisting-store-data.md (Context7 `/pmndrs/zustand`)
- Fuse.js v7.4.0: https://www.npmjs.com/package/fuse.js (HIGH confidence — verified current on npm June 2026)
- Fuse.js configuration / token search: Context7 `/krisk/fuse`
