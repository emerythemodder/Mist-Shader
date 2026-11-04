#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(64, 64, 1);

#ifdef USE_SNOW_TRACKS
#define SNOW_IMAGES
#include "/lib/snow.glsl"

layout(r32f) uniform image2D rippleClockImg;
#endif

void main() {
#ifdef USE_SNOW_TRACKS
    ivec2 t = ivec2(gl_GlobalInvocationID.xy);
    float dt = clamp(frameTime, 0.0, 0.1);

    int slot = frameCounter & 1;
    vec4 state = vec4(imageLoad(rippleClockImg, ivec2(10 + slot, 0)).r, imageLoad(rippleClockImg, ivec2(12 + slot, 0)).r, 0.0, 0.0);
    if (any(isnan(state))) state = vec4(0.0);
    vec3 move = cameraPosition - previousCameraPosition;
    float stepLen = length(move.xz);
    bool walking = onGround > 0.5 && stepLen < 2.0;
    float walked = state.x + (walking ? stepLen : 0.0);
    const float STRIDE = 0.75;
    float stepIndex = floor(walked / STRIDE);
    bool newStep = walking && stepIndex != state.y && stepLen > 1e-4;
    if (t == ivec2(0)) {
        imageStore(rippleClockImg, ivec2(11 - slot, 0), vec4(mod(walked, 4096.0 * STRIDE)));
        imageStore(rippleClockImg, ivec2(13 - slot, 0), vec4(mod(stepIndex, 4096.0)));
    }

    const int halfRes = SNOW_RES / 2;
    ivec2 camCell  = snowCell(cameraPosition.xz);
    ivec2 prevCell = snowCell(previousCameraPosition.xz);
    ivec2 d  = ((t - camCell  + halfRes) & (SNOW_RES - 1)) - halfRes;
    ivec2 dp = ((t - prevCell + halfRes) & (SNOW_RES - 1)) - halfRes;
    ivec2 cell = camCell + d;

    vec4 v = imageLoad(snowDeformImg, t);
    if (cell != prevCell + dp || any(isnan(v)) || max(abs(d.x), abs(d.y)) > int(30.0 * SNOW_CELLS)) v = vec4(0.0);
    v.g -= move.y;

    float inj = 0.0;
    float snowHere = 0.0;
    if (snowLevelAt(cell, snowHere)) {
        for (int y = -2; y <= 2; y++) {
            for (int x = -2; x <= 2; x++) {
                vec2 u = imageLoad(rippleInjectImg, contactTexel(cell + ivec2(x, y), CONTACT_BODY)).xy;
                if (int(u.y) != frameCounter) continue;
                inj = max(inj, snowPress(u.x, snowHere) * exp(-0.45 * float(x * x + y * y)));
            }
        }
    }
    vec2 pos = (vec2(cell) + 0.5) / SNOW_CELLS;
    if (inj > 0.0) inj = saturate(inj * (0.75 + 0.5 * valueNoise(pos * 9.0)) * 1.25);

    if (newStep) {
        vec3 feet = cameraPosition - relativeEyePosition - vec3(0.0, 1.62, 0.0);
        vec2 fwd = normalize(move.xz);
        vec2 side = vec2(-fwd.y, fwd.x);
        float parity = mod(stepIndex, 2.0) < 1.0 ? 1.0 : -1.0;
        vec2 rel = pos - (feet.xz + side * 0.14 * parity);
        vec2 local = vec2(dot(rel, side), dot(rel, fwd)) / vec2(0.11, 0.17);
        float edge = 0.75 + 0.25 * valueNoise(pos * 25.0);
        inj = max(inj, 1.0 - smoothstep(0.6 * edge, 1.0 * edge, length(local)));
    }

    float level = 0.0;
    if (inj > 0.0 && snowLevelAt(cell, level)) {
        float stored = v.g + cameraPosition.y;
        if (v.r < 0.01 || abs(stored - level) > 0.45) v = vec4(0.0, level - cameraPosition.y, 0.0, 0.0);
        v.r = max(v.r, inj);
        v.g = level - cameraPosition.y;
        v.a = min(v.a + inj * 0.04, 1.0);
    }

    float around = 0.0;
    for (int k = 0; k < 8; k++) {
        float a = float(k) * 0.785398;
        around = max(around, imageLoad(snowDeformImg, snowTexel(cell + ivec2(round(vec2(cos(a), sin(a)) * 2.0)))).r);
    }
    v.b = max(v.b * exp(-dt * 0.5), saturate((around - v.r) * 1.5) * (1.0 - v.r));

    float refill = mix(1.0 / 1800.0, 1.0 / 35.0, saturate(snowCover * 3.0));
    v.r *= exp(-dt * refill);
    v.b *= exp(-dt * refill);
    v.a *= exp(-dt * refill * 0.5);
    if (v.r < 0.002 && v.b < 0.002 && v.a < 0.002) v = vec4(0.0);
    imageStore(snowDeformImg, t, v);
#endif
}
