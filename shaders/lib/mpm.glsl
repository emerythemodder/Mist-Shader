#ifndef MPM_GLSL
#define MPM_GLSL

#define MPM_NX 40
#define MPM_NY 32
#define MPM_NZ 40
#define MPM_NODES 51200
#define MPM_DX 0.1
#define MPM_DEPTH 1.0

#define MPM_C 16.0

#define MPM_SETTLE(H) ((H) * (1.0 - 9.81 * (H) / (2.0 * MPM_C * MPM_C)))
#define MPM_BOTTOM MPM_SETTLE(MPM_DEPTH)
#define MPM_FLOOR (MPM_BOTTOM + 0.15)

#define MPM_TANK 1.2
#define MPM_MAXP 40960
#define MPM_MAXSUB 10
#define MPM_PPC 8
#define MPM_FIX 100000000.0
#define MPM_LIFE 3.5
#define MPM_MAGIC 7654.5

#ifndef MPM_ACCESS
#define MPM_ACCESS readonly
#endif

layout(std430, binding = 4) MPM_ACCESS buffer Mpm {
    vec4 mpmCtl[4];

    vec4 mpmStep;

    ivec4 mpmCount;

    vec4 mpmP[MPM_MAXP * 5];

    ivec4 mpmGrid[MPM_NODES];
    vec4 mpmGridV[MPM_NODES];
    vec4 mpmSurf[MPM_NX * MPM_NZ];

    int mpmFoamAcc[MPM_NX * MPM_NZ];
    uint mpmSolid[MPM_NODES / 32];
    int mpmSpray[MPM_NODES];

};

bool mpmActive() { return mpmCtl[0].w >= 0.0 && mpmCtl[0].w < MPM_LIFE && mpmCtl[3].w == MPM_MAGIC; }
vec3 mpmOrigin() { return mpmCtl[0].xyz; }
vec3 mpmSize() { return vec3(MPM_NX - 1, MPM_NY - 1, MPM_NZ - 1) * MPM_DX; }

vec3 mpmCentre() { return mpmOrigin() + vec3(float(MPM_NX / 2) * MPM_DX, MPM_FLOOR, float(MPM_NZ / 2) * MPM_DX); }
int mpmNode(ivec3 c) { return (c.y * MPM_NZ + c.z) * MPM_NX + c.x; }

float mpmSurfaceWeight(vec2 xz) {
    if (!mpmActive()) return 0.0;
    float r = length(xz - mpmCentre().xz);
    float rim = 1.0 - smoothstep(MPM_TANK - 0.4, MPM_TANK - 0.15, r);
    float life = 1.0 - smoothstep(MPM_LIFE - 0.8, MPM_LIFE, mpmCtl[0].w);
    return rim * life;
}

vec3 mpmSurface(vec2 xz, out bool ok) {
    vec2 g = (xz - mpmOrigin().xz) / MPM_DX;
    ivec2 i = ivec2(floor(g));
    vec2 t = g - vec2(i);
    vec2 it = 1.0 - t, t2 = t * t, t3 = t2 * t;
    vec2 w[4] = vec2[4](it * it * it / 6.0, (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0,
                        (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0, t3 / 6.0);
    vec2 d[4] = vec2[4](-0.5 * it * it, 1.5 * t2 - 2.0 * t, -1.5 * t2 + t + 0.5, 0.5 * t2);
    float S = 0.0, W = 0.0;
    vec2 dS = vec2(0.0), dW = vec2(0.0);
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            ivec2 c = i + ivec2(x - 1, y - 1);
            if (any(lessThan(c, ivec2(0))) || any(greaterThanEqual(c, ivec2(MPM_NX, MPM_NZ)))) continue;
            float h = mpmSurf[c.y * MPM_NX + c.x].x;
            if (h < -1e3) continue;
            float wk = w[x].x * w[y].y;
            vec2 dk = vec2(d[x].x * w[y].y, w[x].x * d[y].y);
            S += h * wk; W += wk; dS += h * dk; dW += dk;
        }
    }
    ok = W > 0.5;
    if (!ok) return vec3(0.0);
    float h = S / W;
    return vec3(h + mpmStep.w, (dS - h * dW) / (W * MPM_DX));
}
float mpmSurfaceAt(vec2 xz, out bool ok) { return mpmSurface(xz, ok).x; }

float mpmCover(vec2 xz, float level, out vec3 hs) {
    hs = vec3(0.0);
    float w = abs(level - mpmCtl[1].w) < 0.5 ? mpmSurfaceWeight(xz) : 0.0;
    if (w <= 0.0) return 0.0;
    bool ok;
    hs = mpmSurface(xz, ok);
    return ok ? w : 0.0;
}

float mpmFoamAt(vec2 xz) {
    vec2 g = (xz - mpmOrigin().xz) / MPM_DX;
    ivec2 i = ivec2(floor(g));
    vec2 f = g - vec2(i);
    float s = 0.0;
    for (int k = 0; k < 4; k++) {
        ivec2 c = i + ivec2(k & 1, k >> 1);
        if (any(lessThan(c, ivec2(0))) || any(greaterThanEqual(c, ivec2(MPM_NX, MPM_NZ)))) continue;
        s += mpmSurf[c.y * MPM_NX + c.x].y * ((k & 1) == 1 ? f.x : 1.0 - f.x) * ((k >> 1) == 1 ? f.y : 1.0 - f.y);
    }
    return s;
}

vec2 mpmColumns(vec2 xz) {
    vec2 g = (xz - mpmOrigin().xz) / MPM_DX;
    ivec2 i = ivec2(floor(g));
    vec2 f = g - vec2(i);
    float s = 0.0, w = 0.0, top = -1e4;
    for (int k = 0; k < 4; k++) {
        ivec2 c = i + ivec2(k & 1, k >> 1);
        if (any(lessThan(c, ivec2(0))) || any(greaterThanEqual(c, ivec2(MPM_NX, MPM_NZ)))) continue;
        vec4 col = mpmSurf[c.y * MPM_NX + c.x];
        float wk = ((k & 1) == 1 ? f.x : 1.0 - f.x) * ((k >> 1) == 1 ? f.y : 1.0 - f.y);
        if (col.x > -1e3) { s += col.x * wk; w += wk; }
        top = max(top, col.z);
    }
    return vec2(w > 0.5 ? s / w : -1e4, top);
}

float mpmSprayDensity(vec3 wp) {
    vec3 g = (wp - mpmOrigin()) / MPM_DX;
    ivec3 i = ivec3(floor(g));
    vec3 f = g - vec3(i);
    float s = 0.0;
    for (int k = 0; k < 8; k++) {
        ivec3 o = ivec3(k & 1, (k >> 1) & 1, k >> 2);
        ivec3 c = i + o;
        if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, ivec3(MPM_NX, MPM_NY, MPM_NZ)))) continue;
        vec3 w = mix(1.0 - f, f, vec3(o));
        s += float(mpmSpray[mpmNode(c)]) * (w.x * w.y * w.z);
    }
    return s / MPM_FIX / (MPM_DX * MPM_DX * MPM_DX);
}

float mpmDensity(vec3 wp) {
    vec3 g = (wp - mpmOrigin()) / MPM_DX;
    ivec3 i = ivec3(floor(g));
    vec3 f = g - vec3(i);
    float s = 0.0;
    for (int k = 0; k < 8; k++) {
        ivec3 o = ivec3(k & 1, (k >> 1) & 1, k >> 2);
        ivec3 c = i + o;
        if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, ivec3(MPM_NX, MPM_NY, MPM_NZ)))) continue;
        vec3 w = mix(1.0 - f, f, vec3(o));
        s += mpmGridV[mpmNode(c)].w * (w.x * w.y * w.z);
    }
    return s / (MPM_DX * MPM_DX * MPM_DX);
}
#endif
