#ifdef IEXT_ENABLED
    uniform bool IEXT_KEY_0;
    uniform vec3 playerLookVector;
    #define USE_FLASHLIGHT
#endif

#ifdef USE_FLASHLIGHT
bool flashlightOn() { return IEXT_KEY_0; }

void flashlightFrame(out vec3 origin, out vec3 dir) {
    dir = normalize(playerLookVector);
    if (any(isnan(dir)) || dot(dir, dir) < 0.5) dir = -normalize(gbufferModelViewInverse[2].xyz);
    vec3 right = normalize(cross(dir, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
    vec3 up = cross(right, dir);
    origin = -relativeEyePosition + right * 0.28 - up * 0.22 + dir * 0.2;
}

float flashlightBeam(float cosA) {
    float a = acos(clamp(cosA, -1.0, 1.0));
    float hot = 1.0 - smoothstep(0.06, 0.13, a);
    float spill = 1.0 - smoothstep(0.2, 0.42, a);
    float ring = exp(-pow((a - 0.12) / 0.025, 2.0)) * 0.15;
    return hot + spill * 0.12 + ring;
}

#define FLASHLIGHT_COLOR vec3(1.0, 0.95, 0.86)

vec3 flashlightLight(vec3 playerPos, vec3 normal, out vec3 toLight) {
    toLight = vec3(0.0, 1.0, 0.0);
    if (!flashlightOn()) return vec3(0.0);
    vec3 origin, dir;
    flashlightFrame(origin, dir);
    vec3 d = playerPos - origin;
    float dist = length(d);
    toLight = -d / max(dist, 1e-4);
    float beam = flashlightBeam(dot(-toLight, dir));
    float NdotL = saturate(dot(normal, toLight));
    return FLASHLIGHT_COLOR * (FLASHLIGHT_STRENGTH * 45.0) * beam * NdotL / (dist * dist + 0.25);
}

vec3 flashlightBeamInAir(vec3 playerPos, float density) {
    if (!flashlightOn() || density <= 0.0) return vec3(0.0);
    vec3 origin, dir;
    flashlightFrame(origin, dir);
    vec3 rd = normalize(playerPos);
    float len = min(length(playerPos), 48.0);

    vec3 acc = vec3(0.0);
    const int N = 8;
    for (int i = 0; i < N; i++) {
        float t = len * pow((float(i) + 0.5) / float(N), 2.0);
        float dt = len * (pow((float(i) + 1.0) / float(N), 2.0) - pow(float(i) / float(N), 2.0));
        vec3 p = rd * t - origin;
        float r = length(p);
        float beam = flashlightBeam(dot(p / max(r, 1e-3), dir));
        acc += FLASHLIGHT_COLOR * beam / (r * r + 0.3) * exp(-density * t) * dt;
    }
    return acc * density * (FLASHLIGHT_STRENGTH * 45.0) * 0.08;
}
#endif
