# Windows design recovery

Cause: active local/cloud-AI worktree was based on `8676b02`, preceding the desktop parity commits `d9396d3` and `262c98a` in main. The 1.0.258 source had a new Home/recording stylesheet, but lacked the approved shared NorthStar style layer and replaced tabbed settings with a long stacked legacy form.

Restored the shared style layer from `6758310`, tab navigation and two-column processing settings. Preserved local storage, provider selection, cloud credentials, AI connections, profile, calendar and Obsidian controls. Restored the original real hardware command for the PC panel and collapsible navigation. No account/admin navigation restored.

Checks: TypeScript/Vite build and 48 Vitest tests passed. Added a regression check requiring the settings navigation, hardware panel and new cloud/AI controls together. Browser component review used real app components at 1440x900 and 1024x768; no horizontal page overflow and calendar controls remained reachable. Browser screenshots have no native hardware bridge, so hardware unavailable messages in these captures are expected. Native build/install evidence is recorded separately by the Windows workflow.
