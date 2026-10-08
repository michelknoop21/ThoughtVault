---
name: audio-reactive-waveform
description: Diagnose and improve audio-reactive waveforms in desktop apps and recording widgets. Use when soundwaves miss audible speech, move together, react slowly, or overlap controls; measure PCM response and verify the real renderer before claiming success.
---

# Audio Reactive Waveform

Improve the existing capture and visualization path. First establish whether the user wants a literal time-domain waveform, a frequency-band display, or the existing stylized soundwave. Do not substitute a pitch detector or decorative animation without a reason grounded in that request.

## Diagnose before tuning

Trace PCM source, sample rate, buffer length, publication cadence, calibrated RMS envelope, spectrum, renderer and widget. Preserve source selection, noise calibration, recording storage and capture permissions. Reuse existing platform DSP or decoder FFT support before adding a library.

Distinguish low signal, missing frequency coverage, smoothing latency and renderer suppression. Equal-amplitude tones between existing frequency probes are a useful negative control: silence from the analyzer while RMS remains audible indicates a measurement gap. Inspect real source behavior rather than comparing only screenshots.

For the formulas and a demonstrated macOS/Windows case, read [references/spectrum-response.md](references/spectrum-response.md). Its seven bands, thresholds and time constants describe ThoughtVault 1.0.267, not universal defaults. Adapt them to the actual sample rates, voice range and required response.

## Implement measurable response

- Compute overall volume from the calibrated PCM envelope. In a stylized soundwave, sparse spectral energy must not make audible volume disappear. Preserve the existing temporal history that represents syllables.
- Integrate power over contiguous frequency bands using a correctly normalized windowed FFT. A few isolated Goertzel probes are not a complete band measurement. Correct for window power, mirrored bins and Nyquist.
- Smooth with elapsed time: alpha = 1 - exp(-dt/tau). Choose attack and release separately. Record the measured onset and silence decay rather than assuming those constants equal total latency.
- Use actual low/mid/high distribution to weight individual strands or their spatial pattern. Several sine curves driven by one scalar are not independent frequency response. A spatial curve is not an exact fundamental-pitch estimate.
- Cache FFT plans and buffers; keep analysis off the UI hot path where the current architecture allows. Do not add a second recording engine for the visualizer.
- Reserve and clip the canvas. Check the main studio and compact widget; cover text/buttons, long-duration labels, contrast, pause, silence, stale spectrum and background operation. Reduce Motion should suppress travel while retaining meaningful level feedback.

## Verification and screenshots

Use deterministic PCM fixtures with equal-power tones across band gaps and boundaries at supported sample rates. Include speech-like multi-tone input, quiet/loud levels, non-finite input and silence. Verify streamed rolling buffers at the actual publication cadence, not only a full stationary FFT buffer. Test meaningful renderer invariants such as retained height for audible volume, distinct low/high paths, compact bounds and stationary Reduce Motion peaks.

Separate evidence explicitly: DSP fixture results, native tests/build, installed-app visual checks, and real hardware-to-screen timing. An audio-free screen recording cannot prove audiovisual latency. Passing tests cannot prove that the user likes the movement.

For requested screenshots, capture the installed app and widget through the available computer-use tool. Verify recording state before any interaction. Never stop, restart, update or launch another app copy during a live meeting. If the host is locked, request unlocking; do not bypass the lock or label simulated images as native screenshots. Use a safe test source when needed, avoiding private speech or accidental cloud processing. Crop to the relevant waveform region with the screenshot tool when supported; otherwise omit captures containing private notes or transcripts. If only a controlled preview is available, label it as a preview with simulated input.

Creating or invoking this skill does not authorize deployment, provider changes, credential use or publication of private recordings. Follow the user's existing task authorization and report unverified surfaces plainly.
