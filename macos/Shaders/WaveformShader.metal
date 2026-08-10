// WaveformShader.metal
// ThoughtVault
//
// SiriWave-style neon soundwave. Seven braided strands plus a bright core line,
// each drawn as y(x) = A(x) * carrier(x, t) * g(x):
//
//   g(x)     = (K/(K + x^K))^K, K = 4, x in [-2, 2] — attenuation envelope that
//              keeps the wave full in the middle and tapers it to a point at
//              both edges.
//   carrier  = sin(k*gx + ph) * 0.82 + sin(k*1.9*gx + ph*1.3 + 1.1) * 0.18
//              (fundamental plus a soft second harmonic, fully deterministic).
//   A(x)     = the scrolled envelope history on the left, cross-fading into the
//              LIVE level on the right with weight t*t*0.85, so new speech shows
//              up immediately instead of being squashed by the attenuation.
//
// Mirror pairs (same k, phase offset pi) produce the braided iOS look. The
// history comes from AudioEnvelopeProcessor (30 Hz, 3 s); the phase clock is
// integrated in WaveformView because a shader is stateless.
//
// Output is premultiplied with its own alpha — colour channels are allowed to
// exceed alpha, which is what gives the additive neon bloom (the equivalent of
// `globalCompositeOperation = 'lighter'` on canvas). The view behind it stays
// visible, so the waveform drops into any surface.

#include <metal_stdlib>
using namespace metal;

constant float ATT_K = 4.0;

constant int   MAX_STRANDS = 7;
constant float S_AMP[7]   = { 1.00, 0.90, 0.75, 0.62, 0.50, 0.42, 0.30 };
constant float S_K[7]     = { 6.0,  6.0,  8.5,  8.5,  11.0, 11.0, 14.0 };
constant float S_SPEED[7] = { 1.10, 1.10, 1.45, 1.45, 1.80, 1.80, 2.20 };
constant float S_PHASE[7] = { 0.0,  3.14, 1.2,  4.34, 2.2,  5.34, 0.7  };
constant float S_WIDTH[7] = { 2.4,  2.4,  1.9,  1.9,  1.5,  1.5,  1.2  };
constant float S_ALPHA[7] = { 0.95, 0.95, 0.85, 0.85, 0.75, 0.75, 0.65 };

// Palette, outermost pair -> innermost strand: blue -> cyan -> purple -> pink.
// Mirror pairs share a colour so the braid reads as one strand.
constant float3 S_COLOR[7] = {
    float3(0.2, 0.4, 1.0), float3(0.2, 0.4, 1.0),   // mix(blue, cyan, 0.0)
    float3(0.0, 0.8, 1.0), float3(0.0, 0.8, 1.0),   // mix(blue, cyan, 1.0)
    float3(0.6, 0.2, 0.9), float3(0.6, 0.2, 0.9),   // mix(purple, pink, 0.0)
    float3(1.0, 0.3, 0.6)                            // mix(purple, pink, 1.0)
};

/// (K/(K + x^K))^K. `gx` is negative on the left half, so x^K is built by
/// squaring twice — pow() with a negative base is undefined in Metal.
static float attenuation(float gx) {
    float gx2 = gx * gx;
    float gx4 = gx2 * gx2;
    return pow(ATT_K / (ATT_K + gx4), ATT_K);
}

/// Envelope history sampled at t (0 = oldest/left, 1 = newest/right) with
/// cosine interpolation, so ~90 points over ~900 pt do not show as steps.
static float envAt(float t, device const float *history, int count) {
    if (count <= 0) { return 0.0; }
    if (count == 1) { return history[0]; }
    float f = clamp(t, 0.0, 1.0) * float(count - 1);
    int i0 = int(f);
    int i1 = min(count - 1, i0 + 1);
    float u = (1.0 - cos((f - float(i0)) * M_PI_F)) * 0.5;
    return mix(history[i0], history[i1], u);
}

[[stitchable]]
half4 neonWaveform(float2 position, half4 color,
                   float2 size, float phaseTime,
                   device const float *history, int historyCount,
                   float liveLevel, float strandCount) {
    if (size.x <= 0.0 || size.y <= 0.0) { return half4(0.0h); }

    float t = clamp(position.x / size.x, 0.0, 1.0);
    float gx = t * 4.0 - 2.0;
    float att = attenuation(gx);

    float cy = size.y * 0.5;
    float maxH = size.y * 0.46;

    // Left: scrolled history. Right: increasingly the LIVE level, so a fresh
    // peak is visible at the right edge within a frame or two.
    float liveW = t * t * 0.85;
    float amplitude = envAt(t, history, historyCount) * (1.0 - liveW) + liveLevel * liveW;

    // Glow radius follows loudness. The reference (shadowBlur = 6 + live * 24 on
    // a 120 pt canvas) expressed relative to maxH, so it stays proportional
    // instead of smearing the 32 pt widget into blobs.
    float glow = maxH * (0.11 + liveLevel * 0.44);
    // Stroke widths are reference pixels on a 120 pt canvas; scale them down on
    // small surfaces, never up.
    float widthScale = clamp(size.y / 120.0, 0.4, 1.0);

    float3 c = float3(0.0);
    int strands = clamp(int(strandCount), 1, MAX_STRANDS);

    for (int i = 0; i < strands; i++) {
        float ph = phaseTime * S_SPEED[i] + S_PHASE[i];
        float carrier = sin(S_K[i] * gx + ph) * 0.82
                      + sin(S_K[i] * 1.9 * gx + ph * 1.3 + 1.1) * 0.18;
        float y = cy + carrier * amplitude * S_AMP[i] * maxH * att;
        float d = abs(position.y - y);

        float halfWidth = max(0.35, S_WIDTH[i] * 0.5 * widthScale);
        float sharp  = 1.0 - smoothstep(halfWidth, halfWidth + 0.9, d);
        float medium = smoothstep(glow * 0.5, 0.0, d);
        float aura   = smoothstep(glow * 1.6, 0.0, d);

        c += S_COLOR[i] * S_ALPHA[i] * (sharp * 0.9 + medium * 0.28 + aura * 0.10);
    }

    // Bright core line on top: flat in silence, lights up with speech.
    {
        float ph = phaseTime * 0.8 + 1.6;
        float carrier = sin(4.0 * gx + ph) * 0.82
                      + sin(4.0 * 1.9 * gx + ph * 1.3 + 1.1) * 0.18;
        float y = cy + carrier * amplitude * 0.14 * maxH * att;
        float d = abs(position.y - y);

        float halfWidth = max(0.35, 0.7 * widthScale);
        float sharp = 1.0 - smoothstep(halfWidth, halfWidth + 0.9, d);
        float aura  = smoothstep(glow * 0.6, 0.0, d);
        float brightness = 0.5 + liveLevel * 0.45;

        c += float3(0.7, 0.4, 1.0) * brightness * (sharp * 1.0 + aura * 0.18);
    }

    float a = clamp(max(max(c.r, c.g), c.b), 0.0, 1.0);
    return half4(half3(c), half(a));
}
