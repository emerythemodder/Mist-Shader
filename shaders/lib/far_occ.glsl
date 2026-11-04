#ifndef FAR_OCC_GLSL
#define FAR_OCC_GLSL

#define FAR_RES 512
#define FAR_LEAVES 12
#define FAR_TOP 24
#define FAR_COARSE 25
#define FAR_Y0 -64
#define FAR_Y1 320

#ifdef FAR_OCC_WRITE
layout(r32ui) uniform uimage3D farOccImg;
uint farLoad(ivec3 t) { return imageLoad(farOccImg, t).r; }

void farOccMarkTriangle(vec3 p0, vec3 p1, vec3 p2, int blockId, vec3 blockCenter) {
    if (blockId == 10001 || blockId == 10003 || blockId == 10006 || blockId == 10018 || blockId == 10007) return;
    if (blockId >= 10030 && blockId <= 10047) return;
    ivec3 b;
    if ((blockId >= 10050 && blockId <= 10055) || (blockId >= 10060 && blockId <= 10078) || blockId == 10029) {

        b = ivec3(floor(blockCenter));
    } else {
        vec3 r0 = abs(p0 - round(p0)), r1 = abs(p1 - round(p1)), r2 = abs(p2 - round(p2));
        if (max(max(max(r0.x, r0.y), r0.z), max(max(max(r1.x, r1.y), r1.z), max(max(r2.x, r2.y), r2.z))) > 0.01) return;
        vec3 geoN = cross(p1 - p0, p2 - p0);
        float gl = length(geoN);
        if (gl < 1e-6) return;
        geoN /= gl;
        if (max(abs(geoN.x), max(abs(geoN.y), abs(geoN.z))) < 0.999) return;
        b = ivec3(floor((p0 + p1 + p2) / 3.0 - geoN * 0.05));
    }
    if (b.y < FAR_Y0 || b.y >= FAR_Y1) return;
    vec2 rel = abs(vec2(b.xz) + 0.5 - cameraPosition.xz);
    if (max(rel.x, rel.y) > float(FAR_RES / 2 - 2)) return;
    ivec2 c = b.xz & (FAR_RES - 1);
    int yy = b.y - FAR_Y0;
    bool leaves = blockId == 10002;

    ivec3 tb = ivec3(c.x, (yy >> 5) + (leaves ? FAR_LEAVES : 0), c.y);
    uint bit = 1u << uint(yy & 31);
    if ((imageLoad(farOccImg, tb).r & bit) == 0u) imageAtomicOr(farOccImg, tb, bit);
    uint top = uint(yy + 1);
    ivec3 tt = ivec3(c.x, FAR_TOP, c.y);
    if (imageLoad(farOccImg, tt).r < top) imageAtomicMax(farOccImg, tt, top);
}
#else
uniform usampler3D farOccSampler;
uint farLoad(ivec3 t) { return texelFetch(farOccSampler, t, 0).r; }
#endif

float farColumnTop(ivec2 xz) {
    ivec2 c = xz & (FAR_RES - 1);
    return float(farLoad(ivec3(c.x, FAR_TOP, c.y))) + float(FAR_Y0);
}
float farCoarseTop(ivec2 cxz) {
    ivec2 c = cxz & (FAR_RES / 8 - 1);
    return float(farLoad(ivec3(c.x, FAR_COARSE, c.y))) + float(FAR_Y0);
}

int farBlock(ivec3 b) {
    if (b.y < FAR_Y0 || b.y >= FAR_Y1) return 0;
    ivec2 c = b.xz & (FAR_RES - 1);
    int yy = b.y - FAR_Y0;
    uint bit = 1u << uint(yy & 31);
    if ((farLoad(ivec3(c.x, yy >> 5, c.y)) & bit) != 0u) return 1;
    if ((farLoad(ivec3(c.x, (yy >> 5) + FAR_LEAVES, c.y)) & bit) != 0u) return 2;
    return 0;
}
bool farCovers(vec3 worldPos) {
    vec2 rel = abs(worldPos.xz - cameraPosition.xz);
    return max(rel.x, rel.y) < float(FAR_RES / 2 - 4);
}

float farTrace(vec3 o, vec3 d, float maxDist, float leafSeed) {
    float trans = 1.0;

    vec2 d2 = d.xz;
    vec2 inv2 = 1.0 / max(abs(d2), vec2(1e-6));
    ivec2 cc = ivec2(floor(o.xz / 8.0));
    ivec2 cstep = ivec2(sign(d2));
    vec2 ctMax = ((vec2(cc) + max(vec2(cstep), 0.0)) * 8.0 - o.xz) / d2;
    ctMax = mix(ctMax, vec2(1e9), lessThan(abs(d2), vec2(1e-6)));
    vec2 ctDelta = 8.0 * inv2;
    float t = 0.0;
    for (int ci = 0; ci < 48 && t < maxDist; ci++) {
        float tExit = min(min(ctMax.x, ctMax.y), maxDist);
        float yLow = o.y + d.y * (d.y >= 0.0 ? t : tExit);
        if (d.y >= 0.0 && yLow >= float(FAR_Y1)) break;
        if (yLow < farCoarseTop(cc)) {

            vec3 p = o + d * (t + 1e-3);
            ivec3 b = ivec3(floor(p));
            ivec3 st = ivec3(sign(d));
            vec3 invA = 1.0 / max(abs(d), vec3(1e-6));
            vec3 tM = (vec3(b) + max(vec3(st), 0.0) - o) / d;
            tM = mix(tM, vec3(1e9), lessThan(abs(d), vec3(1e-6)));
            float colTop = farColumnTop(b.xz);
            ivec2 colXZ = b.xz;
            for (int fi = 0; fi < 40; fi++) {
                float tNext = min(tM.x, min(tM.y, tM.z));
                if (b.xz != colXZ) { colXZ = b.xz; colTop = farColumnTop(b.xz); }
                if (float(b.y) < colTop) {
                    int k = farBlock(b);
                    if (k == 1) return 0.0;
                    if (k == 2) {
                        trans *= hash13(vec3(b) + leafSeed) < 0.62 ? 0.0 : 0.85;
                        if (trans < 0.02) return 0.0;
                    }
                }
                if (tNext >= tExit) break;
                if (tM.x < tM.y && tM.x < tM.z) { b.x += st.x; tM.x += invA.x; }
                else if (tM.y < tM.z)           { b.y += st.y; tM.y += invA.y; }
                else                            { b.z += st.z; tM.z += invA.z; }
            }
        }
        t = tExit;
        if (ctMax.x < ctMax.y) { cc.x += cstep.x; ctMax.x += ctDelta.x; }
        else                   { cc.y += cstep.y; ctMax.y += ctDelta.y; }
    }
    return trans;
}

float farSunCheap(vec3 o, vec3 d, float maxDist) {
    if (d.y <= 0.02) return 1.0;
    for (int i = 1; i <= 12; i++) {
        float t = maxDist * float(i * i) / 144.0;
        vec3 p = o + d * t;
        if (p.y > float(FAR_Y1)) return 1.0;
        if (p.y < farColumnTop(ivec2(floor(p.xz)))) return 0.0;
    }
    return 1.0;
}
#endif
