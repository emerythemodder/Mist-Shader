#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

#ifdef USE_MPM
#define MPM_ACCESS
#include "/lib/mpm.glsl"
#include "/lib/far_occ.glsl"
#if MPM_PASS == 0 || MPM_PASS == 1
#include "/lib/contact.glsl"

bool waterAt(vec2 xz, out float level) {
    ivec2 rc = ivec2(floor(xz * RIPPLE_CELLS));
    for (int k = 0; k < 9; k++) {
        vec2 st = imageLoad(waterLevelImg, contactTexel(rc + ivec2(k % 3 - 1, k / 3 - 1) * 2, CONTACT_WATER)).xy;
        int age = frameCounter - int(st.y);
        if (age < 0) age += 720720;
        if (age <= 60 && st.y > 0.0) { level = st.x; return true; }
    }
    level = 0.0;
    return false;
}
#endif

#ifndef MPM_EOS
#define MPM_EOS 2
#endif
#define MPM_CFL 0.5
#define MPM_BODY_R 0.3

float mpmDt() { return mpmStep.y; }
int mpmSubsteps() { return int(mpmStep.x + 0.5); }
bool mpmSolidBlock(vec3 wp) { return farBlock(ivec3(floor(wp))) == 1; }
bool mpmSolidNode(ivec3 c) {
    if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, ivec3(MPM_NX, MPM_NY, MPM_NZ)))) return false;
    int n = mpmNode(c);
    return (mpmSolid[n >> 5] & (1u << uint(n & 31))) != 0u;
}

void mpmBody(int k, out vec3 a, out vec3 b, out vec3 vel) {
    float n = max(mpmStep.x, 1.0);
    vec3 eye = mix(mpmCtl[2].xyz, mpmCtl[3].xyz, float(k + 1) / n);
    a = eye - vec3(0.0, 1.62 - 0.9, 0.0);
    b = vec3(MPM_BODY_R, 0.9, MPM_BODY_R);
    vel = (mpmCtl[3].xyz - mpmCtl[2].xyz) / max(n * mpmStep.y, 1e-4);
}

float mpmBodyDist(vec3 p, vec3 a, vec3 b, out vec3 nrm) {
    vec3 d = p - a;
    vec3 q = abs(d) - b;
    if (max(q.x, max(q.y, q.z)) < 0.0) {

        nrm = q.x > q.y && q.x > q.z ? vec3(sign(d.x), 0.0, 0.0) : (q.y > q.z ? vec3(0.0, sign(d.y), 0.0) : vec3(0.0, 0.0, sign(d.z)));
        return max(q.x, max(q.y, q.z));
    }
    vec3 e = max(q, 0.0);
    float l = length(e);
    nrm = sign(d) * e / max(l, 1e-5);
    return l;
}

void mpmStencil(vec3 g, out ivec3 base, out vec3 fx, out vec3 w[3]) {
    base = ivec3(floor(g - 0.5));
    fx = g - vec3(base);
    w = vec3[3](0.5 * (1.5 - fx) * (1.5 - fx), 0.75 - (fx - 1.0) * (fx - 1.0), 0.5 * (fx - 0.5) * (fx - 0.5));
}

void mpmScatter(vec3 p, vec3 v, mat3 C, float rho) {
    ivec3 base; vec3 fx; vec3 w[3];
    mpmStencil((p - mpmOrigin()) / MPM_DX, base, fx, w);
    const float vol = MPM_DX * MPM_DX * MPM_DX / float(MPM_PPC);
    const float mass = vol;

    #if MPM_EOS == 1
    float p_ = MPM_C * MPM_C * max(rho - 1.0, 0.0);
    float stress = mpmDt() * vol * 4.0 / (MPM_DX * MPM_DX) * p_ / max(rho, 1e-3);
    #else
    float J_ = rho;
    float p_ = MPM_C * MPM_C * max(1.0 - J_, 0.0);
    float stress = mpmDt() * vol * 4.0 / (MPM_DX * MPM_DX) * J_ * p_;
    #endif
    mat3 affine = mat3(stress) + mass * C;
    for (int k = 0; k < 27; k++) {
        ivec3 o = ivec3(k % 3, (k / 3) % 3, k / 9);
        ivec3 c = base + o;
        if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, ivec3(MPM_NX, MPM_NY, MPM_NZ)))) continue;
        float wt = w[o.x].x * w[o.y].y * w[o.z].z;
        vec3 dpos = (vec3(o) - fx) * MPM_DX;
        vec3 mom = clamp(wt * (mass * v + affine * dpos) * MPM_FIX, -2e7, 2e7);
        int n = mpmNode(c);
        atomicAdd(mpmGrid[n].x, int(round(mom.x)));
        atomicAdd(mpmGrid[n].y, int(round(mom.y)));
        atomicAdd(mpmGrid[n].z, int(round(mom.z)));
        atomicAdd(mpmGrid[n].w, int(round(wt * mass * MPM_FIX)));
    }
}
#endif

void main() {
#ifdef USE_MPM
#if MPM_PASS == 0

    vec3 eye = cameraPosition - relativeEyePosition;
    vec3 prevEye = previousCameraPosition - relativeEyePosition;
    float ft = max(frameTime, 1e-3);
    vec4 c0 = mpmCtl[0];
    if (mpmCtl[3].w != MPM_MAGIC) c0 = vec4(0.0, 0.0, 0.0, -1.0);
    bool teleport = length(eye - prevEye) > 4.0;

    float vBody = teleport ? 0.0 : length(eye - prevEye) / ft;
    float dtMax = MPM_CFL * MPM_DX / (MPM_C + max(vBody, 3.0));
    float simT = min(clamp(frameTime, 0.0, 0.1), float(MPM_MAXSUB) * dtMax);
    int nsub = frameTime > 0.0 ? clamp(int(ceil(simT / dtMax - 1e-3)), 1, MPM_MAXSUB) : 0;
    if (c0.w >= 0.0) c0.w += simT;
    if (c0.w >= MPM_LIFE) c0.w = -1.0;
    bool start = false;
    float level;
    float vy = (eye.y - prevEye.y) / ft;
    if (frameTime > 0.0 && !teleport && waterAt(eye.xz, level)) {
        float feet = eye.y - 1.62, prevFeet = prevEye.y - 1.62;

        if (prevFeet > level && feet <= level && vy < -2.5 && !(c0.w >= 0.0 && c0.w < 0.6)) {
            vec2 hit = mix(prevEye.xz, eye.xz, saturate((prevFeet - level) / max(prevFeet - feet, 1e-4)));
            c0 = vec4(vec3(hit.x, level, hit.y) - vec3(float(MPM_NX / 2) * MPM_DX, MPM_FLOOR, float(MPM_NZ / 2) * MPM_DX), 0.0);
            mpmCtl[1] = vec4((eye - prevEye) / ft, level);
            start = true;
        }
    }
    mpmCtl[0] = c0;
    mpmCtl[2] = vec4(prevEye, start ? 1.0 : 0.0);
    mpmCtl[3] = vec4(eye, MPM_MAGIC);
    mpmStep = vec4(float(nsub), nsub > 0 ? simT / float(nsub) : 0.0, vBody, start ? 0.0 : mpmStep.w);
    mpmCount = ivec4(start ? 0 : mpmCount.x, 0, 0, 0);

#elif MPM_PASS == 1

    if (mpmCtl[2].w < 0.5) return;
    uint i = gl_GlobalInvocationID.x;

    if (i < uint(MPM_NODES)) { mpmGrid[i] = ivec4(0); mpmSpray[i] = 0; }
    if (i < uint(MPM_NX * MPM_NZ)) mpmFoamAcc[i] = 0;
    if (i < uint(MPM_NODES / 32)) {
        uint bits = 0u;
        for (int j = 0; j < 32; j++) {
            int n = int(i) * 32 + j;
            ivec3 c = ivec3(n % MPM_NX, n / (MPM_NX * MPM_NZ), (n / MPM_NX) % MPM_NZ);
            if (mpmSolidBlock(mpmOrigin() + vec3(c) * MPM_DX)) bits |= 1u << uint(j);
        }
        mpmSolid[i] = bits;
    }

    const int NL = 48, NV = 20;
    if (i >= uint(NL * NL * NV)) return;
    int ix = int(i) % NL, iz = (int(i) / NL) % NL, iy = int(i) / (NL * NL);
    float rest = mpmCtl[1].w;
    vec3 centre = mpmCentre();
    float depth = MPM_SETTLE((float(NV - 1 - iy) + 0.5) * 0.05);
    vec3 p = vec3(centre.x + (float(ix) - float(NL - 1) * 0.5) * 0.05, rest - depth,
                  centre.z + (float(iz) - float(NL - 1) * 0.5) * 0.05);
    float lvl;
    if (length(p.xz - centre.xz) > MPM_TANK || mpmSolidBlock(p)) return;
    if (!waterAt(p.xz, lvl) || abs(lvl - rest) > 0.3 || p.y > lvl) return;
    depth = lvl - p.y;
    int slot = atomicAdd(mpmCount.x, 1);
    if (slot >= MPM_MAXP) return;
    uint s = uint(slot) * 5u;
    #if MPM_EOS == 1
    mpmP[s] = vec4(p, 1.0 / (1.0 - 9.81 * depth / (MPM_C * MPM_C)));
    #else
    mpmP[s] = vec4(p, 1.0 - 9.81 * depth / (MPM_C * MPM_C));
    #endif
    mpmP[s + 1u] = vec4(0.0, 0.0, 0.0, 1.0);
    mpmP[s + 2u] = vec4(0.0);
    mpmP[s + 3u] = vec4(0.0);
    mpmP[s + 4u] = vec4(0.0);

#elif MPM_PASS == 2

    if (!mpmActive() || mpmSubsteps() < 1) return;
    uint i = gl_GlobalInvocationID.x;
    if (i >= uint(min(mpmCount.x, MPM_MAXP))) return;
    vec4 pj = mpmP[i * 5u], va = mpmP[i * 5u + 1u];
    if (va.w < 0.5) return;
    mpmScatter(pj.xyz, va.xyz, mat3(mpmP[i * 5u + 2u].xyz, mpmP[i * 5u + 3u].xyz, mpmP[i * 5u + 4u].xyz), pj.w);

#elif MPM_PASS == 3

    if (!mpmActive() || MPM_K >= mpmSubsteps()) return;
    int n = int(gl_GlobalInvocationID.x);
    if (n >= MPM_NODES) return;
    ivec4 gi = mpmGrid[n];
    mpmGrid[n] = ivec4(0);
    if (MPM_K == mpmSubsteps() - 1) mpmSpray[n] = 0;
    ivec3 c = ivec3(n % MPM_NX, n / (MPM_NX * MPM_NZ), (n / MPM_NX) % MPM_NZ);
    float m = float(gi.w) / MPM_FIX;
    vec3 v = vec3(0.0);
    if (m > 1e-9) {
        float dt = mpmDt();
        v = vec3(gi.xyz) / MPM_FIX / m;
        v.y -= dt * 9.81;
        vec3 wpn = mpmOrigin() + vec3(c) * MPM_DX;

        vec3 centre = mpmCentre();
        vec2 rc = wpn.xz - centre.xz;
        float r = length(rc);
        if (wpn.y < centre.y + 0.05) {
            v *= exp(-dt * 6.0 * smoothstep(MPM_TANK - 0.35, MPM_TANK, r));
            if (r > MPM_TANK - 0.5 * MPM_DX) {
                vec2 rh = rc / max(r, 1e-4);
                float vr = dot(v.xz, rh);
                if (vr > 0.0) v.xz -= vr * rh;
            }
        }

        if (c.y < 2 && v.y < 0.0) v.y = 0.0;

        if (mpmSolidNode(c)) v = vec3(0.0);
        else {
            if (v.x < 0.0 && mpmSolidNode(c - ivec3(1, 0, 0))) v.x = 0.0;
            if (v.x > 0.0 && mpmSolidNode(c + ivec3(1, 0, 0))) v.x = 0.0;
            if (v.y < 0.0 && mpmSolidNode(c - ivec3(0, 1, 0))) v.y = 0.0;
            if (v.y > 0.0 && mpmSolidNode(c + ivec3(0, 1, 0))) v.y = 0.0;
            if (v.z < 0.0 && mpmSolidNode(c - ivec3(0, 0, 1))) v.z = 0.0;
            if (v.z > 0.0 && mpmSolidNode(c + ivec3(0, 0, 1))) v.z = 0.0;
        }

        vec3 ba, bb, bv, nb;
        mpmBody(MPM_K, ba, bb, bv);
        float d = mpmBodyDist(wpn, ba, bb, nb);
        if (d < 0.25 * MPM_DX) {
            float vn = dot(v - bv, nb);

            float out_ = d < -1.5 * MPM_DX ? min((-1.5 * MPM_DX - d) * 8.0, 1.5) : 0.0;
            if (vn < out_) v += (out_ - vn) * nb;
        }

        float vmax = 0.5 * MPM_DX / max(dt, 1e-5);
        float sp = length(v);
        if (sp > vmax) v *= vmax / sp;
    }
    mpmGridV[n] = vec4(v, m);

#elif MPM_PASS == 4

    if (!mpmActive() || MPM_K >= mpmSubsteps()) return;
    uint i = gl_GlobalInvocationID.x;
    if (i >= uint(min(mpmCount.x, MPM_MAXP))) return;
    vec4 pj = mpmP[i * 5u], va = mpmP[i * 5u + 1u];
    if (va.w < 0.5) return;
    float air = mpmP[i * 5u + 2u].w;
    ivec3 base; vec3 fx; vec3 w[3];
    mpmStencil((pj.xyz - mpmOrigin()) / MPM_DX, base, fx, w);
    vec3 ba, bb, bv, nb;
    mpmBody(MPM_K, ba, bb, bv);
    vec3 v = vec3(0.0);
    mat3 C = mat3(0.0);

    float dens = 0.0, thinnest = 1.0;
    const float full = MPM_DX * MPM_DX * MPM_DX;
    for (int k = 0; k < 27; k++) {
        ivec3 o = ivec3(k % 3, (k / 3) % 3, k / 9);
        ivec3 c = base + o;
        float wt = w[o.x].x * w[o.y].y * w[o.z].z;
        bool wall = c.y < 2 || mpmSolidNode(c) || mpmBodyDist(mpmOrigin() + vec3(c) * MPM_DX, ba, bb, nb) < 0.0;
        if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, ivec3(MPM_NX, MPM_NY, MPM_NZ)))) { if (wall) dens += wt; else thinnest = 0.0; continue; }
        vec4 gv = mpmGridV[mpmNode(c)];
        vec3 dpos = (vec3(o) - fx) * MPM_DX;
        v += wt * gv.xyz;
        C += outerProduct(gv.xyz, dpos) * (wt * 4.0 / (MPM_DX * MPM_DX));
        dens += wall ? wt * max(gv.w / full, 1.0) : wt * gv.w / full;
        if (!wall) thinnest = min(thinnest, gv.w / full);
    }
    float dt = mpmDt();
    vec3 p = pj.xyz + v * dt;

    #if MPM_EOS == 1
    float J = clamp(dens, 0.0, 3.0);
    #elif MPM_EOS == 0
    float J = clamp(pj.w * (1.0 + dt * (C[0][0] + C[1][1] + C[2][2])), 0.6, 1.4);
    #else
    float J = clamp(pj.w * (1.0 + dt * (C[0][0] + C[1][1] + C[2][2])), 0.6, 1.4);
    if (thinnest > 0.6) J = mix(J, clamp(1.0 / dens, 0.6, 1.4), 1.0 - exp(-dt / 0.1));
    if (dens < 0.3) J = mix(J, 1.0, 1.0 - exp(-dt / 0.05));
    #endif

    float bd = mpmBodyDist(p, ba, bb, nb);
    if (dens < 0.25) air = 1.0;
    else air *= exp(-dt / 0.8);
    if (bd < 0.1) air = max(air, saturate((length(v - bv) - 2.0) / 5.0));

    vec3 gp = (p - mpmOrigin()) / MPM_DX;

    if (gp.y < 1.5 && bd > 0.15) {
        p.y = mpmOrigin().y + 1.5 * MPM_DX;
        gp.y = 1.5;
        v.y = max(v.y, 0.0);
    }
    bool alive = all(greaterThan(gp, vec3(1.0))) && all(lessThan(gp, vec3(MPM_NX, MPM_NY, MPM_NZ) - 2.0));
    vec3 centre = mpmCentre();
    float rp = length(p.xz - centre.xz);
    if (rp > MPM_TANK + 0.2 && p.y < centre.y - 0.02) alive = false;
    if (rp > MPM_TANK - 0.1 && p.y > centre.y + 0.01 && p.y < centre.y + 0.3 && v.y < 1.0) alive = false;
    if (any(isnan(p)) || any(isnan(v)) || isnan(dens)) alive = false;
    mpmP[i * 5u] = vec4(p, J);
    mpmP[i * 5u + 1u] = vec4(v, alive ? 1.0 : 0.0);
    mpmP[i * 5u + 2u] = vec4(C[0], air);
    mpmP[i * 5u + 3u] = vec4(C[1], dens);
    mpmP[i * 5u + 4u] = vec4(C[2], 0.0);
    if (!alive) return;
    if (MPM_K + 1 < mpmSubsteps()) mpmScatter(p, v, C, J);
    else if (dens < 0.4) {

        ivec3 sb; vec3 sf; vec3 sw[3];
        mpmStencil(gp, sb, sf, sw);
        const float mass = MPM_DX * MPM_DX * MPM_DX / float(MPM_PPC);
        for (int k = 0; k < 27; k++) {
            ivec3 o = ivec3(k % 3, (k / 3) % 3, k / 9);
            ivec3 c = sb + o;
            if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, ivec3(MPM_NX, MPM_NY, MPM_NZ)))) continue;
            atomicAdd(mpmSpray[mpmNode(c)], int(round(sw[o.x].x * sw[o.y].y * sw[o.z].z * mass * MPM_FIX)));
        }
    } else if (air > 0.05) {

        ivec2 cc = ivec2(floor(gp.xz + 0.5));
        if (all(greaterThanEqual(cc, ivec2(0))) && all(lessThan(cc, ivec2(MPM_NX, MPM_NZ))))
            atomicAdd(mpmFoamAcc[cc.y * MPM_NX + cc.x], int(air * 256.0));
    }

#elif MPM_PASS == 6

    if (!mpmActive()) { mpmStep.w = 0.0; return; }

    float off = mpmCount.w > 0 ? max(-float(mpmCount.z) / 10000.0 / float(mpmCount.w), 0.0) : 0.0;
    mpmStep.w = mpmCtl[2].w > 0.5 ? 0.0 : mix(mpmStep.w, off, 1.0 - exp(-mpmStep.x * mpmStep.y / 1.0));

#elif MPM_PASS == 5

    int col = int(gl_GlobalInvocationID.x);
    if (col >= MPM_NX * MPM_NZ) return;
    if (!mpmActive()) { mpmSurf[col] = vec4(-1e4, 0.0, -1e4, 0.0); mpmFoamAcc[col] = 0; return; }
    int cx = col % MPM_NX, cz = col / MPM_NX;
    vec3 ba, bb, bv, nb;
    mpmBody(mpmSubsteps() - 1, ba, bb, bv);

    const float full = MPM_DX * MPM_DX * MPM_DX;
    vec3 o = mpmOrigin();
    float top = -1e4, mLast = 0.0, mNext = 0.0;
    int lastW = -1, gap = 0, over = 0;
    bool done = false, lastBody = false, nextSet = false, wall = false;
    for (int y = 0; y < MPM_NY; y++) {
        float m = mpmGridV[mpmNode(ivec3(cx, y, cz))].w / full;
        float wy = o.y + float(y) * MPM_DX;
        if (float(mpmSpray[mpmNode(ivec3(cx, y, cz))]) / MPM_FIX / full > 0.002) top = wy;
        if (done) continue;
        if (mpmSolidNode(ivec3(cx, y, cz))) {

            if (floor(wy) + 1.0 > mpmCentre().y + 0.3) { wall = true; break; }
            continue;
        }
        float d = mpmBodyDist(vec3(o.x + float(cx) * MPM_DX, wy, o.z + float(cz) * MPM_DX), ba, bb, nb);
        if (d < 0.5 * MPM_DX) { lastBody = true; over = 0; gap = 0; nextSet = false; continue; }
        if (d < 1.5 * MPM_DX && m > 0.25) m = max(m, 1.0);
        if (m > 0.5) {
            if (lastBody && ++over < 2) continue;
            lastBody = false; lastW = y; mLast = m; gap = 0; nextSet = false;
            continue;
        }
        if (lastW >= 0 || lastBody) {
            if (!nextSet) { mNext = m; nextSet = true; }
            if (++gap > 2) done = true;
        }
    }
    float surf = (lastW < 0 || lastBody || wall) ? -1e4
               : o.y + (float(lastW) + saturate((mLast - 0.5) / max(mLast - mNext, 1e-4))) * MPM_DX;

    if (top > -1e3) atomicAdd(mpmCount.y, 1);

    float rc = length(vec2(o.x + float(cx) * MPM_DX, o.z + float(cz) * MPM_DX) - mpmCentre().xz);
    if (surf > -1e3 && rc > MPM_TANK - 0.35 && rc < MPM_TANK - 0.1) {
        atomicAdd(mpmCount.z, int(round((surf - mpmCtl[1].w) * 10000.0)));
        atomicAdd(mpmCount.w, 1);
    }

    float foam = saturate(float(mpmFoamAcc[col]) / 256.0 / (float(MPM_PPC) * 0.33));
    mpmFoamAcc[col] = 0;
    mpmSurf[col] = vec4(surf, foam, top > -1e3 ? top + MPM_DX : -1e4, 0.0);
#endif
#endif
}
