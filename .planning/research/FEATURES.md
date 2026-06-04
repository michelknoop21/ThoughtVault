# Feature Research — People & Attribution

**Domain:** Meeting notes / action-item attribution with people-context
**Researched:** 2026-06-04
**Confidence:** MEDIUM-HIGH (real-tool observations + official docs; no access to proprietary UX internals)

---

## Scope

This research covers only the four NEW feature categories (A–D) of the People & Attribution milestone. Existing features (recording, transcription, notule generation, profiles, auth, calendar) are treated as given infrastructure.

---

## A. Self-Profiling Onboarding Step

### What it is in the real world

Apps like HubSpot, Mailchimp, Lovable, and Arcade ask 2–4 strategic questions at first run — role, company, primary goal — then route the user into a tailored experience. The pattern is called "progressive profiling": collect the minimum upfront, prompt completion later. Duolingo's onboarding is the extreme example: defer account creation until after first value delivery.

For meeting-notes tools specifically, self-profiling serves a different purpose than segmentation: it provides the LLM with a stable "perspective anchor" — who is the person generating notes, so pronouns, first-person references, and action-item self-assignments can be resolved correctly. No competing tool ships this concept explicitly (most assume shared/team accounts). TranscriptStudio's single-user-per-install model makes this a genuine differentiator.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Name + display name field | Any personalized app collects this | LOW | Used in greeting, injected in prompt |
| Skippable at first run | Users resist mandatory gates before seeing value | LOW | Show "fill in later" clearly; never block recording |
| Editable in Settings | Users change roles; must not require reinstall | LOW | Dedicated Settings section, both platforms |
| Persists across sessions | Profile should not reset | LOW | SwiftData / Tauri store |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Aliases / "how you are addressed" | LLM can resolve "Michel", "dhr. Knoop", "de voorzitter" to the same person | MEDIUM | Comma-separated list; 2–4 aliases is enough |
| Typical meeting types | Tells LLM what context to expect ("board review", "client intake") | LOW | Free text or multi-select; feeds prompt as soft context |
| Role + organization | Enables intern/extern determination for other attendees | LOW | Single text fields; no org-chart needed |
| Inline prompt-preview ("your profile will be used like this") | Builds trust in what data is used for | LOW | Optional tooltip/example in onboarding |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Photo / avatar upload | "Feels like a real profile" | No product value for LLM attribution; privacy exposure; complexity | Skip entirely |
| Org-chart / reporting structure | Power-user request | Backend sync required; irrelevant for single-install local use | Roles field + directory is sufficient |
| Mandatory profile before recording | Completeness feels good | Blocks power users; destroys first-run experience | Always skippable; soft nudge after first notule |
| LinkedIn/calendar account import for self | Auto-fill convenience | Privacy-invasive; over-engineered for 5 fields | Just ask the 5 questions directly |
| Progressive profile completion prompts mid-flow | Seen in SaaS best practices | Distracting in a recording/notes app context | One-time badge in Settings is sufficient |

### Behavior description

User opens app for first time. After existing permissions onboarding (microphone, calendar), a new step appears: "Stel jezelf even voor" — 1 screen, 4 fields (naam, functie/rol, organisatie, aanspreekvormen), plus meeting-types as optional chips. "Overslaan" skips to main UI. Profile stored locally. Settings > Persoonlijk profiel is the edit entrypoint post-onboarding.

### Dependencies on existing features

- Integrates into existing `OnboardingView` flow (step after calendar permission)
- Settings section already exists; adds a new row/screen
- `PersonProfile` model is new, no collision with existing `Profile` (notule-style)

---

## B. People Directory (Colleagues + Known Externals)

### What it is in the real world

Notion's People Directory and Fellow's attendee model both maintain a workspace-level contact list. Fireflies and Otter sync meeting participants to CRM (Salesforce, HubSpot) — treating every new attendee email as a potential contact record. The key insight from competitive analysis: **email domain is the universal internal/external signal** — tools like Otter, Jiminny, and Practifi all define "internal" as "same email domain as the installer's organization." Multi-domain orgs are the edge case.

For TranscriptStudio, the directory is purely local. Calendar attendees (Microsoft Graph `attendees`/`organizer`) are already fetched but discarded — this is the free seed source.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Add person manually (name, role, org) | Basic CRUD | LOW | Single form, both platforms |
| Edit and delete entries | Basic CRUD | LOW | Swipe-to-delete macOS; context menu Windows |
| Aliases per person | Same as self-profile; "Jan", "de heer Bakker", "JB" | LOW | Same alias model as PersonProfile |
| Internal/external flag | Core to attribution quality | LOW | Toggle or inferred from org matching |
| Name + org visible in directory list | Scannable overview | LOW | Simple list view |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Auto-seed from calendar attendees | Zero-friction first population; attendees already fetched | MEDIUM | Read `attendees`/`organizer` from Graph event; show "add to directory?" prompt |
| Organization-based intern/extern inference | If person's org matches user's org in PersonProfile → internal; otherwise external | LOW | Simple string match; user can override |
| Meeting-history association | "Jan appeared in 3 previous meetings" | HIGH | Requires retrospective transcript scan; defer |
| Duplicate detection on import | Prevents "Jan Bakker" + "J. Bakker" as two entries | MEDIUM | Fuzzy name match before insert; show merge prompt |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| macOS Contacts / CardDAV sync | Power users want one source of truth | Privacy: contacts access is sensitive permission; overkill for 20–50 known people | Manual add + calendar seed covers 95% of cases |
| Cloud sync of directory across devices | "Available everywhere" | Requires backend; breaks local-first; out of scope | Explicit out of scope |
| Auto-create person from every transcript mention | Automatic growth | Generates noise (one-off mentions, company names, artifacts); hard to clean up | Only seed from structured calendar attendees |
| Profile photos | Visual richness | No product value for attribution; storage overhead | Skip |
| Directory search/filter at v1 | Scales well | At <50 people, alphabetical list is fine | Add search only when user feedback requests it |

### Behavior description

Directory accessed from Settings > Contacten. List view: name, role/org, intern/extern chip. Tap to edit. "Toevoegen" FAB opens form. When a meeting is transcribed and calendar attendees were fetched, a banner in the notule view: "3 deelnemers niet in uw directory — toevoegen?" with per-attendee accept/skip. Internal/extern inferred automatically if org matches PersonProfile.org; user can flip the toggle per entry.

### Dependencies on existing features

- Calendar integration (Microsoft Graph) already fetches `attendees` — seed hook goes here
- Both platforms need equivalent storage: SwiftData entity `PersonEntry` (macOS), Tauri store / SQLite (Windows)
- Attendee data currently discarded in the meeting-fetch path — add retention there

---

## C. Context Injection into Notule Generation

### What it is in the real world

The Gladia pipeline guide describes the canonical pattern: inject a bounded participant list into the LLM prompt so name resolution happens against known people rather than via hallucination. The schema they recommend includes `owner_speaker_id` (mapped to a named participant) and a `confidence` score for surfacing uncertain attributions. AssemblyAI's summarization guide confirms: meeting context (participant names, roles) in the system prompt yields significantly more accurate action-item attribution than prompt-less extraction.

Fireflies' approach is CRM-side: push attributed action items to Salesforce/HubSpot contacts. TranscriptStudio's approach must be prompt-side (no CRM), making the injected people-context the only signal.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Self-profile injected into prompt | Without it, "I" in transcript stays unresolved | LOW | `{{PEOPLE_CONTEXT}}` placeholder already planned |
| Known attendees list in prompt | Enables name→person matching in LLM | LOW | Serialize directory entries relevant to the meeting |
| Internal/extern flag per person in prompt | LLM can then mark action items as internal/external task | LOW | Include with each person entry |
| Both local (LLMService) and cloud (n8n) paths | Feature parity required | MEDIUM | Two injection points; n8n payload contract change |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Prompt instructs LLM to output structured owner field | Structured output enables D (mapping) without regex | MEDIUM | LLM returns `[ACTIE:eigenaar=Jan Bakker]` or JSON block |
| Confidence signal in LLM output | Surfaces uncertain attributions for user review | HIGH | Requires prompt engineering + output parsing; spike needed |
| Prompt explains alias list per person | "Jan Bakker, ook bekend als: Jan, JB, dhr. Bakker" | LOW | Trivial to serialize; high value for matching |
| Meeting-type context in prompt | "Dit is een klantgesprek" changes tone and attribution assumptions | LOW | From PersonProfile.meetingTypes |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full directory (all people) in every prompt | "More context = better results" | Tokens cost money; degrades quality with irrelevant noise; privacy exposure | Inject only attendees for this specific meeting + self-profile |
| Auto-detect attendees from transcript without directory | Fallback when no calendar | Creates new unresolved "ghost" people; low quality | Warn user "geen deelnemerslijst beschikbaar" and skip attribution |
| Real-time streaming attribution during transcription | Fast feedback | Transcript not complete during streaming; attribution quality suffers | Post-processing only, after full transcript |

### Behavior description

When user generates a notule, `LLMService.buildNotuleUserContent` constructs a `{{PEOPLE_CONTEXT}}` block: first the self-profile (name, role, aliases), then any directory entries matched to the meeting's calendar attendees. Cloud path: the n8n webhook payload gains a `people_context` field (JSON array) alongside existing `profile_id`/`requested_by`. The n8n workflow injects this into the Claude prompt. The LLM is instructed to resolve owner names against the provided list and use exact names from the list in action-item lines.

### Dependencies on existing features

- B (directory) must exist for attendee context to be available
- A (self-profile) must exist for self-context injection
- Existing `LLMService.swift:53-76` and `transcription.py:450-468` are the injection points
- n8n workflow `Iq3AAf8Vk8eQ9dcZ` requires payload contract change — spike recommended

---

## D. Name Matching + Editable Owner Assignment in Notule

### What it is in the real world

This is the least standardized of the four areas — no mainstream meeting-notes tool ships a "click the owner, pick a person from your local directory" UX. The closest patterns:

- **Fireflies/Asana integration**: auto-assign task in Asana to participant by email; user can override in Asana. The correction loop is external (in the task tool), not inline in the notes.
- **Microsoft Teams meeting notes**: assignee field on action items is a people-picker backed by the org's Active Directory. Inline, typed, resolves to known contacts.
- **AFFiNE**: action items styled `[ACTIE:eigenaar=@Jane]` are clickable Kanban cards; owner is editable.
- **Fellow**: action items have an "assign to" dropdown populated from meeting attendees.

The pattern that fits TranscriptStudio: **parse structured action-item blocks from the notule HTML/markdown, render each with a tappable owner chip, open a people-picker populated from the directory, save the override**.

Key UX principle from all tools: **the initial LLM attribution is a suggestion, not a commitment**. Showing a confidence indicator (greyed chip vs. solid chip) reduces user anxiety about wrong auto-assignments.

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Action items visually distinct in notule | Without visual separation, tappable owners are invisible | LOW | Already in notule templates; verify markup |
| Owner name rendered as tappable chip/badge | Obvious affordance for reassignment | MEDIUM | Requires custom HTML rendering or SwiftUI overlay |
| People-picker (directory + self) on tap | Without this the edit is just a text field | MEDIUM | Sheet/popover with directory entries |
| "Geen eigenaar" (unassigned) option | Not every action item has a clear owner | LOW | Explicit unassigned state, not just blank |
| Persistence of overrides | Override must survive notule regeneration | MEDIUM | `TranscriptRecord` attribution field; separate from notule HTML |
| Works in both notule viewers | `NotuleResultView` + `TranscriptDetailView` (FND-008) | MEDIUM | Two code paths; must not diverge |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Visual confidence indicator on auto-assigned owners | Low-confidence assignments shown differently (dashed chip); user knows what to verify | HIGH | Requires structured LLM output from C |
| Intern/extern indicator on owner chip | "Client" tag on external owner is relevant context | LOW | If person has extern flag, show it inline |
| Bulk confirm ("looks good, accept all") | Fast path for meetings where LLM did well | LOW | One tap to lock all auto-assignments |
| Override remembered for future meetings with same person | "Jan Bakker is always the owner of deployment tasks" | HIGH | Learning loop; out of scope for v1 |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Free-text name entry in owner field | Maximum flexibility | Creates orphan strings not tied to directory; breaks future matching; degrades attribution quality over time | Directory-only picker; "persoon toevoegen" link to directory |
| Auto-sync owner assignment to external task system (Jira, Asana) at time of edit | Obvious integration | Scope explosion; requires auth flows for each system; out of scope | Export action items as structured data; integrations are a future milestone |
| Re-generate notule on owner change | "Fix it at the source" | LLM output can change entirely; user loses other edits; slow | Store overrides separately; display = merge of notule + overrides |
| Owner assignment on transcript lines (not action items) | Fine-grained attribution | Premature; attribution at action-item level covers 90% of the value | Transcript-level attribution is a future feature |
| Automatic email send to owner on assignment | Workflow automation | Privacy: sends contact info to backend; out of scope | Explicit export/share later |

### Behavior description

In `NotuleResultView` and `TranscriptDetailView`, action-item sections render with each owner as a tappable badge. Tapping opens a sheet: directory entries + self + "Geen eigenaar" option. Selecting saves to `TranscriptRecord.attributions` (a separate dictionary keyed by action-item ID). The notule HTML is NOT modified; the overlay merges attributed owners on display. The two viewers share the same attribution read/write logic via a shared service or ViewModel method. On next open, saved attributions are restored.

### Dependencies on existing features

- C (context injection + structured LLM output) must produce parseable action-item blocks with owner fields
- B (directory) is the data source for the people-picker
- A (self-profile) is included in picker as "ik / myself" option
- `TranscriptRecord` model needs attribution extension (D-03)
- Both notule viewers must be updated — FND-008 from Parity & Polish findings is the relevant existing note

---

## Feature Dependencies

```
A. Self-Profile
    └──feeds──> C. Context Injection (self as prompt anchor)
    └──feeds──> D. Owner picker (self is a picker option)

B. People Directory
    └──requires──> A (org field enables intern/extern inference)
    └──feeds──> C. Context Injection (attendee list)
    └──feeds──> D. Owner picker (people source)

Calendar integration (existing)
    └──seeds──> B. People Directory (attendees as seed)

C. Context Injection
    └──requires──> A (self-profile exists)
    └──requires──> B (directory exists, even if empty)
    └──enables──> D (structured LLM output contains owner field)

D. Owner Assignment UI
    └──requires──> B (picker data source)
    └──enhanced by──> C (structured output reduces manual corrections)
    └──requires──> both notule viewers updated (FND-008)
```

### Dependency Notes

- **A before B**: org field in PersonProfile is needed to infer intern/extern when seeding directory from calendar
- **B before C**: injecting an empty people context is valid; B just makes C more useful
- **C before D**: D works without structured C output (fallback: regex parse action-item lines), but quality is much lower
- **FND-008 is a prerequisite for D**: the two-viewer inconsistency must be resolved before adding owner-edit UI to both

---

## MVP Definition

### Launch With (v1.1)

- [ ] A: PersonProfile model + skippable onboarding step + Settings edit — foundational for all other features
- [ ] B: Directory CRUD + calendar attendee seed prompt — populates the picker for D
- [ ] C: Self-profile + directory context injected into both LLM paths — immediate quality improvement for existing users
- [ ] D: Action-item owner chip (tappable) + people-picker + persistence — the visible payoff that justifies the milestone

### Add After Validation (v1.x)

- [ ] Duplicate detection in directory (fuzzy merge prompt) — trigger: user reports duplicate entries after calendar seeding
- [ ] Confidence indicator on auto-assigned owners — trigger: after structured LLM output from C is validated and stable
- [ ] Bulk-confirm "accept all attributions" — trigger: user feedback that per-item confirmation is tedious

### Future Consideration (v2+)

- [ ] Meeting-history association in directory ("appeared in N meetings") — deferred: requires transcript scan, high cost
- [ ] Attribution learning loop (remember owner patterns) — deferred: requires ML/heuristics layer
- [ ] External task system sync (Jira, Asana) — deferred: separate milestone, auth complexity
- [ ] Android — explicit out of scope for this milestone
- [ ] Org-wide profile sync — requires backend; breaks local-first

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| A: PersonProfile model + storage | MEDIUM | LOW | P1 |
| A: Onboarding step | MEDIUM | LOW | P1 |
| A: Settings edit | MEDIUM | LOW | P1 |
| B: Directory CRUD UI | HIGH | MEDIUM | P1 |
| B: Calendar attendee seed | HIGH | MEDIUM | P1 |
| B: Intern/extern inference | MEDIUM | LOW | P1 |
| C: Local LLMService injection | HIGH | LOW | P1 |
| C: Cloud n8n injection | HIGH | MEDIUM | P1 — spike first |
| D: Owner chip + people-picker | HIGH | MEDIUM | P1 |
| D: Attribution persistence | HIGH | MEDIUM | P1 |
| D: Both viewers updated | HIGH | MEDIUM | P1 — FND-008 dependency |
| B: Duplicate detection | LOW | MEDIUM | P2 |
| D: Confidence indicator | MEDIUM | HIGH | P2 |
| D: Bulk confirm | LOW | LOW | P2 |

---

## Competitor Feature Comparison

| Feature | Fireflies.ai | Otter.ai | Fellow.app | TranscriptStudio approach |
|---------|--------------|----------|------------|---------------------------|
| Action item owner attribution | Auto from transcript + CRM push | Auto from transcript | Manual in shared agenda | Auto (LLM) + manual correction inline |
| Owner correction | In CRM / task tool (external) | In Otter UI (comment) | In agenda | Inline owner chip, local only |
| People directory | Contacts via CRM integration | No local directory | Workspace contacts | Local on-device, privacy-first |
| Internal/external distinction | Email domain (org-wide) | No explicit flag | Default internal-only | Email-org match + manual toggle |
| Self-profiling | No | No | No (assumes shared workspace) | YES — unique to single-install model |
| Context injection | No (CRM sync is post-hoc) | No | No | YES — into LLM prompt directly |
| Privacy | Cloud-first, data leaves device | Cloud-first | Cloud-first | On-device, no backend for people data |

---

## Sources

- Gladia: [From transcript to actionable notes: Building effective LLM pipelines for meeting intelligence](https://www.gladia.io/blog/transcript-to-actionable-notes-llm)
- Fireflies: [What are action items](https://fireflies.ai/blog/what-are-action-items/) + [Asana integration](https://guide.fireflies.ai/articles/1901313269-how-to-integrate-asana-with-fireflies)
- Jiminny: [How your Teams Notetaker works](https://help.jiminny.com/en/articles/9527169-how-your-microsoft-teams-notetaker-works) — internal/external domain detection
- Grain: [Fireflies vs Otter comparison](https://grain.com/blog/fireflies-vs-otter)
- Otter.ai: [Meeting notes templates with action items](https://otter.ai/blog/meeting-notes-templates)
- Notion: [People Directory](https://www.notion.com/en-gb/help/people-directory) + [People profiles](https://www.notion.com/help/people-profiles)
- Fellow.ai: [How to manage meeting tasks and action items](https://fellow.ai/blog/how-to-manage-meeting-tasks-and-action-items/)
- Eleken: [User onboarding best practices](https://www.eleken.co/blog-posts/user-onboarding-best-practices)
- Avoma: [AI notetaker security and privacy checklist](https://www.avoma.com/blog/ai-notetaker-security-features) — internal/external recording controls
- AFFiNE: [How to get action items from meeting notes](https://affine.pro/blog/how-to-get-action-items-from-meeting-notes-ai-tips)

---

*Feature research for: People & Attribution milestone — TranscriptStudio v1.1*
*Researched: 2026-06-04*
