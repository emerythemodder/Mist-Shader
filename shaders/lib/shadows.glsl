float causticEdges(vec2 p, float t) {
    vec2 i = floor(p), f = fract(p);
    float d1 = 8.0, d2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 g = vec2(float(x), float(y));
            vec2 o = 0.5 + 0.42 * sin(t + TAU * hash22(i + g));
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
        }
    }
    return sqrt(d2) - sqrt(d1);
}

#ifdef USE_RIPPLES

uniform sampler2D rippleSamplerA;
uniform sampler2D rippleSamplerB;
#include "/lib/ripple_act.glsl"
#define RIPPLE_ACT_READ
float rippleHeightAt(ivec2 cell) {
    ivec2 t = cell & (RIPPLE_RES - 1);
    return (frameCounter & 1) == 0 ? texelFetch(rippleSamplerB, t, 0).x : texelFetch(rippleSamplerA, t, 0).x;
}

float rippleCaustics(vec2 surfXZ, float depth) {
    vec2 rel = abs(surfXZ - cameraPosition.xz);
    if (max(rel.x, rel.y) > 22.0 || !rippleActive(surfXZ)) return 1.0;
    vec2 p = surfXZ * RIPPLE_CELLS - 0.5;
    ivec2 i = ivec2(floor(p));
    vec2 f = p - vec2(i);
    float lap = 0.0;
    for (int k = 0; k < 4; k++) {
        ivec2 c = i + ivec2(k & 1, k >> 1);
        float l = rippleHeightAt(c + ivec2(1, 0)) + rippleHeightAt(c - ivec2(1, 0)) + rippleHeightAt(c + ivec2(0, 1))
                + rippleHeightAt(c - ivec2(0, 1)) - 4.0 * rippleHeightAt(c);
        lap += l * ((k & 1) == 1 ? f.x : 1.0 - f.x) * ((k >> 1) == 1 ? f.y : 1.0 - f.y);
    }
    lap *= RIPPLE_CELLS * RIPPLE_CELLS * 0.01;
    return clamp(1.0 / max(1.0 + depth * 0.25 * lap, 0.25), 0.3, 4.0);
}
#endif

float waterCaustics(vec3 worldPos, float depth) {
    #ifdef WATER_CAUSTICS
    vec3 Lr = refract(-getLightDir(), vec3(0.0, 1.0, 0.0), 1.0 / 1.33);
    vec2 surf = worldPos.xz + Lr.xz * depth / min(Lr.y, -0.05);
    float caustic = 1.0;
    #ifdef WATER_WAVES
    {
        float t = frameTimeCounter * WAVE_SPEED;
        float amp = 0.13 * WAVE_HEIGHT * (1.0 + rainStrength * 0.8);

        float e = 0.03 + depth * 0.006;
        float h0 = waveHeight(surf, t, 14);
        float lap = (waveHeight(surf + vec2(e, 0.0), t, 14) + waveHeight(surf - vec2(e, 0.0), t, 14)
                   + waveHeight(surf + vec2(0.0, e), t, 14) + waveHeight(surf - vec2(0.0, e), t, 14) - 4.0 * h0) / (e * e);
        caustic = 1.0 / max(1.0 + depth * (1.0 - 1.0 / 1.33) * amp * lap, 0.25);
    }
    #endif
    #ifdef USE_RIPPLES
    caustic *= rippleCaustics(surf, depth);
    #endif
    caustic = clamp(caustic, 0.2, 4.0);
    float spread = smoothstep(0.1, 1.2, depth);
    return mix(1.0, caustic, saturate(spread * CAUSTIC_STRENGTH));
    #else
    return 1.0;
    #endif
}
