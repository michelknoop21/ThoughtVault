# Windows desktop responsiveness

Source starts at bf331ae (latest unreleased audit fixes, based on released 1.0.260).
The released Windows baseline and these changes were reconciled into a branch
based on Gitea main. Website and unrelated platform sources remain intact.
The Windows tree matches the reviewed candidate exactly.

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

Run `npm ci`, then `npm run dev -- --port 1438` in `windows`, followed by:

```sh
python3 docs/qa/windows-desktop-responsive/check.py
```

Requires the project's existing global gstack browse installation. The review
entrypoint uses real app pages/components and synthetic local notes, blocks
network calls and stubs native commands. It is not a production Vite entrypoint.
No real recordings, calendar events or note content are included in the images.

## Verified

- TypeScript/Vite production build succeeds; 59 Vitest tests pass.
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
