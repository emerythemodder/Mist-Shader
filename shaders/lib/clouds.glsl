uniform sampler3D cloudShapeTex;
uniform sampler3D cloudDetailTex;

#define CU_THICKNESS 520.0
#define CU_EXTINCTION 0.055
#define CU_SHAPE_SCALE (1.0 / 2600.0)
#define CU_DETAIL_SCALE (1.0 / 210.0)

float cuBase() { return float(CLOUD_ALTITUDE); }
float cuTop()  { return float(CLOUD_ALTITUDE) + CU_THICKNESS; }
float acAltitude() { return float(CLOUD_ALTITUDE) + 1700.0; }
float ciAltitude() { return float(CLOUD_ALTITUDE) + 4200.0; }

vec2 cloudWind() { return vec2(1.0, 0.35) * frameTimeCounter * 3.0; }

float remap01(float x, float a, float b) { return saturate((x - a) / (b - a)); }

float cloudWeather(vec2 xz) {
    vec2 q = xz + cloudWind() * 0.4;
    float big = textureLod(cloudShapeTex, vec3(q * (1.0 / 15000.0), 0.37), 0.0).r;
    float mid = textureLod(cloudShapeTex, vec3(q * (1.0 / 5600.0) + 0.21, 0.71), 0.0).g;
    float w = (big - 0.62) * 1.6 + (mid - 0.45) * 0.7;
    return saturate(mix(CLOUD_COVERAGE, 0.95, rainStrength) + w * 0.55);
}

float cumulusDensity(vec3 wp, bool detail) {
    float h = (wp.y - cuBase()) / CU_THICKNESS;
    if (h <= 0.0 || h >= 1.0) return 0.0;
    float cov = cloudWeather(wp.xz);
    if (cov < 0.02) return 0.0;

    float top = mix(0.42, 1.0, cov * cov);
    float profile = smoothstep(0.0, 0.06, h) * (1.0 - smoothstep(top * 0.55, top, h));
    if (profile <= 0.0) return 0.0;

    vec3 p = wp;
    p.xz += cloudWind() + vec2(0.9, 0.3) * h * 260.0;
    vec4 n = textureLod(cloudShapeTex, p * CU_SHAPE_SCALE, 0.0);
    float cells = n.g * 0.625 + n.b * 0.25 + n.a * 0.125;
    float shape = remap01(n.r, cells * 0.55 + 0.15, 1.0);
    float d = remap01(shape * profile, 1.0 - cov * 1.08, 1.0);
    if (d <= 0.0) return 0.0;
    if (detail) {

        vec3 dn = textureLod(cloudDetailTex, p * CU_DETAIL_SCALE + vec3(0.0, frameTimeCounter * 0.003, 0.0), 0.0).rgb;
        float dd = dn.r * 0.625 + dn.g * 0.25 + dn.b * 0.125;
        float erode = mix(dd, 1.0 - dd, saturate(h * 5.0));
        d = remap01(d, erode * 0.5, 1.0);
    }

    return saturate((d - 0.015) * 2.6) * CU_EXTINCTION;
}

float cloudScattering(float od, float mu, float powder) {
    float s = 0.0, a = 1.0, b = 1.0, c = 1.0;
    for (int i = 0; i < 4; i++) {
        float phase = mix(henyeyGreenstein(mu, 0.8 * c), henyeyGreenstein(mu, -0.2 * c), 0.25);
        s += a * exp(-od * b) * phase;
        a *= 0.5; b *= 0.4; c *= 0.6;
    }
    return s * powder;
}

vec4 renderCumulus(vec3 dir, vec3 direct, vec3 ambient, float dither, out float meanT) {
    meanT = 1e5;
    float lo = cuBase(), hi = cuTop();
    float cy = cameraPosition.y;
    float t0, t1;
    if (cy < lo) {
        if (dir.y < 0.008) return vec4(0.0, 0.0, 0.0, 1.0);
        t0 = (lo - cy) / dir.y;
        t1 = (hi - cy) / dir.y;
    } else if (cy > hi) {
        if (dir.y > -0.008) return vec4(0.0, 0.0, 0.0, 1.0);
        t0 = (hi - cy) / dir.y;
        t1 = (lo - cy) / dir.y;
    } else {
        t0 = 0.0;
        t1 = dir.y > 0.008 ? (hi - cy) / dir.y : (dir.y < -0.008 ? (lo - cy) / dir.y : 9000.0);
    }
    if (t0 > 30000.0) return vec4(0.0, 0.0, 0.0, 1.0);
    t1 = min(t1, t0 + 9000.0);

    vec3 L = getLightDir();
    float mu = dot(dir, L);

    int steps = int(float(CLOUD_STEPS) * mix(1.0, 1.75, saturate(1.0 - abs(dir.y) * 3.0)));
    float stepL = (t1 - t0) / float(steps);

    vec3 scat = vec3(0.0);
    float T = 1.0, tSum = 0.0, wSum = 0.0;
    for (int i = 0; i < 64; i++) {
        if (i >= steps) break;
        float t = t0 + stepL * (float(i) + dither);
        vec3 wp = cameraPosition + dir * t;
        float d = cumulusDensity(wp, true);
        if (d < 1e-5) continue;
        float h = saturate((wp.y - lo) / CU_THICKNESS);

        float od = 0.0, ls = 18.0, lt = 0.0;
        for (int j = 0; j < 6; j++) {
            lt += ls;
            od += cumulusDensity(wp + L * lt, false) * ls;
            ls *= 1.9;
        }

        float powder = mix(1.0, 1.0 - exp(-d * 90.0), 0.55 * saturate(0.6 - 0.4 * mu));

        float skyAbove = exp(-cumulusDensity(wp + vec3(0.0, 45.0, 0.0), false) * 45.0);
        vec3 S = direct * cloudScattering(od, mu, powder) * 2.2
               + ambient * mix(0.35, 1.25, sqrt(h)) * mix(0.55, 1.0, skyAbove)
               + direct * (0.06 * (1.0 - h) * saturate(L.y));

        float dT = exp(-d * stepL);
        scat += T * S * (1.0 - dT);
        tSum += t * T * (1.0 - dT);
        wSum += T * (1.0 - dT);
        T *= dT;
        if (T < 0.01) break;
    }
    if (wSum > 0.0) meanT = tSum / wSum;
    return vec4(scat, T);
}

vec4 renderAltocumulus(vec3 dir, vec3 direct, vec3 ambient, out float dist) {
    dist = 1e5;
    float alt = acAltitude();
    if (dir.y < 0.012 || cameraPosition.y > alt) return vec4(0.0, 0.0, 0.0, 1.0);
    float t = (alt - cameraPosition.y) / dir.y;
    dist = t;
    vec2 p = cameraPosition.xz + dir.xz * t + cloudWind() * 1.6;

    float sheet = remap01(textureLod(cloudShapeTex, vec3(p * (1.0 / 11000.0), 0.53), 0.0).r, 0.66 - rainStrength * 0.2, 0.8);
    if (sheet <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);
    vec2 q = vec2(p.x * 1.0, p.y * 1.6);
    vec4 n = textureLod(cloudShapeTex, vec3(q * (1.0 / 2400.0), 0.27), 0.0);
    float cells = n.b * 0.6 + n.a * 0.25 + n.g * 0.15;
    float d = remap01(cells, 0.6 - sheet * 0.1, 0.84) * sheet;
    if (d <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);

    vec3 L = getLightDir();
    float mu = dot(dir, L);
    vec2 toL = L.xz / max(L.y, 0.15) * 12.0;
    vec4 ns = textureLod(cloudShapeTex, vec3((q + toL) * (1.0 / 2400.0), 0.27), 0.0);
    float occl = remap01(ns.b * 0.6 + ns.a * 0.25 + ns.g * 0.15, 0.6, 0.84);
    vec3 S = direct * cloudScattering(occl * 2.5, mu, 1.0) * 1.3 + ambient * 1.0;
    float T = exp(-d * 1.6);
    return vec4(S * (1.0 - T), T);
}

vec4 renderCirrus(vec3 dir, vec3 direct, vec3 ambient, out float dist) {
    dist = 1e5;
    float alt = ciAltitude();
    if (dir.y < 0.008 || cameraPosition.y > alt) return vec4(0.0, 0.0, 0.0, 1.0);
    float t = (alt - cameraPosition.y) / dir.y;
    dist = t;
    vec2 p = cameraPosition.xz + dir.xz * t + cloudWind() * 3.0;
    vec2 w = normalize(vec2(1.0, 0.35));
    vec2 q = vec2(dot(p, w), dot(p, vec2(-w.y, w.x)));
    float band = remap01(textureLod(cloudShapeTex, vec3(q * (1.0 / 16000.0), 0.81), 0.0).r, 0.62, 0.78);
    if (band <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);

    vec2 r = q * vec2(1.0 / 5200.0, 1.0 / 520.0);
    r.y += (textureLod(cloudShapeTex, vec3(q * (1.0 / 3000.0), 0.11), 0.0).r - 0.5) * 0.8;
    float fib = textureLod(cloudShapeTex, vec3(r, 0.63), 0.0).r * 0.65 + textureLod(cloudShapeTex, vec3(r * 2.7, 0.29), 0.0).r * 0.35;
    float d = remap01(fib, 0.6, 0.86) * band * 0.25;
    if (d <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);

    float mu = dot(dir, getLightDir());
    float phase = mix(henyeyGreenstein(mu, 0.75), henyeyGreenstein(mu, -0.2), 0.3);
    vec3 S = direct * phase * 0.8 + ambient * 1.1;
    float T = exp(-d * 1.4);
    return vec4(S * (1.0 - T), T);
}

vec4 aerialFade(vec4 layer, float dist) {
    float f = exp(-dist * 0.000075);
    return vec4(layer.rgb * f, mix(1.0, layer.a, f));
}

vec3 cloudDirectLight(float alt) {
#if defined WORLD_OVERWORLD
    float h = max(alt - 63.0, 0.0);
    float dip = sqrt(2.0 * h / 6.371e6);
    vec3 tauA = TAU_R * exp(-h / 8000.0) + vec3(TAU_M) * exp(-h / 1200.0) + TAU_O;
    vec3 sd = getSunDir();
    vec3 sunL  = SUN_E * sunVisibility() * exp(-tauA * airmass(sd.y + dip)) * smoothstep(-0.03, 0.08, sd.y + dip);
    vec3 moonL = MOON_E * moonBrightness() * moonTint() * exp(-tauA * airmass(-sd.y + dip)) * smoothstep(-0.03, 0.08, -sd.y + dip);
    return (sunL + moonL) * (1.0 - rainStrength * 0.9);
#else
    return vec3(0.0);
#endif
}

vec4 renderClouds(vec3 dir, vec3 direct, vec3 ambient, float dither) {
    float dCu, dAc, dCi;
    vec4 cu = aerialFade(renderCumulus(dir, cloudDirectLight(0.5 * (cuBase() + cuTop())), ambient, dither, dCu), dCu);
    vec4 result = cu;
    #ifdef ALTOCUMULUS_CLOUDS
    vec4 ac = aerialFade(renderAltocumulus(dir, cloudDirectLight(acAltitude()), ambient, dAc), dAc);
    result = vec4(result.rgb + result.a * ac.rgb, result.a * ac.a);
    #endif
    #ifdef CIRRUS_CLOUDS
    vec4 ci = aerialFade(renderCirrus(dir, cloudDirectLight(ciAltitude()), ambient, dCi), dCi);
    result = vec4(result.rgb + result.a * ci.rgb, result.a * ci.a);
    #endif
    return result;
}

float cloudShadow(vec3 worldPos) {
    vec3 L = getLightDir();
    if (L.y < 0.05 || worldPos.y > cuBase()) return 1.0;
    vec3 p = worldPos + L * ((cuBase() + CU_THICKNESS * 0.3 - worldPos.y) / L.y);
    float d = cumulusDensity(p, false);
    return mix(1.0, exp(-d * 260.0), 0.9);
}
