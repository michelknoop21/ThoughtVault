# Travelling soundwaves with real audio response

Read this when implementing a SiriWave-style renderer or investigating a wave that changes height but does not travel. This is a stylized audio visualization, not a literal PCM waveform or a fundamental-frequency detector.

## Reuse the verified curve

ThoughtVault reused the [SiriWave Classic source](https://github.com/kopiro/siriwave/blob/744cb00235b7900733efff25dc73b4d1ab77c92d/src/classic-curve.ts) at commit `744cb00235b7900733efff25dc73b4d1ab77c92d` under MIT. Preserve the upstream copyright/license when adapting its code. The small geometry ports to an existing Canvas or native drawing surface; installing the JavaScript library is optional and should fit the project's renderer.

For normalized horizontal position x in 0..1:

```text
u = 4*x - 2
attenuation = (4 / (4 + u^4))^4
phase += dtSeconds * 2*pi * travelHz * (1 + energyBoost*liveLevel)
y = centerY - maxHeight * attenuation * amplitude * strandScale
    * sin(spatialFrequency*u - phase*strandSpeed + strandOffset)
```

`spatialFrequency` controls the drawn curve, not a measured frequency in Hz. `liveLevel` is finite, clamped and derived from calibrated audio. Main amplitude follows loudness even when spectral data is absent. Support strands may combine current and briefly delayed loudness and use measured band distribution for their gain. Their independent phase speeds do not establish independent audio response.

ThoughtVault's reference choices: travelHz=0.65, energyBoost=0.8, maxHeight=0.40*canvasHeight, visual amplitude=0.9*calibratedLevel. Main strand speed=1; support speed=0.82+index*0.065. Support amplitude=0.65*current+0.35*delayed, delay=index*25 ms; band gain has a visual floor of 0.25. These are styling choices, not universal calibration defaults. Relative band normalization preserves spectral shape but cannot replace absolute loudness.

## Clock and redraw failure modes

- Keep phase state across PCM updates and rendered frames. Recreating a view for each exported image can reset its clock and create a video with volume changes but no travelling crests.
- Use elapsed time, not a fixed per-frame increment. Keep time units consistent across native timeline dates and browser timestamps. Use the platform's monotonic clock where available and clamp negative or excessively large deltas after suspension; ThoughtVault caps dt at 64 ms.
- A deferred native draw closure needs a snapshot of the new scalar phase. Mutating an object hidden inside unchanged view inputs can leave Canvas drawing an old frame.
- Reset timing on resume without replaying the background gap. Respect intended floating-widget background behavior separately from the main window. Cancel observers/animation loops when disposing the renderer.
- Pause/inactivity must clear or gate old envelope and spectrum. Silence flattens height even if the phase clock continues. Reduce Motion removes travel while retaining loudness feedback.
- Do not smooth the same signal repeatedly in capture, publication and rendering without measuring the combined delay. Avoid a second gate/power curve on a shaped envelope; this previously hid quiet speech and removed soft/loud separation.

## Acceptance cases

| Input / state | Evidence to collect | Required behavior |
| --- | --- | --- |
| Steady audible level | Two or more frames at known times | Crests move horizontally; height does not depend on frame rate |
| Same elapsed time at 30 / 60 Hz | Accumulated phase and curve positions | Equivalent travel within numeric tolerance |
| Quiet, normal, loud at the same spectrum | PCM RMS, calibrated envelope, peak height | Clear ordered heights with headroom; quiet is visible above the intended gate |
| Equal-power low / high tones | Band energy and support paths | Spectral shape changes without losing main loudness |
| Tones between former probes / on band boundaries | Integrated energy at supported sample rates | No artificial silent gaps; boundary energy may split across bands |
| Speech-like bursts / rolling buffers | Onset, peak and silence-decay times | Syllable timing survives the actual buffer/publication cadence |
| Silence with stale spectrum, pause, resume | Levels, phase and captured frames | Flat inactive/silent output; no suspension jump on resume |
| Main window and compact widget | Bounds, labels, buttons, contrast | Wave and blur stay inside reserved space; controls remain legible |
| Reduce Motion | Constant and changing levels | No travelling crests, meaningful height feedback remains |

Reject empty or non-finite PCM safely. Check low sample rates, actual source channels and system/microphone/combined levels where supported. A quiet source with low measured RMS is a capture/calibration issue; healthy level diagnostics with tiny or static output is a mapping/redraw issue. Preserve capture semantics when fixing visualization.

## Evidence limits

Use production DSP and renderer code in a controlled preview. Keep one clock across frames and label synthetic input. A screenshot cannot prove travel. A silent video cannot establish audio-to-screen timing. For latency, pair safe known audio with timestamped diagnostics or a synchronized audiovisual capture, and distinguish DSP delay from device/transport/render delay. Do not record or disclose private meetings to obtain proof.

A live check belongs on the installed target app and its widget. Native Windows verification must use the real Windows executable, not a browser fixture. Verify build/version and local data preservation on upgrade. Do not restart an active meeting to improve evidence. Publication is a separate authorized step, not implied by having built or installed the app.
