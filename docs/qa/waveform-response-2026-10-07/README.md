# Live waveform response

The native envelope already gates background noise and applies attack/release. The renderer now maps its output linearly (0.9 × level), replacing a second attenuation curve. Travel responds more strongly to measured energy (0.3 × (1 + 1.8 × level) Hz). The existing seven-strand gradient, three delayed lobes and compact widget remain. Silence is flat, and Reduce Motion freezes travel while retaining amplitude feedback.

The Windows recovery source also received the existing native system-audio meter and 30 Hz combined-source publisher from the primary checkout. It takes the maximum of recent microphone/system envelopes rather than letting a silent source suppress the other source. Stalled or paused streams expire after 150 ms. Both i16 and f32 loopback paths are metered before storage resampling.

No browser microphone capture or third-party waveform dependency was introduced. Native recording remains the single audio source for the visualizer on macOS and Windows.

Validation:

- Primary Windows frontend: production build and 61 tests pass.
- Recovery Windows frontend: production build and 52 tests pass.
- macOS `AudioEnvelopeProcessorTests`: 10 pass, 1 opt-in hardware test skipped. `xcodebuild test -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS' -only-testing:ThoughtVaultTests/AudioEnvelopeProcessorTests -allowProvisioningUpdates` succeeds.
- Real SwiftUI Canvas snapshots exported and visually reviewed: `soft.png`, `normal.png`, `loud.png`, `widget-loud.png`. The compact full-scale rendering remains inside its 32-point surface.
- Geometry test covers flat silence, visible normal speech, immediate first-sample feedback, reduced motion, inactive baseline and full-scale compact bounds.
- Standalone Rust test of the actual combined-level helper passes (system audio with silent microphone, microphone maximum, stale-source expiry).
- Windows candidate CI: https://github.com/michelknoop21/ThoughtVault/actions/runs/37654178569 (source `703e4ffa84338679433120077d0c21f5b499b790`, `publish=false`). Succeeded: frontend/native checks, MSI build and install/upgrade/startup smoke checks pass. Server publication was skipped.

Live microphone/WASAPI capture responsiveness has not been re-tested on hardware. The local installed app and published updater feed are unchanged by this candidate build. CI artifacts are retained under `build/windows-waveform-candidate-20261007/` (ignored).
