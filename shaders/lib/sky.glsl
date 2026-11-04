const vec3  TAU_R = vec3(0.0464, 0.1080, 0.2648);
const float TAU_M = 0.028;
const vec3  TAU_O = vec3(0.0065, 0.0175, 0.0008);
const vec3  SUN_E = vec3(3.2);
const vec3  MOON_E = vec3(0.042, 0.050, 0.068);

vec3 getSunDir()   { return normalize(mat3(gbufferModelViewInverse) * sunPosition); }
vec3 getLightDir() { return normalize(mat3(gbufferModelViewInverse) * shadowLightPosition); }

float airmass(float c) {
    c = clamp(c, 0.0, 1.0);
    float z = degrees(acos(c));
    return 1.0 / (c + 0.50572 * pow(max(96.07995 - z, 0.01), -1.6364));
}

float moonBrightness() { return 0.3 + 0.7 * abs(float(moonPhase) - 4.0) / 4.0; }

const float SUN_RADIUS = 0.0115;

float eclipsePhase() {
    #ifdef ECLIPSES
    if (worldDay % 16 != 5) return 9.0;
    return (sunAngle - 0.25) / 0.035;
    #else
    return 9.0;
    #endif
}

float eclipseCoverage() {
    float d = abs(eclipsePhase()) * 2.6;
    const float r = 1.06;
    if (d >= 1.0 + r) return 0.0;
    if (d <= r - 1.0) return 1.0;
    float a = acos(clamp((d * d + 1.0 - r * r) / (2.0 * d), -1.0, 1.0));
    float b = acos(clamp((d * d + r * r - 1.0) / (2.0 * d * r), -1.0, 1.0));
    float k = sqrt(max((-d + 1.0 + r) * (d + 1.0 - r) * (d - 1.0 + r) * (d + 1.0 + r), 0.0));
    return clamp((a + r * r * b - 0.5 * k) / PI, 0.0, 1.0);
}
float sunVisibility() { return 1.0 - 0.995 * eclipseCoverage(); }

float bloodMoon() {
    #ifdef BLOOD_MOON
    return (moonPhase == 0 && worldDay % 5 == 2) ? 1.0 : 0.0;
    #else
    return 0.0;
    #endif
}
vec3 moonTint() { return mix(vec3(1.0), vec3(1.0, 0.26, 0.12) * 0.7, bloodMoon()); }

vec3 skyScatter(vec3 dir, vec3 lDir, vec3 E) {
    float mu = dot(dir, lDir);
    vec3 tauT = TAU_R + vec3(TAU_M);
    vec3 extL = exp(-(tauT + TAU_O) * airmass(lDir.y));
    vec3 extV = exp(-tauT * airmass(dir.y));
    float pR = 0.75 * (1.0 + mu * mu);
    float pM = henyeyGreenstein(mu, 0.76);
    vec3 single = (TAU_R * pR + vec3(TAU_M * pM * 0.9)) / tauT * (1.0 - extV) * extL;
    vec3 multi  = TAU_R / tauT * (1.0 - extV) * exp(-tauT * 1.5) * 0.35;
    float fadeS = smoothstep(-0.18, 0.04, lDir.y);
    float fadeM = smoothstep(-0.05, 0.25, lDir.y);
    return E * (single * fadeS + multi * fadeM);
}

vec3 celestialDir(vec3 dir) {
    float a = sunAngle * TAU;
    float c = cos(a), s = sin(a);
    return vec3(dir.x, dir.y * c - dir.z * s, dir.y * s + dir.z * c);
}

float starField(vec3 dir) {
    vec3 p = celestialDir(dir) * 220.0;
    vec3 cell = floor(p);
    vec3 f = fract(p) - 0.5;
    float h = hash13(cell);
    if (h < 0.9972) return 0.0;
    float b = (h - 0.9972) / 0.0028;
    float twinkle = 0.7 + 0.3 * sin(frameTimeCounter * (2.0 + b * 5.0) + h * 100.0);
    return b * b * twinkle * (1.0 - smoothstep(0.0, 0.42, length(f)));
}

vec3 milkyWay(vec3 dir) {
    vec3 d = celestialDir(dir);
    vec3 bandN = normalize(vec3(0.35, 0.25, 0.9));
    float lat = dot(d, bandN);
    float band = exp(-lat * lat * 28.0);
    if (band < 0.01) return vec3(0.0);
    vec3 q = d * 9.0;
    float glow = fbm(q.xy + q.z * 0.7, 4);
    float dust = smoothstep(0.45, 0.7, fbm(q.yz * 2.1 + 3.7, 4)) * exp(-lat * lat * 120.0);
    float core = exp(-pow(dot(d, normalize(vec3(-0.6, 0.3, 0.2))) - 1.0, 2.0) * 3.0);
    return vec3(0.75, 0.82, 1.0) * band * (0.4 + 0.8 * glow) * (1.0 - 0.8 * dust) * (0.6 + core);
}

float shootingStarSlot(vec3 dir, float period, float seed) {
    float slot = floor(frameTimeCounter / period) + seed * 1000.0;
    float t = fract(frameTimeCounter / period) * period;
    if (t > 0.9 || hash12(vec2(slot, 7.3)) < 0.35) return 0.0;
    float az = hash12(vec2(slot, 1.1)) * TAU;
    float el = mix(0.35, 1.1, hash12(vec2(slot, 2.7)));
    vec3 start = vec3(cos(az) * cos(el), sin(el), sin(az) * cos(el));
    vec3 side = normalize(cross(start, vec3(0.0, 1.0, 0.0)));
    vec3 travel = normalize(side * (hash12(vec2(slot, 3.3)) > 0.5 ? 1.0 : -1.0) - vec3(0.0, 0.35, 0.0));
    float progress = t / 0.9;
    vec3 head = normalize(start + travel * progress * 0.35);
    vec3 tail = normalize(start + travel * max(progress - 0.18, 0.0) * 0.35);

    vec3 seg = head - tail;
    float h = saturate(dot(dir - tail, seg) / max(dot(seg, seg), 1e-6));
    float dist = length(dir - (tail + seg * h));
    float fade = sin(progress * PI);
    return exp(-dist * dist * 4.0e6) * h * h * fade;
}

float shootingStar(vec3 dir) {
    float s = shootingStarSlot(dir, 6.0, 0.0);
    #ifdef METEOR_SHOWERS
    if (worldDay % 7 == 3) {
        for (int i = 1; i <= 4; i++) s += shootingStarSlot(dir, 1.3 + 0.37 * float(i), float(i));
    }
    #endif
    return s;
}

vec3 aurora(vec3 dir, float night) {
    #ifndef AURORA_ALWAYS
    night *= snowyBiome;
    #endif
    if (dir.y < 0.03 || night <= 0.0) return vec3(0.0);
    vec3 acc = vec3(0.0);
    float t = frameTimeCounter * 0.03;
    float jitter = hash12(dir.xz * 1731.0 + dir.y * 97.0);
    for (int i = 0; i < 10; i++) {
        float fi = (float(i) + jitter) / 10.0;
        float height = 1.0 + fi * 0.8;
        vec2 p = dir.xz / dir.y * height;

        float n = fbm(p * 0.35 + vec2(t, -t * 0.6), 3);
        float curtain = exp(-pow((n - 0.5) * 16.0, 2.0));
        curtain *= 0.35 + 0.65 * valueNoise(vec2(n * 70.0 + t * 3.0, fi * 2.0));
        vec3 col = mix(vec3(0.1, 1.0, 0.45), vec3(0.55, 0.2, 1.0), fi * fi);
        acc += col * curtain * (1.0 - fi);
    }
    float horizon = smoothstep(0.03, 0.25, dir.y) * (1.0 - smoothstep(0.7, 1.0, dir.y) * 0.5);
    return acc * 0.02 * horizon * night;
}

vec3 rainbow(vec3 dir, vec3 sunDir) {
    float amount = saturate(wetness * 2.0 - rainStrength * 3.0) * smoothstep(0.0, 0.1, sunDir.y) * smoothstep(0.7, 0.2, sunDir.y);
    if (amount <= 0.0) return vec3(0.0);
    float ang = degrees(acos(clamp(dot(dir, -sunDir), -1.0, 1.0)));
    float x = (ang - 40.3) / 2.4;
    if (x < -0.2 || x > 1.2) return vec3(0.0);
    vec3 spectrum = saturate(vec3(1.0 - abs(x - 0.95) * 2.6, 1.0 - abs(x - 0.55) * 2.8, 1.0 - abs(x - 0.15) * 2.8));
    spectrum += vec3(0.5, 0.0, 0.6) * saturate(1.0 - abs(x + 0.05) * 5.0);
    return spectrum * amount * smoothstep(-0.02, 0.1, dir.y) * 0.12;
}

vec3 iceHalos(vec3 dir, vec3 sunDir) {
    float amount = step(0.55, hash12(vec2(float(worldDay), 3.7))) * (0.4 + 0.6 * snowyBiome) * (1.0 - rainStrength);
    if (amount <= 0.0) return vec3(0.0);
    const float R = 0.3840;
    vec3 tauT = TAU_R + vec3(TAU_M) + TAU_O;
    vec3 sunLight = SUN_E * sunVisibility() * exp(-tauT * airmass(sunDir.y)) * smoothstep(-0.02, 0.05, sunDir.y);
    vec3 moonLight = MOON_E * moonBrightness() * exp(-tauT * airmass(-sunDir.y)) * smoothstep(-0.02, 0.05, -sunDir.y);
    vec3 result = vec3(0.0);
    for (int i = 0; i < 2; i++) {
        vec3 c = i == 0 ? sunDir : -sunDir;
        vec3 light = i == 0 ? sunLight : moonLight * 6.0;
        float theta = acos(clamp(dot(dir, c), -1.0, 1.0));
        float ring = exp(-pow((theta - R) / 0.010, 2.0)) + 0.3 * exp(-pow((theta - R - 0.03) / 0.035, 2.0));
        vec3 tint = mix(vec3(1.0, 0.5, 0.3), vec3(0.85, 0.9, 1.0), saturate((theta - R + 0.008) / 0.025));
        result += ring * tint * light * 0.05;
    }

    float elev = asin(clamp(sunDir.y, -1.0, 1.0));
    if (elev > -0.02 && elev < 0.6) {
        float az = R / max(cos(elev), 0.5);
        float sunAz = atan(sunDir.z, sunDir.x);
        float dirAz = atan(dir.z, dir.x);
        float dirEl = asin(clamp(dir.y, -1.0, 1.0));
        for (int s = -1; s <= 1; s += 2) {
            float dAz = dirAz - (sunAz + float(s) * az);
            dAz = mod(dAz + PI, TAU) - PI;
            vec2 d = vec2(dAz * cos(elev) / 0.035, (dirEl - elev) / 0.02);
            float spot = exp(-dot(d, d));
            float away = saturate(-dAz * float(s) / 0.03 + 0.5);
            vec3 tint = mix(vec3(1.0, 0.55, 0.3), vec3(0.9, 0.95, 1.0), away);
            result += spot * tint * sunLight * 0.3;
        }
    }
    return result * amount;
}

float lightningFlash() {
    #ifdef LIGHTNING_FLASH
    if (lightningBoltPosition.w <= 0.0) return 0.0;
    float f = hash12(vec2(floor(frameTimeCounter * 14.0), 3.1));
    return 0.4 + 0.6 * f * f;
    #else
    return 0.0;
    #endif
}

vec3 getSky(vec3 dir, bool withBodies) {
#if defined WORLD_NETHER
    return toLinear(fogColor) * 0.35;
#elif defined WORLD_END
    vec3 c = vec3(0.010, 0.007, 0.018) + vec3(0.025, 0.012, 0.040) * pow(1.0 - abs(dir.y), 4.0);
    #ifdef STARS
    if (withBodies) c += vec3(0.7, 0.6, 1.0) * starField(dir) * 0.08;
    #endif
    return c;
#else
    vec3 sunDir = getSunDir();
    vec3 moonDir = -sunDir;
    float below = dir.y;
    vec3 d = normalize(vec3(dir.x, max(dir.y, 0.0) + 0.002, dir.z));

    vec3 sky = skyScatter(d, sunDir, SUN_E * sunVisibility()) + skyScatter(d, moonDir, MOON_E * moonBrightness() * moonTint());
    sky += vec3(0.0004, 0.0006, 0.0012);

    if (withBodies && below > 0.0) {
        vec3 ext = exp(-(TAU_R + vec3(TAU_M) + TAU_O) * airmass(d.y));
        float clearSky = 1.0 - rainStrength;

        #ifdef STARS
        float starVis = saturate(1.0 - luminance(sky) * 40.0) * clearSky;
        sky += vec3(0.9, 0.95, 1.0) * starField(dir) * 0.04 * starVis;
        #ifdef MILKY_WAY
        sky += milkyWay(dir) * 0.0025 * starVis;
        #endif
        #ifdef SHOOTING_STARS
        sky += vec3(0.9, 0.95, 1.0) * shootingStar(dir) * 0.3 * starVis;
        #endif
        #endif
        #ifdef AURORA
        sky += aurora(dir, smoothstep(-0.05, -0.2, sunDir.y) * clearSky);
        #endif
        #ifdef RAINBOW
        sky += rainbow(dir, sunDir) * luminance(sky + 0.01) * 6.0;
        #endif
        #ifdef SKY_HALOS
        sky += iceHalos(dir, sunDir) * clearSky;
        #endif

        float cs = dot(dir, sunDir);
        float disk = smoothstep(cos(0.0125), cos(0.0105), cs);
        float rr = saturate(acos(clamp(cs, -1.0, 1.0)) / 0.0115);
        float mu = sqrt(max(1.0 - rr * rr, 0.0));
        vec3 limb = vec3(1.0 - 0.45 * (1.0 - mu), 1.0 - 0.55 * (1.0 - mu), 1.0 - 0.7 * (1.0 - mu));
        #ifdef ECLIPSES
        float ePhase = eclipsePhase();
        if (abs(ePhase) < 1.5) {

            vec3 across = normalize(cross(vec3(0.0, 0.0, 1.0), sunDir));
            vec3 moonC = normalize(sunDir + across * ePhase * 2.6 * SUN_RADIUS);
            float mAng = acos(clamp(dot(dir, moonC), -1.0, 1.0));
            disk *= smoothstep(SUN_RADIUS * 1.06, SUN_RADIUS * 1.06 + 0.0008, mAng);
            float cover = eclipseCoverage();
            float sAng = acos(clamp(cs, -1.0, 1.0));
            float corona = exp(-max(sAng - SUN_RADIUS, 0.0) / 0.012) * step(SUN_RADIUS * 1.06, mAng);
            sky += vec3(0.95, 0.97, 1.0) * corona * smoothstep(0.85, 1.0, cover) * 2.5 * clearSky;
        }
        #endif
        sky += disk * SUN_E * ext * 80.0 * limb * clearSky;

        vec3 up0 = abs(moonDir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
        vec3 right = normalize(cross(up0, moonDir));
        vec3 upv = cross(moonDir, right);
        const float moonR = 0.022;
        vec2 lp = vec2(dot(dir, right), dot(dir, upv)) / moonR;
        float r2 = dot(lp, lp);
        if (r2 < 1.0 && dot(dir, moonDir) > 0.0) {
            vec3 sn = vec3(lp, sqrt(1.0 - r2));
            float phi = float(moonPhase) / 8.0 * TAU;
            vec3 ldir = vec3(sin(phi), 0.0, cos(phi));
            float lit = smoothstep(-0.05, 0.12, dot(sn, ldir));
            float crater = 0.72 + 0.28 * valueNoise(lp * 3.5 + 7.0);
            float edge = 1.0 - smoothstep(0.92, 1.0, sqrt(r2));
            sky += vec3(0.9, 0.95, 1.0) * moonTint() * lit * crater * edge * 0.35 * ext * clearSky;
        }
    }

    sky = mix(sky, vec3(luminance(sky)) * vec3(0.85, 0.9, 1.0) * 0.75, rainStrength * 0.85);
    sky += vec3(0.35, 0.4, 0.6) * lightningFlash() * 0.25 * saturate(dir.y * 3.0 + 0.3);
    sky *= 1.0 - 0.65 * saturate(-below * 4.0);
    return sky;
#endif
}
