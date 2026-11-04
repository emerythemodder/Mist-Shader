vec2 foamCells(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    float d1 = 8.0, d2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 g = vec2(float(x), float(y));
            vec2 r = g + hash22(i + g) - f;
            float d = dot(r, r);
            if (d < d1) { d2 = d1; d1 = d; }
            else if (d < d2) d2 = d;
        }
    }
    return vec2(sqrt(d2) - sqrt(d1), sqrt(d1));
}

float foamCover(vec2 p, float amount, float footprint, float time, vec2 drift) {
    if (amount < 0.004) return 0.0;
    p -= drift;

    vec2 q = p + (vec2(valueNoise(p * 3.1 + time * 0.05), valueNoise(p * 3.1 + 7.7 - time * 0.04)) - 0.5) * 0.18;
    float a = amount * (0.55 + 0.9 * valueNoise(p * 1.7 + 5.0));

    float th = clamp(a, 0.0, 1.2) * 0.42 * (0.55 + 0.9 * valueNoise(q * 6.3 + 2.1));
    vec2 big = foamCells(q * 12.0);
    vec2 fine = foamCells(q * 29.0 + 3.7);
    float net = 1.0 - smoothstep(th - 0.05, th + 0.03, big.x);
    float lace = (1.0 - smoothstep(th * 0.8 - 0.06, th * 0.8 + 0.02, fine.x)) * smoothstep(0.05, 0.3, a);
    float cover = max(net, lace * 0.7);

    vec2 bc = floor(p * 70.0);
    float bub = step(hash12(bc), a * 0.15) * (1.0 - smoothstep(0.18, 0.34, length(fract(p * 70.0) - hash22(bc) * 0.5 - 0.25)));
    cover = max(cover, bub * 0.6);

    float opacity = mix(0.25, 0.8, smoothstep(0.15, 1.0, a));
    cover *= opacity;
    float avg = saturate(th * th * 6.0) * opacity;
    cover = mix(cover, avg, smoothstep(0.03, 0.09, footprint));
    return saturate(cover) * smoothstep(0.0, 0.05, a);
}

float windFoam(vec2 p, float t, float crest, float wind) {
    float W = smoothstep(0.2, 1.0, wind);
    W *= W * W;
    if (W < 0.002) return 0.0;
    vec2 w = waterWind();
    vec2 q = vec2(dot(p, w), dot(p, vec2(-w.y, w.x)));

    float breaking = valueNoise(q * vec2(0.3, 0.55) - vec2(t * 0.9, 0.0) + 3.0);
    float caps = smoothstep(0.66, 0.92, crest) * smoothstep(0.6, 0.85, breaking) * W * 1.3;

    float s = valueNoise(q * vec2(0.22, 1.9) - vec2(t * 0.12, 0.0)) * valueNoise(q * vec2(0.5, 4.0) - vec2(t * 0.16, 0.0) + 7.0);
    float residual = smoothstep(0.32, 0.62, s) * W * 0.3;
    return caps + residual;
}

float flowFoam(vec2 p, vec2 flowDir, float slope, float t) {
    float churn = smoothstep(0.12, 0.6, slope);
    if (churn < 0.01) return 0.0;
    vec2 q = vec2(dot(p, flowDir), dot(p, vec2(-flowDir.y, flowDir.x)));
    q.x -= t * (0.8 + slope * 2.0);
    float lines = valueNoise(q * vec2(0.7, 3.2)) * valueNoise(q * vec2(1.6, 6.0) + 4.0);
    return churn * (0.25 + 0.6 * smoothstep(0.25, 0.6, lines)) * 0.6;
}
