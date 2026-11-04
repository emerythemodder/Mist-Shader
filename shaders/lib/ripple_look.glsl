vec3 rippleSurface(vec2 worldXZ) {
    #ifdef RIPPLE_ACT_READ
    if (!rippleActive(worldXZ)) return vec3(0.0);
    #endif
    vec2 p = worldXZ * RIPPLE_CELLS - 0.5;
    ivec2 i = ivec2(floor(p));
    vec2 t = p - floor(p);
    vec2 it = 1.0 - t, t2 = t * t, t3 = t2 * t;
    vec2 w[4]  = vec2[4](it * it * it / 6.0, (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0,
                         (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0, t3 / 6.0);
    vec2 dw[4] = vec2[4](-0.5 * it * it, 1.5 * t2 - 2.0 * t, -1.5 * t2 + t + 0.5, 0.5 * t2);
    vec2 g = vec2(0.0);
    float foam = 0.0;
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            vec4 s = rippleCellState(i + ivec2(x - 1, y - 1));
            g += s.x * vec2(dw[x].x * w[y].y, w[x].x * dw[y].y);
            foam += s.z * (w[x].x * w[y].y);
        }
    }
    return vec3(g * (RIPPLE_CELLS * 0.01), foam);
}

vec2 rippleChop(vec2 p, float time, float churn, float footprint) {
    float amp = churn * (1.0 - smoothstep(0.01, 0.04, footprint));
    if (amp < 0.01) return vec2(0.0);
    const float e = 0.012;
    vec2 q1 = p * 13.0 + vec2(time * 1.3, -time * 0.9);
    vec2 q2 = p * 29.0 - vec2(time * 2.1, time * 1.7);
    float c1 = valueNoise(q1), c2 = valueNoise(q2);
    vec2 g1 = vec2(valueNoise(q1 + vec2(e * 13.0, 0.0)) - c1, valueNoise(q1 + vec2(0.0, e * 13.0)) - c1) / e;
    vec2 g2 = vec2(valueNoise(q2 + vec2(e * 29.0, 0.0)) - c2, valueNoise(q2 + vec2(0.0, e * 29.0)) - c2) / e;
    return (g1 * 0.0015 + g2 * 0.0008) * amp;
}
