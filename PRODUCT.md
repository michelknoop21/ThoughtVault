# Product

## Register

product

## Users

Dutch business professionals (MKB and larger), and the Yinga/Prezent teams and clients who work alongside them. Their context: they sit in meetings, calls, and interviews that produce decisions they're accountable for, and they don't want to spend the evening writing them up. The job to be done is **"turn what was just said into a clean, shareable set of notulen I can trust"** — record (or upload) a conversation, get an accurate transcript, get a structured Dutch summary in the right format for their situation, lightly edit, done.

They are not power users of transcription tooling. They expect it to behave like a well-made native app: open it, hit record, and the rest is obvious. The primary task on any given screen is singular and clear — record, review a transcript, read/edit a notule, or adjust a setting — never a wall of options.

## Product Purpose

TranscriptStudio records or ingests audio, transcribes it, and generates structured Dutch meeting notes (notulen) using configurable profiles. It runs natively on macOS/iOS (SwiftUI) and Windows (Tauri) against a shared FastAPI backend, with a local-first fallback path for transcription and summarisation.

It exists because the gap between "the meeting happened" and "the notes are written" is where accountability leaks. Generic transcription tools stop at a raw transcript; TranscriptStudio carries the workflow all the way to a finished, profile-shaped notule. Success looks like: a user finishes a meeting, presses one button, and minutes later has notes good enough to send with only minor edits — on whichever platform they happen to be using, with the same experience and quality on each.

## Brand Personality

Yinga: **warm, confident, professional.** Three words: approachable, branded, dependable. The interface should feel like a first-party native app that happens to wear Yinga's colours — calm and uncluttered, but unmistakably Yinga (the four-colour spinner, magenta primary actions). It evokes quiet competence: the user should feel the tool is handling something tedious well, not performing cleverness at them. Voice in UI copy is plain, direct Dutch — verb-first labels, no jargon, no hype.

## Anti-references

- **Generic dark SaaS dashboard** — neon-on-charcoal, dense data grids, sharp corners, the Linear/Vercel-clone aesthetic. TranscriptStudio is light-first, glass-on-soft-gray, rounded.
- **Cluttered enterprise tool** — dense toolbars, tiny fonts, flat corporate blue, feature-soup screens (old Teams/SharePoint admin energy). One clear task per screen instead.
- **Toy / consumer-cute app** — mascots, playful illustrations, gamified confetti. Too casual for notes people are accountable for; stay professional.
- **Faceless, unbranded utility** — a neutral grey tool with no identity. It must stay unmistakably Yinga; the brand is the personality, not decoration.

## Design Principles

- **One job per screen.** Every view answers a single question — record? review? edit? configure? Resist piling options onto a surface; the workflow is the spine.
- **Branded, but mannered.** Yinga's identity leads (magenta actions, the spinner, the wordmark) while the platform supplies the manners (native materials, HIG rhythm, system fonts). Confidence without noise.
- **Same product, twice.** macOS/iOS and Windows are one experience rendered on two stacks. Feature and visual parity is a product promise, not a nice-to-have; a change that lands on one platform is unfinished until it lands on the other.
- **Trust through clarity.** Users are accountable for these notes. State must be legible at a glance — what's recording, what's processing, what's done, what failed — with honest, specific feedback over reassuring vagueness.
- **Quiet competence.** The tool does the tedious part well and gets out of the way. Motion and colour reinforce what's happening; they never perform for their own sake.

## Accessibility & Inclusion

Target **WCAG 2.1 AA**, already partly established in code and to be held going forward:
- Body text meets ≥4.5:1 contrast (≥3:1 for large/bold); placeholder text held to the same bar, not faint grey.
- Visible brand-coloured `:focus-visible` rings; full keyboard operability including a skip-link and `.sr-only` labelling.
- Minimum 44px touch/hit targets (small icon buttons expand their hit area transparently).
- `prefers-reduced-motion` honoured on every animation (pulses, hover lifts, skeletons) with a crossfade/instant fallback.
- Full light **and** dark themes as first-class, with status colours that shift per theme to preserve contrast.
- UI strings localised (Dutch via `Localizable.strings`); language-agnostic layout that tolerates longer Dutch labels.
