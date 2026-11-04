#define RIPPLE_ACT_WRITE
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(64, 64, 1);

#ifdef USE_RIPPLES
#include "/lib/ripples.glsl"
#include "/lib/ripple_kernel.glsl"
#include "/lib/far_occ.glsl"
#ifdef USE_RT_LIGHTS

#include "/lib/voxel_common.glsl"
layout(r32ui) uniform uimage3D voxelImg;
layout(r32ui) uniform uimage3D voxelTriImg;
shared float colLevel[9];
#endif
#ifdef USE_MPM
#include "/lib/mpm.glsl"
#endif

bool readA;
shared vec4 tile[28][28];
shared float occTile[28][28];
shared float waterTile[28][28];
shared float wallTile[28][28];
shared float ghostTile[28][28];
shared float occNowTile[28][28];
shared uint groupBusy;
shared uint groupWalls;
ivec2 lc;
ivec2 gCell;

vec4 loadState(ivec2 t) {
    t &= RIPPLE_RES - 1;
    vec4 s = readA ? imageLoad(rippleImgA, t) : imageLoad(rippleImgB, t);
    return any(isnan(s)) || any(isinf(s)) ? vec4(0.0) : s;
}
void writeState(ivec2 t, vec4 v) {
    if (readA) imageStore(rippleImgB, t, v);
    else       imageStore(rippleImgA, t, v);
}

vec4 rsState(ivec2 o) {
    ivec2 q = lc + o;
    vec4 s = tile[q.y][q.x];
    if (wallTile[q.y][q.x] > 0.5) s.x = ghostTile[q.y][q.x];
    return s;
}

float mirrorHeight(ivec2 o) {
    const ivec2 dirs[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
    int best = 7;
    float sum = 0.0, n = 0.0;
    for (int k = 0; k < 4; k++) {
        for (int d = 1; d <= min(best, 6); d++) {
            ivec2 q = o + dirs[k] * d;
            if (any(lessThan(q, ivec2(0))) || any(greaterThan(q, ivec2(27)))) break;
            if (wallTile[q.y][q.x] > 0.5) continue;
            ivec2 m = o + dirs[k] * (2 * d - 1);
            bool inWater = all(greaterThanEqual(m, ivec2(0))) && all(lessThanEqual(m, ivec2(27))) && wallTile[m.y][m.x] < 0.5;
            float hm = inWater ? tile[m.y][m.x].x : tile[q.y][q.x].x;
            if (d < best) { best = d; sum = 0.0; n = 0.0; }
            sum += hm;
            n += 1.0;
            break;
        }
    }
    return n > 0.0 ? sum / n : 0.0;
}

float rsVertical() {
    float s = 0.0;
    if (groupWalls == 0u) {

        for (int y = -6; y <= 6; y++) {
            for (int x = -6; x <= 6; x++) {
                float k = RIPPLE_KERNEL[(y + 6) * 13 + x + 6];
                if (k != 0.0) s += k * tile[lc.y + y][lc.x + x].x;
            }
        }
        return s;
    }
    for (int y = -6; y <= 6; y++) {
        for (int x = -6; x <= 6; x++) {
            float k = RIPPLE_KERNEL[(y + 6) * 13 + x + 6];
            if (k == 0.0) continue;
            ivec2 q = lc + ivec2(x, y);
            s += k * (wallTile[q.y][q.x] > 0.5 ? ghostTile[q.y][q.x] : tile[q.y][q.x].x);
        }
    }
    return s;
}

float rsWater(ivec2 o) {
    ivec2 w = lc + o;
    return max(max(waterTile[w.y][w.x], max(waterTile[w.y][w.x + 2], waterTile[w.y][w.x - 2])),
               max(waterTile[w.y + 2][w.x], waterTile[w.y - 2][w.x]));
}
float rsBlocked(ivec2 o) { return wallTile[lc.y + o.y][lc.x + o.x]; }
#include "/lib/ripple_step.glsl"

#ifdef USE_RT_LIGHTS

float columnWaterLevel(ivec2 bxz, float ref) {
    ivec3 o = voxelOrigin();
    ivec2 v = bxz - o.xz;
    if (any(lessThan(v, ivec2(0))) || v.x >= VOXEL_SIZE_X || v.y >= VOXEL_SIZE_Z) return -1e4;
    float best = -1e4;
    uint above = VX_DECODE(imageLoad(voxelImg, ivec3(v.x, VOXEL_SIZE_Y - 1, v.y)).r);
    for (int y = VOXEL_SIZE_Y - 2; y >= 0; y--) {
        uint c = VX_DECODE(imageLoad(voxelImg, ivec3(v.x, y, v.y)).r);
        if (c == VX_WATER && above != VX_WATER) {
            float l = float(y + o.y) + 0.889;
            if (abs(l - ref) < abs(best - ref)) best = l;
        }
        above = c;
    }
    return abs(best - ref) < 16.0 ? best : -1e4;
}

bool insideBlockShape(vec3 p) {
    ivec3 v = ivec3(floor(p)) - voxelOrigin();
    if (!inVoxelVolume(v)) return false;
    uint code = VX_DECODE(imageLoad(voxelImg, v).r);
    vec3 f = fract(p);

    if (code == VX_SLAB_BOTTOM) return f.y < 0.5;
    if (code == VX_SLAB_TOP) return f.y >= 0.5;
    if (code == VX_THIN) return f.y < 0.125;
    if (code == VX_POST) return max(abs(f.x - 0.5), abs(f.z - 0.5)) < 0.125;
    if (code != VX_SHAPED) return false;
    const vec3 dirs[4] = vec3[4](vec3(1.0, 0.0013, 0.0007), vec3(-1.0, 0.0011, -0.0009),
                                 vec3(0.0008, 0.0012, 1.0), vec3(-0.0006, 0.0014, -1.0));
    vec3 o = p - vec3(voxelOrigin()), base = vec3(v);
    int odd = 0;
    for (int d = 0; d < 4; d++) {
        vec3 rd = dirs[d];
        uint node = imageLoad(voxelTriImg, v).r;
        int n = 0;
        for (int i = 0; i < 48 && node != 0u && node <= uint(MAX_RT_TRIS); i++) {
            uvec4 a = rtTris[(node - 1u) * 2u];
            vec3 v0 = base + unpackLocal(a.x);
            vec3 e1 = base + unpackLocal(a.y) - v0, e2 = base + unpackLocal(a.z) - v0;
            vec3 pv = cross(rd, e2);
            float det = dot(e1, pv);
            if (abs(det) > 1e-9) {
                float inv = 1.0 / det;
                vec3 tv = o - v0;
                float u = dot(tv, pv) * inv;
                vec3 qv = cross(tv, e1);
                float w = dot(rd, qv) * inv;
                float tt = dot(e2, qv) * inv;
                if (u >= 0.0 && w >= 0.0 && u + w <= 1.0 && tt > 0.0 && tt < 1.5) n++;
            }
            node = a.w;
        }
        odd += n & 1;
    }
    return odd >= 2;
}
#endif

float clockLoad(int field, int slot) { return imageLoad(rippleClockImg, ivec2(field * 2 + slot, 0)).r; }
void clockStore(int field, int slot, float v) { imageStore(rippleClockImg, ivec2(field * 2 + slot, 0), vec4(v)); }
#endif

void main() {
#ifdef USE_RIPPLES
    ivec2 t = ivec2(gl_GlobalInvocationID.xy);
    readA = (frameCounter & 1) == 0;

    const int halfRes = RIPPLE_RES / 2;
    ivec2 camCell  = rippleCell(cameraPosition.xz);
    ivec2 prevCell = rippleCell(previousCameraPosition.xz);
    ivec2 d  = ((t - camCell  + halfRes) & (RIPPLE_RES - 1)) - halfRes;
    ivec2 dp = ((t - prevCell + halfRes) & (RIPPLE_RES - 1)) - halfRes;
    ivec2 cell = camCell + d;

    int slot = frameCounter & 1;
    float dt = clockLoad(0, slot);
    if (!(dt > 0.0 && dt <= 0.05)) dt = 1.0 / 60.0;
    if (frameTime > 0.0) dt = mix(dt, min(frameTime, 0.05), 0.05);

    vec3 eye = cameraPosition - relativeEyePosition;
    vec3 prevEye = previousCameraPosition - relativeEyePosition;
    ivec2 ec = rippleCell(eye.xz);

    float level = 0.0;
    bool found = false;
    for (int k = 0; k < 17 && !found; k++) {
        float a = float(k) * 0.785398;
        ivec2 o = k == 0 ? ivec2(0) : ivec2(round(vec2(cos(a), sin(a)) * (k <= 8 ? 3.0 : 7.0)));
        found = waterLevelAt(ec + o, level);
    }
    #ifdef USE_RT_LIGHTS
    for (int k = -1; k <= 2 && !found; k++) {

        ivec3 q = ivec3(floor(vec3(eye.x, eye.y - 1.62 + float(k), eye.z))) - voxelOrigin();
        if (inVoxelVolume(q) && inVoxelVolume(q + ivec3(0, 1, 0)) && VX_DECODE(imageLoad(voxelImg, q).r) == VX_WATER
            && VX_DECODE(imageLoad(voxelImg, q + ivec3(0, 1, 0)).r) != VX_WATER) {
            level = float(q.y + voxelOrigin().y) + 0.889;
            found = true;
        }
    }
    #endif
    float lastLevel = clockLoad(8, slot), lastAge = clockLoad(9, slot);
    if (found) { lastLevel = level; lastAge = 0.0; }
    else if (lastAge >= 0.0 && lastAge < 20.0 && abs(lastLevel - (eye.y - 1.0)) < 2.5) { level = lastLevel; found = true; lastAge += 1.0; }
    else lastAge = 1e4;
    float ft = max(frameTime, 1e-3);
    RippleBody body = rippleBody(eye, prevEye, found ? level : -1e4, frameTimeCounter, ft);
    if (!found || frameTime <= 0.0 || length(eye - prevEye) > 4.0) body.amount = 0.0;

    vec4 splash = vec4(clockLoad(1, slot), clockLoad(2, slot), clockLoad(3, slot), frameTimeCounter - clockLoad(4, slot));
    if (splash.w < 0.0) splash.z = 0.0;
    float vy = (eye.y - prevEye.y) / ft;
    bool splashNow = found && frameTime > 0.0 && prevEye.y - 1.62 > level && eye.y - 1.62 <= level && vy < -2.5;
    #ifdef USE_MPM
    splashNow = false;
    #endif
    if (splashNow) splash = vec4(eye.xz, saturate((-vy - 2.5) / 15.0) + 0.3, 0.0);

    vec3 ring = vec3(0.0);
    if (body.amount > 0.0 && body.speed > 0.15)
        ring = vec3(rippleRingPos(body, float(frameCounter)),
                    body.amount * saturate(body.speed / 1.5) * clamp(body.speed * ft / 0.04, 0.3, 1.0));
    if (t == ivec2(0)) {
        clockStore(0, 1 - slot, dt);
        clockStore(1, 1 - slot, splash.x);
        clockStore(2, 1 - slot, splash.y);
        clockStore(3, 1 - slot, splash.z);
        clockStore(4, 1 - slot, splashNow ? frameTimeCounter : clockLoad(4, slot));
        clockStore(8, 1 - slot, lastLevel);
        clockStore(9, 1 - slot, lastAge);
    }

    const float simEdge = RIPPLE_RANGE * RIPPLE_CELLS + 60.0;
    ivec2 g0 = ivec2(gl_WorkGroupID.xy) * 16;
    ivec2 gd = ((g0 - camCell + halfRes) & (RIPPLE_RES - 1)) - halfRes;
    ivec2 gMin = ivec2(gd.x <= 0 && gd.x + 15 >= 0 ? 0 : min(abs(gd.x), abs(gd.x + 15)),
                       gd.y <= 0 && gd.y + 15 >= 0 ? 0 : min(abs(gd.y), abs(gd.y + 15)));
    if (float(max(gMin.x, gMin.y)) > simEdge) { writeState(t, vec4(0.0)); return; }

    ivec2 cell0 = camCell + gd;

    vec2 gLo = vec2(cell0), gHi = vec2(cell0 + 15);
    float dBody = length(max(max(gLo - vec2(ec), vec2(ec) - gHi), 0.0));
    bool near = body.amount > 0.0 && dBody < 48.0;
    vec2 sc = splash.xy * RIPPLE_CELLS;
    near = near || (splash.z > 0.0 && splash.w < 1.2 && length(max(max(gLo - sc, sc - gHi), 0.0)) < 64.0);
    #ifdef USE_MPM
    if (mpmActive()) {
        vec2 mc = mpmCentre().xz * RIPPLE_CELLS;
        near = near || length(max(max(gLo - mc, mc - gHi), 0.0)) < (MPM_TANK + 0.5) * RIPPLE_CELLS;
    }
    #endif

    ivec2 gg = ivec2(gl_WorkGroupID.xy);
    int fPrev = frameCounter > 0 ? frameCounter - 1 : FRAME_COUNTER_WRAP - 1;
    bool stirred = near;
    for (int k = 0; k < 9 && !stirred; k++) {
        ivec2 n = (gg + ivec2(k % 3 - 1, k / 3 - 1)) & 63;
        float a = rippleAct[n.y * 64 + n.x];
        stirred = a == float(frameCounter) || a == float(fPrev);
    }
    if (!stirred) { writeState(t, vec4(0.0)); return; }

    if (gl_LocalInvocationIndex == 0u) { groupBusy = 0u; groupWalls = 0u; }
    barrier();
    bool busy = false;
    for (uint i = gl_LocalInvocationIndex; i < 784u; i += 256u) {
        ivec2 o = ivec2(int(i % 28u), int(i / 28u));
        vec4 st = loadState(g0 - 6 + o);
        tile[o.y][o.x] = st;

        vec2 v = imageLoad(rippleInjectImg, contactTexel(cell0 - 6 + o, CONTACT_WATER)).rg;
        int age = frameCounter - int(v.y);
        float inj = age == 0 && v.x > 0.0 ? v.x : (age == 1 && v.x < 0.0 ? -v.x : 0.0);
        occTile[o.y][o.x] = inj;
        busy = busy || abs(st.x) + abs(st.y) + st.z + st.w > 1e-3 || inj > 0.0;
    }
    if (busy) atomicOr(groupBusy, 1u);
    barrier();
    if (groupBusy == 0u && !near) { writeState(t, vec4(0.0)); return; }

    if (gl_LocalInvocationIndex == 0u) rippleAct[gg.y * 64 + gg.x] = float(frameCounter);

    #ifdef USE_RT_LIGHTS

    if (gl_LocalInvocationIndex < 9u) {
        int k = int(gl_LocalInvocationIndex);
        colLevel[k] = columnWaterLevel((cell0 >> 4) + ivec2(k % 3 - 1, k / 3 - 1), found ? level : cameraPosition.y - 1.0);
    }
    barrier();
    #endif
    bool walls = false;
    for (uint i = gl_LocalInvocationIndex; i < 784u; i += 256u) {
        ivec2 o = ivec2(int(i % 28u), int(i / 28u));
        ivec2 c = cell0 - 6 + o;

        vec2 ws = imageLoad(waterLevelImg, contactTexel(c, CONTACT_WATER)).xy;
        int wAge = frameCounter - int(ws.y);
        if (wAge < 0) wAge += FRAME_COUNTER_WRAP;
        bool wet = ws.y > 0.0 && wAge <= 40, wetLong = ws.y > 0.0 && wAge <= 3600;
        float l = ws.x;
        #ifdef USE_RT_LIGHTS

        float vLevel = colLevel[(o.y < 6 ? 0 : (o.y < 22 ? 3 : 6)) + (o.x < 6 ? 0 : (o.x < 22 ? 1 : 2))];
        bool vWater = vLevel > -1e3;
        if (!wetLong && vWater) l = vLevel;
        wet = wet || vWater;
        wetLong = wetLong || vWater;
        #endif
        float inj = occTile[o.y][o.x];

        vec2 bp = (vec2(c) + 0.5) / RIPPLE_CELLS;
        bool solid = wetLong && farCovers(vec3(bp.x, 0.0, bp.y)) && farBlock(ivec3(int(floor(bp.x)), int(floor(l - 0.05)), int(floor(bp.y)))) == 1;
        #ifdef USE_RT_LIGHTS

        solid = solid || (wetLong && insideBlockShape(vec3(bp.x, l - 0.05, bp.y)));
        #endif
        waterTile[o.y][o.x] = wet ? 1.0 : 0.0;

        bool legs = body.amount > 0.5 && rippleBodyDist(body, bp, false) < -0.02;
        bool wall = solid || inj > 0.5 || legs || !wetLong;
        wallTile[o.y][o.x] = wall ? 1.0 : 0.0;
        walls = walls || wall;
    }
    if (walls) atomicOr(groupWalls, 1u);
    barrier();

    for (uint i = gl_LocalInvocationIndex; i < 784u; i += 256u) {
        ivec2 o = ivec2(int(i % 28u), int(i / 28u));
        ghostTile[o.y][o.x] = groupWalls != 0u && wallTile[o.y][o.x] > 0.5 ? mirrorHeight(o) : 0.0;
        float oc = 0.0;
        for (int y = -2; y <= 2; y++) {
            for (int x = -2; x <= 2; x++) {
                ivec2 q = clamp(o + ivec2(x, y), ivec2(0), ivec2(27));
                oc = max(oc, occTile[q.y][q.x] * exp(-0.35 * float(x * x + y * y)));
            }
        }
        occNowTile[o.y][o.x] = oc;
    }
    barrier();
    lc = ivec2(gl_LocalInvocationID.xy) + 6;
    gCell = cell;

    float occ = occNowTile[lc.y][lc.x];
    float dSum = 0.0, freeSum = 0.0, wSum = 0.0;
    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            ivec2 q = lc + ivec2(x, y);
            float g = exp(-float(x * x + y * y) / 3.0);
            dSum += g * (occNowTile[q.y][q.x] - tile[q.y][q.x].w);
            freeSum += g * (1.0 - wallTile[q.y][q.x]);
            wSum += g;
        }
    }

    float displaced = 6.0 * dSum / max(freeSum, 0.3 * wSum);

    float edge = float(max(abs(d.x), abs(d.y)));
    if (edge > simEdge) { writeState(t, vec4(0.0)); return; }

    if (cell != prevCell + dp) { writeState(t, vec4(0.0, 0.0, 0.0, occ)); return; }
    if (frameTime <= 0.0) { writeState(t, rsState(ivec2(0))); return; }

    vec2 pos = (vec2(cell) + 0.5) / RIPPLE_CELLS;
    vec4 s = rippleStep(pos, cell, dt, frameTimeCounter, body, occ, displaced, splash, ring);
    #ifdef USE_MPM

    if (mpmSurfaceWeight(pos) > 0.0) {
        float lvl;
        vec3 hs;
        float wM = waterLevelAt(cell, lvl, 40) ? mpmCover(pos, lvl, hs) : 0.0;
        if (wM > 0.0) {
            float hT = clamp((hs.x - mpmCtl[1].w) * 100.0, -80.0, 80.0);
            float hPrev = rsState(ivec2(0)).x;
            s.x = mix(s.x, hT, wM);
            s.y = mix(s.y, (hT - hPrev) / max(dt, 1e-3), wM);
            s.z = max(s.z, mpmFoamAt(pos) * wM);
        }
    }
    #endif

    s.xyz *= 1.0 - smoothstep(simEdge - 50.0, simEdge - 5.0, edge);
    if (any(isnan(s)) || any(isinf(s))) s = vec4(0.0);
    writeState(t, s);
#endif
}
