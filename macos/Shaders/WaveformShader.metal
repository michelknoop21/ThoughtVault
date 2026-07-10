// WaveformShader.metal
// ThoughtVault
//
// Neon soundwave — direct port of the WebGL/GLSL reference: 9 mirrored layers,
// each a sum of 3 sines with layer-dependent frequency/speed, smoothstep edge
// mask, 3 additive glow passes per layer (sharp core / medium glow / ambient
// aura), palette blue->cyan (0-3), electric purple core (4), purple->pink (5-8),
// on near-black. Driven via SwiftUI colorEffect.
//
// Only change vs the reference: waveVal is scaled by the real mic envelope
// (level, 0..1) so silence = calm thin lines, speech = full waves.

#include <metal_stdlib>
using namespace metal;

static float getWave(float2 uv, float layer, float time) {
    float x = uv.x;
    float wave = sin(x * (8.0 + layer * 0.5) - time * (2.0 + layer * 0.2)) * 0.3;
    wave += sin(x * (15.0 + layer) + time * (1.5 - layer * 0.1)) * 0.15;
    wave += sin(x * (4.0) - time * 0.8) * 0.1;
    float mask = smoothstep(0.0, 0.15, x) * smoothstep(1.0, 0.85, x);
    return wave * mask;
}

[[stitchable]]
half4 neonWaveform(float2 position, half4 color, float2 size, float time, float level) {
    float2 uv = position / size;

    float3 finalColor = float3(0.01, 0.005, 0.02);
    float centerY = 0.5;
    const int NUM_LAYERS = 9;

    for (int i = 0; i < NUM_LAYERS; i++) {
        float fi = float(i);
        float distCenter = abs(fi - 4.0);

        float phaseOffset = fi * 0.25;
        float ampScale = 1.0 - distCenter * 0.15;
        float opacity = 1.0 - distCenter * 0.2;
        float lineWidth = 1.0 - distCenter * 0.1;

        // Real envelope drives amplitude: idle ~thin lines, speech ~full waves.
        float waveVal = getWave(uv, fi, time + phaseOffset) * 0.4 * ampScale;
        waveVal *= (0.15 + 0.85 * level);

        float d = abs(uv.y - (centerY + waveVal));
        float dMirror = abs(uv.y - (centerY - waveVal));
        float minDist = min(d, dMirror);

        float3 layerColor;
        if (i == 4) {
            layerColor = float3(0.7, 0.4, 1.0);
        } else if (i < 4) {
            layerColor = mix(float3(0.2, 0.4, 1.0), float3(0.0, 0.8, 1.0), fi / 4.0);
        } else {
            layerColor = mix(float3(0.6, 0.2, 0.9), float3(1.0, 0.3, 0.6), (fi - 5.0) / 4.0);
        }

        float sharp = smoothstep(0.006 * lineWidth, 0.0, minDist);
        finalColor += layerColor * sharp * opacity * 0.9;

        float medium = smoothstep(0.04, 0.0, minDist);
        finalColor += layerColor * medium * opacity * 0.3;

        float aura = smoothstep(0.12, 0.0, minDist);
        finalColor += layerColor * aura * opacity * 0.1;
    }

    float centerLine = smoothstep(0.002, 0.0, abs(uv.y - centerY));
    finalColor += float3(0.5, 0.3, 0.8) * centerLine * 0.15;

    finalColor = clamp(finalColor, 0.0, 1.0);
    return half4(half3(finalColor), 1.0h);
}
