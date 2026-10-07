# ThoughtVault artwork

`thoughtvault-vault-mark.png` is the approved transparent brain-to-vault mark, created on 7 October 2026 from the existing ThoughtVault artwork. The lower crystal was changed into a safe at the user's request. Original artwork is retained separately.

Regenerate desktop assets from the repository root on macOS:

```sh
swift scripts/generate-desktop-icons.swift
```

This exports proportional, transparent PNGs for macOS AppIcon and desktop in-app branding, plus Windows PNG, ICO and ICNS assets. The ICO contains 16, 24, 32, 48, 64, 128 and 256px entries. The original portrait artwork remains unchanged. Mobile-specific assets and the monochrome recording status icon are outside this export.

Validation: macOS signed Debug build succeeded; Windows frontend TypeScript/Vite build succeeded. PNG dimensions/transparency and all ICO sizes checked. A Windows executable/MSI rebuild and installed OS icon-cache check remain release-time validation.
