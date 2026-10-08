# Windows desktop responsiveness

Source is based on current Gitea main. The released Windows distribution settings
and the presentation fixes were ported without importing unrelated app changes.
Website and unrelated platform sources remain intact.
The responsive presentation is applied to the current main implementation.
Obsidian conflict handling, credential storage and recording quick notes are retained.

The shell now uses the Windows caption, resize borders, system menu and window
controls. Recording status updates the native caption. Branding stays in the
sidebar. Ctrl+Shift+S collapses/expands navigation. Recent navigation scrolls
within its own section so Settings stays reachable.

Home keeps search, recording preparation, settings, source shortcuts, calendar
connection/events, note filters, open/delete and loading/error/empty states.
The instructions use a native disclosure. Notes move above the secondary calendar
and shortcuts on narrow windows. The recording workspace keeps transport, source,
profile, participant controls, file import, saved recordings and processing status.
Its inspector stacks below it without overlapping or a second scrollbar.

## Reproduce

Run `npm ci`, then `npm run dev -- --port 1442` in `windows`, followed by:

```sh
python3 docs/qa/windows-desktop-responsive/check.py
```

Requires the project's existing global gstack browse installation. The review
entrypoint uses real app pages/components and synthetic local notes, blocks
network calls and stubs native commands. It is not a production Vite entrypoint.
No real recordings, calendar events or note content are included in the images.

## Verified

- TypeScript/Vite production build succeeds; 65 Vitest tests pass.
- 56 route/viewport combinations: Home, Recording, Tasks, Notes, Profiles, People,
  Settings at 640x560, 720x560, 900x560, 900x600, 1200x800, 1280x800, 1440x900,
  1920x1080. No horizontal workspace overflow or clipped form/button controls.
- Settings remains inside the navigation viewport; the studio control bar stays
  inside the smallest viewport. Stacked inspector begins after the workspace.
- 900x600 at device pixel ratio 2 rendered; note detail and Obsidian settings
  controls also checked at 900x560. Screenshots show web content dimensions,
  excluding the native Windows caption.
- Before: at 900x600 the recording card was 500px tall and recent notes started
  at y=1214. After: card ~220px, recent notes start ~428px at 900x560.
- Native minimum width reduced to 640, after all seven pages passed at that width.

## Native verification boundary

The running 1.0.260 in Parallels was inspected visually. Guest input through the
available computer control did not reliably execute, and Parallels CLI guest
commands require a Pro/Business license on this host. Do not claim interactive
Parallels validation. The exact candidate is built and installation/upgrade tested
on Windows through the existing GitHub workflow; record its final result below.

## macOS navigation and sheet review

The local navigation matches `AppTab` in macOS ContentView: Home, Opnemen,
Taken, Notulen, Mensen, Instellingen. Ctrl+1 through Ctrl+6 follows that order.
Profiles are managed within Settings > Notulen. Legacy /profiles links redirect
to that tab. Existing recording profile selection remains available.

`python3 docs/qa/windows-desktop-responsive/check-settings.py` checks all seven
settings tabs at 640x560, 900x560 and 1200x800, plus six onboarding steps.
The 21 tab/viewport checks and six steps passed without clipped controls.

Browser sheet review at 640x560 covers person editing, participant selection,
profile creation, quick notes during a simulated recording, attendee review,
tags, regeneration and note deletion. Open sheets kept focus inside, fit within
the viewport and closed with Escape. Profile creation also restored focus to
its opening button. Sheet contents use the existing app components, not mockups.
The common sheet behavior also applies to task confirmations and profile deletion.

Recording stop, Obsidian replacement and model deletion now use native Windows
confirmation dialogs. Native file/folder pickers and the separate floating recorder
keep their existing platform implementations. Interactive OS dialog, floating-window
and audio-device checks in Parallels remain unverified.
