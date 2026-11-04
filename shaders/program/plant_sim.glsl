#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(16, 16, 1);

#ifdef USE_PLANT_BEND
#include "/lib/contact.glsl"
#define BEND_RES 256
#define BEND_CELLS 4.0
layout(rgba16f) uniform image2D bendImg;

shared float presTile[20][20];
shared float yTile[20][20];
#endif

void main() {
#ifdef USE_PLANT_BEND
    ivec2 t = ivec2(gl_GlobalInvocationID.xy);
    float dt = clamp(frameTime, 0.0, 0.05);

    const int halfRes = BEND_RES / 2;
    ivec2 camCell  = ivec2(floor(cameraPosition.xz * BEND_CELLS));
    ivec2 prevCell = ivec2(floor(previousCameraPosition.xz * BEND_CELLS));
    ivec2 d  = ((t - camCell  + halfRes) & (BEND_RES - 1)) - halfRes;
    ivec2 dp = ((t - prevCell + halfRes) & (BEND_RES - 1)) - halfRes;
    ivec2 cell = camCell + d;
    ivec2 g0 = ivec2(gl_WorkGroupID.xy) * 16;
    ivec2 cell0 = camCell + (((g0 - camCell + halfRes) & (BEND_RES - 1)) - halfRes);

    vec3 eye = cameraPosition - relativeEyePosition;
    vec3 prevEye = previousCameraPosition - relativeEyePosition;
    vec2 pVel = (eye.xz - prevEye.xz) / max(frameTime, 1e-3);
    if (length(eye - prevEye) > 4.0) pVel = vec2(0.0);

    const int sub = int(RIPPLE_CELLS / BEND_CELLS);
    for (uint i = gl_LocalInvocationIndex; i < 400u; i += 256u) {
        ivec2 o = ivec2(int(i % 20u), int(i / 20u));
        ivec2 bc = cell0 - 2 + o;
        float y = 1e9;
        for (int k = 0; k < sub * sub; k++) {
            ivec2 cc = bc * sub + ivec2(k % sub, k / sub);
            vec2 u = imageLoad(rippleInjectImg, contactTexel(cc, CONTACT_BODY)).xy;
            if (int(u.y) == frameCounter) y = min(y, u.x);
        }
        vec2 c = (vec2(bc) + 0.5) / BEND_CELLS;
        if (length(c - eye.xz) < 0.32) y = min(y, eye.y - 1.62);
        presTile[o.y][o.x] = y < 1e8 ? 1.0 : 0.0;
        yTile[o.y][o.x] = y;
    }
    barrier();

    ivec2 lc = ivec2(gl_LocalInvocationID.xy) + 2;
    vec4 s = imageLoad(bendImg, ivec2((t.x & (BEND_RES - 1)) * 2, t.y));
    vec4 s2 = imageLoad(bendImg, ivec2((t.x & (BEND_RES - 1)) * 2 + 1, t.y));
    if (cell != prevCell + dp || any(isnan(s)) || any(isnan(s2))) { s = vec4(0.0); s2 = vec4(-1e4, 0.0, 0.0, 0.0); }

    float P = 0.0, wsum = 0.0, yMin = 1e9;
    vec2 grad = vec2(0.0);
    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            float w = exp(-0.5 * float(x * x + y * y));
            float pr = presTile[lc.y + y][lc.x + x];
            P += pr * w;
            grad += pr * w * vec2(x, y);
            wsum += w;
            if (abs(x) <= 1 && abs(y) <= 1 && pr > 0.0) yMin = min(yMin, yTile[lc.y + y][lc.x + x]);
        }
    }
    P /= wsum;
    grad /= wsum;
    float amount = saturate(P * 2.2);
    vec2 target = vec2(0.0);
    if (amount > 0.0) {
        vec2 away = -grad;

        vec2 c = (vec2(cell) + 0.5) / BEND_CELLS;
        vec2 fallback = length(c - eye.xz) < 0.8 && length(pVel) > 0.3 ? normalize(pVel) : normalize(hash22(vec2(cell)) - 0.5 + 1e-4);
        vec2 dir = normalize(away + fallback * max(0.06 - length(away), 0.0) * 12.0 + 1e-5);
        target = dir * amount;
        s2.x = yMin < 1e8 ? yMin : s2.x;
    }

    float pushing = step(0.02, amount);
    float k = mix(55.0, 260.0, pushing);
    float c = 2.0 * mix(0.32, 0.8, pushing) * sqrt(k);
    vec2 acc = k * (target - s.xy) - c * s.zw;
    s.zw += acc * dt;
    s.xy += s.zw * dt;
    float m = length(s.xy);
    if (m > 1.2) s.xy *= 1.2 / m;
    if (m < 0.003 && length(s.zw) < 0.01) { s = vec4(0.0); }

    imageStore(bendImg, ivec2((t.x & (BEND_RES - 1)) * 2, t.y), s);
    imageStore(bendImg, ivec2((t.x & (BEND_RES - 1)) * 2 + 1, t.y), s2);
#endif
}
