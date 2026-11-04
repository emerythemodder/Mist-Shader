#define WATER_ABSORB (vec3(0.30, 0.065, 0.04) / WATER_CLARITY)

vec2 waterWind() { return vec2(0.943, 0.330); }

float waveHeight(vec2 pos, float time, int iters) {
    float windAngle = atan(waterWind().x, waterWind().y);
    float angle = 0.0, freq = 1.7, weight = 1.0;
    float sumV = 0.0, sumW = 0.0;
    for (int i = 0; i < iters; i++) {
        float a = i < 3 ? windAngle + (fract(float(i) * 0.7548777 + 0.2) - 0.5) * 1.2 : angle;
        vec2 d = vec2(sin(a), cos(a));
        float x = dot(d, pos) * freq + time * 1.5 * sqrt(freq);
        float w = exp(sin(x) - 1.0);
        float dw = w * cos(x);
        pos -= d * dw * weight * 0.26;
        sumV += w * weight;
        sumW += weight;
        weight *= 0.8;
        freq *= 1.18;
        angle += 1232.399963;
    }
    return sumV / sumW;
}

vec3 waveHeight3(vec2 p0, vec2 p1, vec2 p2, float time, int iters) {
    float windAngle = atan(waterWind().x, waterWind().y);
    float angle = 0.0, freq = 1.7, weight = 1.0;
    vec3 sumV = vec3(0.0);
    float sumW = 0.0;
    for (int i = 0; i < iters; i++) {
        float a = i < 3 ? windAngle + (fract(float(i) * 0.7548777 + 0.2) - 0.5) * 1.2 : angle;
        vec2 d = vec2(sin(a), cos(a));
        float tp = time * 1.5 * sqrt(freq);
        float x0 = dot(d, p0) * freq + tp, x1 = dot(d, p1) * freq + tp, x2 = dot(d, p2) * freq + tp;
        float w0 = exp(sin(x0) - 1.0), w1 = exp(sin(x1) - 1.0), w2 = exp(sin(x2) - 1.0);
        p0 -= d * (w0 * cos(x0)) * weight * 0.26;
        p1 -= d * (w1 * cos(x1)) * weight * 0.26;
        p2 -= d * (w2 * cos(x2)) * weight * 0.26;
        sumV += vec3(w0, w1, w2) * weight;
        sumW += weight;
        weight *= 0.8;
        freq *= 1.18;
        angle += 1232.399963;
    }
    return sumV / sumW;
}

float waterSwell(vec2 p, float t) {
    vec2 w = waterWind();
    return sin(dot(p, w) * 0.42 + t * 0.95) * 0.5
         + sin(dot(p, vec2(-w.y, w.x) * 0.8 + w * 0.6) * 0.61 - t * 1.15) * 0.3
         + sin(dot(p, vec2(0.31, -0.95)) * 0.83 + t * 1.35) * 0.2;
}
float waterSwellHeight() { return 0.14 * (0.5 + WAVE_HEIGHT); }

vec2 rainRipple(vec2 p, float time) {
    p *= 1.2;
    vec2 cell = floor(p);
    vec2 grad = vec2(0.0);
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 c = cell + vec2(float(x), float(y));
            float h = hash12(c);
            vec2 center = c + hash22(c);
            float ph = fract(time * 1.1 + h);
            vec2 dv = p - center;
            float d = length(dv);
            float xr = d - ph * 0.9;
            float wave = sin(xr * 28.0) * exp(-xr * xr * 60.0) * (1.0 - ph) * (1.0 - ph);
            grad += (d > 1e-4 ? dv / d : vec2(0.0)) * wave;
        }
    }
    return grad;
}

vec3 waterNormal(vec3 worldPos, float dist, int iters) {
    vec2 p = worldPos.xz;
    float t = frameTimeCounter * WAVE_SPEED;
    const float e = 0.04;
    vec3 hh = waveHeight3(p, p + vec2(e, 0.0), p + vec2(0.0, e), t, iters);
    float h = hh.x, hx = hh.y, hz = hh.z;
    float amp = 0.13 * WAVE_HEIGHT * (1.0 + rainStrength * 0.8) / (1.0 + dist * 0.012);
    vec3 n = normalize(vec3((h - hx) * amp / e, 1.0, (h - hz) * amp / e));
    #ifdef RAIN_RIPPLES
    if (rainStrength > 0.01) {
        vec2 r = rainRipple(p, frameTimeCounter) * rainStrength;
        n = normalize(n + vec3(r.x, 0.0, r.y) * 0.5);
    }
    #endif
    return n;
}
