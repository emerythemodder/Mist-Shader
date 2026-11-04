#ifndef RT_LIGHTS_GLSL
#define RT_LIGHTS_GLSL

#include "/lib/voxel_common.glsl"

layout(r32ui) uniform uimage3D voxelImg;

layout(r32ui) uniform uimage3D voxelFaceImg;

layout(r32ui) uniform uimage3D voxelTriImg;

#if defined GSH || defined PT_TRACE
layout(r32ui) uniform uimage3D voxelMatImg;
#define VOXEL_MATERIALS

layout(r32ui) uniform uimage3D voxelBrickImg;
#define VOXEL_BRICKS
#endif
uniform sampler2D blockAtlasTex;
layout(rgba16f) uniform image3D lpvImgA;
layout(rgba16f) uniform image3D lpvImgB;

layout(std430, binding = 0) buffer RTLightList {
    uint rtLightCount;
    uint rtPad0, rtPad1, rtPad2;
    vec4 rtLights[MAX_RT_LIGHTS];
};

bool rtIgnoreEntities = false;

bool rtSkipStart = false;

bool rtSmoothStart = false;

uint vxGroundMask = 0u;
#ifdef SMOOTH_TERRAIN
#ifndef TRACKED_RADIUS_UNIFORM
#define TRACKED_RADIUS_UNIFORM
uniform float trackedEntityRadius;
#endif
#endif

bool rtRayEscaped;
vec3 rtRayEnd;

bool rtHitFace;
float rtHitT;
vec3 rtHitNormal;
ivec3 rtHitCell;
uint rtHitCode;

float rtTriT;
vec3 rtTriN;

float rtWaterLen;

#include "/lib/far_occ.glsl"

void lightInfo(int id, out int type, out float range) {
    type = -1; range = 0.0;
    if      (id == 10004) { type = 0; range = 14.0; }
    else if (id == 10009) { type = 1; range = 10.0; }
    else if (id == 10010) { type = 2; range = 7.0;  }
    else if (id == 10011) { type = 3; range = 15.0; }
    else if (id == 10012) { type = 4; range = 10.0; }
    else if (id == 10013) { type = 5; range = 8.0;  }
    else if (id == 10005) { type = 6; range = 15.0; }
    else if (id == 10014) { type = 7; range = 15.0; }
    else if (id == 10015) { type = 8; range = 6.0;  }
    else if (id == 10017) { type = 9; range = 14.0; }
}

float lightTypeRange(uint type) {
    const float r[10] = float[10](14.0, 10.0, 7.0, 15.0, 10.0, 8.0, 15.0, 15.0, 6.0, 14.0);
    return r[min(type, 9u)];
}

vec3 lightTypeColor(int type) {
    if (type == 0 || type == 8) return vec3(1.00, 0.56, 0.24);
    if (type == 1) return vec3(0.25, 0.72, 1.00);
    if (type == 2) return vec3(1.00, 0.18, 0.06);
    if (type == 3) return vec3(0.82, 0.90, 1.00);
    if (type == 4) return vec3(0.62, 0.28, 1.00);
    if (type == 5) return vec3(0.35, 1.00, 0.70);
    if (type == 6) return vec3(1.00, 0.40, 0.08);
    if (type == 9) return vec3(0.45, 1.00, 0.35);
    return vec3(1.00, 0.78, 0.42);
}

vec3 tintColor(uint code) {
    uint i = code - VX_TINT;
    if (i < 16u) {
        const vec3 glass[16] = vec3[16](
            vec3(0.95, 0.95, 0.95), vec3(0.95, 0.45, 0.10), vec3(0.75, 0.25, 0.75), vec3(0.35, 0.65, 0.95),
            vec3(0.95, 0.85, 0.15), vec3(0.45, 0.85, 0.15), vec3(0.95, 0.50, 0.65), vec3(0.35, 0.35, 0.35),
            vec3(0.65, 0.65, 0.65), vec3(0.15, 0.60, 0.65), vec3(0.45, 0.20, 0.75), vec3(0.15, 0.25, 0.85),
            vec3(0.45, 0.30, 0.15), vec3(0.30, 0.45, 0.10), vec3(0.75, 0.15, 0.12), vec3(0.08, 0.08, 0.08));
        return glass[i];
    }
    if (code == 26u) return vec3(0.92);
    if (code == 27u) return vec3(0.08, 0.06, 0.1);
    if (code == VX_WATER) return vec3(0.55, 0.75, 0.85);
    return vec3(1.0);
}
bool isTintCode(uint code) { return code >= VX_TINT && code < VX_LEAVES; }
uint lightCodeType(uint code) { return code >= VX_LIGHT_BLOCK ? code - VX_LIGHT_BLOCK : code - VX_LIGHT; }

uint voxelCodeForBlock(int id) {
    int type; float range;
    lightInfo(id, type, range);
    if (type >= 0) return VX_LIGHT + uint(type);
    if (id == 10001) return VX_WATER;
    if (id == 10002) return VX_LEAVES;
    if (id == 10020) return VX_SLAB_BOTTOM;
    if (id == 10021) return VX_SLAB_TOP;
    if (id == 10022 || id == 10019) return VX_THIN;
    if (id == 10023) return VX_POST;
    if (id >= 10030 && id <= 10047) return VX_TINT + uint(id - 10030);
    #ifdef SMOOTH_TERRAIN
    if (id >= 10053 && id <= 10055) return VX_GROUND;
    #endif
    return VX_EMPTY;
}
bool isPlantBlock(int id) { return id == 10003 || id == 10006 || id == 10018; }

bool isCubeBlock(int id) { return (id >= 10050 && id <= 10055) || (id >= 10060 && id <= 10078) || id == 10029; }

bool onGrid(vec3 p) { return all(lessThan(abs(p - round(p)), vec3(0.01))); }

uint faceSpriteBits(vec2 uv0, vec2 uv1, vec2 uv2, vec2 atlas) {
    vec2 lo = min(uv0, min(uv1, uv2)) * atlas, hi = max(uv0, max(uv1, uv2)) * atlas;
    float size = max(hi.x - lo.x, hi.y - lo.y);
    uint lg = uint(clamp(round(log2(max(size, 16.0) / 16.0)), 0.0, 3.0));
    uvec2 o16 = uvec2(clamp(floor(lo / 16.0 + 0.5), 0.0, 511.0));
    return (o16.x << 12) | (o16.y << 21) | (lg << 30);
}

bool faceOpaque(uint faces, vec2 uv) {
    int S = 16 << int(faces >> 30);
    ivec2 origin = ivec2(uvec2((faces >> 12) & 511u, (faces >> 21) & 511u)) * 16;
    return texelFetch(blockAtlasTex, origin + ivec2(clamp(uv, 0.0, 0.9999) * float(S)), 0).a > 0.5;
}

float faceCoverage(uint faces) {
    float solid = 0.0;
    for (int i = 0; i < 16; i++) solid += faceOpaque(faces, (vec2(i & 3, i >> 2) + 0.5) / 4.0) ? 1.0 : 0.0;
    return solid / 16.0;
}

bool storeTriangle(ivec3 c, vec3 cellMin, vec3 p0, vec3 p1, vec3 p2, vec2 uv0, vec2 uv1, vec2 uv2, uint flags) {
    uint idx = atomicAdd(rtTriCount, 1u);
    if (idx >= uint(MAX_RT_TRIS)) return false;
    uint next = imageAtomicExchange(voxelTriImg, c, idx + 1u);
    rtTris[idx * 2u]      = uvec4(packLocal(p0 - cellMin), packLocal(p1 - cellMin), packLocal(p2 - cellMin), next);
    rtTris[idx * 2u + 1u] = uvec4(packUnorm2x16(uv0), packUnorm2x16(uv1), packUnorm2x16(uv2), flags);
    return true;
}

void markBrick(ivec3 c) {
    #ifdef VOXEL_BRICKS
    if (inVoxelVolume(c) && imageLoad(voxelBrickImg, c >> 2).r == 0u) imageStore(voxelBrickImg, c >> 2, uvec4(1u));
    #endif
}

uint packMaterial(vec2 uv0, vec2 uv1, vec2 uv2, vec2 atlas, vec3 tint) {
    uvec3 t = uvec3(round(saturate(tint) * 15.0));
    return (faceSpriteBits(uv0, uv1, uv2, atlas) >> 12) | (t.r << 20) | (t.g << 24) | (t.b << 28);
}
void storeMaterial(ivec3 c, vec3 geoN, uint mat) {
    #ifdef VOXEL_MATERIALS
    if (!inVoxelVolume(c)) return;
    int slot = geoN.y > 0.5 ? 0 : (geoN.y < -0.5 ? 1 : 2);
    imageStore(voxelMatImg, ivec3(c.x * 3 + slot, c.y, c.z), uvec4(mat));
    #endif
}

void voxelizeCube(ivec3 b) {
    if (!inVoxelVolume(b)) return;
    if ((imageLoad(voxelFaceImg, b).r & 63u) == 63u) return;
    imageAtomicOr(voxelFaceImg, b, 63u);
    markBrick(b);
    for (int a = 0; a < 3; a++) {
        ivec3 e = ivec3(0); e[a] = 1;
        if (inVoxelVolume(b - e)) { imageAtomicOr(voxelFaceImg, b - e, 2u << uint(a * 2)); markBrick(b - e); }
        if (inVoxelVolume(b + e)) { imageAtomicOr(voxelFaceImg, b + e, 1u << uint(a * 2)); markBrick(b + e); }
    }
}

void voxelizeTriangle(vec3 p0, vec3 p1, vec3 p2, vec2 uv0, vec2 uv1, vec2 uv2, bool holes, int blockId, vec2 atlas, vec3 tint, vec3 blockCenter) {
    ivec3 o = voxelOrigin();
    uint code = voxelCodeForBlock(blockId);
    vec3 geoN = normalize(cross(p1 - p0, p2 - p0));
    vec3 cen = (p0 + p1 + p2) / 3.0;
    vec3 spread = abs(p1 - p0) + abs(p2 - p0);
    int axis = spread.x < 0.01 ? 0 : (spread.y < 0.01 ? 1 : (spread.z < 0.01 ? 2 : -1));
    bool fullFace = axis >= 0 && onGrid(p0) && onGrid(p1) && onGrid(p2) && max(spread.x, max(spread.y, spread.z)) < 2.01;
    ivec3 behind = ivec3(floor(cen - geoN * 0.05)) - o;

    if (code >= VX_LIGHT || isTintCode(code)) {
        if (code >= VX_LIGHT && fullFace) {
            code += VX_LIGHT_BLOCK - VX_LIGHT;
            storeMaterial(behind, geoN, packMaterial(uv0, uv1, uv2, atlas, tint));
        }
        if (inVoxelVolume(behind)) imageAtomicMax(voxelImg, behind, code);
        markBrick(behind);
        return;
    }
    if (!holes || code == VX_LEAVES) storeMaterial(behind, geoN, packMaterial(uv0, uv1, uv2, atlas, tint));

    if (fullFace) {
        ivec3 hi = ivec3(floor(cen));
        hi[axis] = int(round(cen[axis]));
        ivec3 lo = hi;
        lo[axis] -= 1;
        bool seeThrough = holes || code == VX_LEAVES;
        uint bits = seeThrough ? faceSpriteBits(uv0, uv1, uv2, atlas) : 0u;
        uint side = uint(axis * 2);
        uint bitHi = seeThrough ? (64u << side) : (1u << side);
        uint bitLo = seeThrough ? (128u << side) : (2u << side);
        if (inVoxelVolume(hi - o)) imageAtomicOr(voxelFaceImg, hi - o, bitHi | bits);
        if (inVoxelVolume(lo - o)) imageAtomicOr(voxelFaceImg, lo - o, bitLo | bits);
        markBrick(hi - o);
        markBrick(lo - o);
        if (code == VX_GROUND && inVoxelVolume(behind)) imageAtomicMax(voxelImg, behind, VX_GROUND_BIT | vxGroundMask);
        if (code == VX_LEAVES && inVoxelVolume(ivec3(floor(cen - geoN * 0.05)) - o))
            imageAtomicMax(voxelImg, ivec3(floor(cen - geoN * 0.05)) - o, VX_LEAVES);
        return;
    }

    if (isCubeBlock(blockId)) {
        ivec3 b = ivec3(floor(blockCenter)) - o;
        if (!holes && dot(geoN, geoN) > 0.5) storeMaterial(b, geoN, packMaterial(uv0, uv1, uv2, atlas, tint));
        voxelizeCube(b);
        if (code == VX_GROUND && inVoxelVolume(b)) imageAtomicMax(voxelImg, b, VX_GROUND_BIT | vxGroundMask);
        return;
    }

    vec3 cellMin = floor(cen - geoN * 0.02);
    ivec3 c = ivec3(cellMin) - o;
    if (!inVoxelVolume(c)) return;
    if (holes) storeMaterial(c, geoN, packMaterial(uv0, uv1, uv2, atlas, tint));
    markBrick(c);
    if (storeTriangle(c, cellMin, p0, p1, p2, uv0, uv1, uv2, 0u)) {
        imageAtomicMax(voxelImg, c, isPlantBlock(blockId) ? VX_PLANT : VX_SHAPED);
    } else if (code >= VX_SLAB_BOTTOM && code <= VX_POST) {
        imageAtomicMax(voxelImg, c, code);
    }
}

void voxelizeEntityTriangle(vec3 p0, vec3 p1, vec3 p2) {
    ivec3 o = voxelOrigin();
    ivec3 c0 = ivec3(floor(min(p0, min(p1, p2)))) - o, c1 = ivec3(floor(max(p0, max(p1, p2)))) - o;
    if (any(greaterThan(c1 - c0, ivec3(1)))) { c0 = ivec3(floor((p0 + p1 + p2) / 3.0)) - o; c1 = c0; }
    for (int z = c0.z; z <= c1.z; z++) for (int y = c0.y; y <= c1.y; y++) for (int x = c0.x; x <= c1.x; x++) {
        ivec3 c = ivec3(x, y, z);
        if (!inVoxelVolume(c)) continue;
        if (!storeTriangle(c, vec3(c + o), p0, p1, p2, vec2(0.0), vec2(0.0), vec2(0.0), 1u)) return;
        imageAtomicMax(voxelImg, c, VX_ENTITY);
        markBrick(c);
    }
}

bool rayHitsBox(vec3 ro, vec3 rd, vec3 bmin, vec3 bmax) {
    vec3 inv = 1.0 / mix(rd, vec3(1e-6), lessThan(abs(rd), vec3(1e-6)));
    vec3 t0 = (bmin - ro) * inv, t1 = (bmax - ro) * inv;
    vec3 tn = min(t0, t1), tf = max(t0, t1);
    float tNear = max(max(tn.x, tn.y), tn.z), tFar = min(min(tf.x, tf.y), tf.z);
    return tFar >= max(tNear, 0.0);
}
bool hitsShape(uint code, vec3 ro, vec3 rd, vec3 cell) {
    if (code == VX_SLAB_BOTTOM) return rayHitsBox(ro, rd, cell, cell + vec3(1.0, 0.5, 1.0));
    if (code == VX_SLAB_TOP)    return rayHitsBox(ro, rd, cell + vec3(0.0, 0.5, 0.0), cell + 1.0);
    if (code == VX_THIN)        return rayHitsBox(ro, rd, cell, cell + vec3(1.0, 0.125, 1.0));
    if (code == VX_POST)        return rayHitsBox(ro, rd, cell + vec3(0.375, 0.0, 0.375), cell + vec3(0.625, 1.0, 0.625));
    return false;
}

bool hitsTriangles(vec3 ro, vec3 rd, ivec3 cell, float maxDist) {
    uint node = imageLoad(voxelTriImg, cell).r;
    vec2 atlas = vec2(textureSize(blockAtlasTex, 0));
    vec3 base = vec3(cell);
    for (int i = 0; i < 48 && node != 0u && node <= uint(MAX_RT_TRIS); i++) {
        uvec4 a = rtTris[(node - 1u) * 2u];
        vec3 v0 = base + unpackLocal(a.x);
        vec3 e1 = base + unpackLocal(a.y) - v0, e2 = base + unpackLocal(a.z) - v0;
        vec3 pv = cross(rd, e2);
        float det = dot(e1, pv);
        if (abs(det) > 1e-9) {
            float inv = 1.0 / det;
            vec3 tv = ro - v0;
            float u = dot(tv, pv) * inv;
            vec3 qv = cross(tv, e1);
            float v = dot(rd, qv) * inv;
            float t = dot(e2, qv) * inv;
            if (u >= 0.0 && v >= 0.0 && u + v <= 1.0 && t > 1e-3 && t < maxDist) {
                uvec4 b = rtTris[(node - 1u) * 2u + 1u];
                bool hit;
                if ((b.w & 1u) != 0u) {
                    hit = !rtIgnoreEntities;
                } else {
                    vec2 uv = unpackUnorm2x16(b.x) * (1.0 - u - v) + unpackUnorm2x16(b.y) * u + unpackUnorm2x16(b.z) * v;
                    hit = texelFetch(blockAtlasTex, ivec2(uv * atlas), 0).a > 0.5;
                }
                if (hit) {
                    rtTriT = t;
                    rtTriN = normalize(cross(e1, e2));
                    if (dot(rtTriN, rd) > 0.0) rtTriN = -rtTriN;
                    return true;
                }
            }
        }
        node = a.w;
    }
    return false;
}

bool voxelBlocks(uint code, vec3 from, vec3 dir, ivec3 cell, float maxDist) {
    if (code == VX_ENTITY) return !rtIgnoreEntities && hitsTriangles(from, dir, cell, maxDist);
    if (code == VX_SHAPED || code == VX_PLANT) return hitsTriangles(from, dir, cell, maxDist);
    if (code >= VX_SLAB_BOTTOM && code <= VX_POST) return hitsShape(code, from, dir, vec3(cell));
    return false;
}

vec2 boundaryUv(vec3 p, int axis) {
    vec3 f = fract(p);
    if (axis == 0) return vec2(f.z, 1.0 - f.y);
    if (axis == 1) return vec2(f.x, f.z);
    return vec2(f.x, 1.0 - f.y);
}

#ifdef SMOOTH_TERRAIN

float groundDensity(vec3 p) {
    vec3 q = p - 0.5;
    ivec3 i = ivec3(floor(q));
    vec3 f = q - vec3(i);
    uint v[8];
    int e = -1;
    for (int k = 0; k < 8; k++) {
        ivec3 c = i + ivec3(k & 1, (k >> 1) & 1, k >> 2);
        v[k] = inVoxelVolume(c) ? imageLoad(voxelImg, c).r : 0u;
        if (e < 0 && (v[k] & VX_GROUND_BIT) != 0u) e = k;
    }
    if (e < 0) return 0.0;
    uint mask = v[e];
    ivec3 ce = ivec3(e & 1, (e >> 1) & 1, e >> 2);
    float d = 0.0;
    for (int k = 0; k < 8; k++) {
        ivec3 o = ivec3(k & 1, (k >> 1) & 1, k >> 2);
        bool solid = (v[k] & VX_GROUND_BIT) != 0u;
        if (!solid && k != e) {
            ivec3 r = o - ce;
            int b = (r.x + 1) + (r.y + 1) * 3 + (r.z + 1) * 9;
            solid = ((mask >> uint(b < 13 ? b : b - 1)) & 1u) != 0u;
        }
        vec3 w = mix(1.0 - f, f, vec3(o));
        if (solid) d += w.x * w.y * w.z;
    }
    return d;
}

float groundMarch(vec3 from, vec3 dir, float t0, float t1, inout float dMin) {
    const int N = 4;
    for (int k = 0; k < N; k++) {
        float t = mix(t0, t1, (float(k) + 0.5) / float(N));
        float d = groundDensity(from + dir * t);
        if (d > max(0.5, dMin + 0.12)) return t;
        dMin = min(dMin, d);
    }
    return -1.0;
}
#endif

vec3 traceVoxels(vec3 from, vec3 dir, float maxDist, ivec3 target, int maxSteps, bool shapes, bool sunRay) {
    ivec3 cell = ivec3(floor(from));
    ivec3 stepDir = ivec3(sign(dir));
    vec3 invAbs = 1.0 / max(abs(dir), vec3(1e-6));
    vec3 tMax = (vec3(cell) + max(vec3(stepDir), 0.0) - from) / dir;
    tMax = mix(tMax, vec3(1e9), lessThan(abs(dir), vec3(1e-6)));
    vec3 trans = vec3(1.0);
    rtRayEscaped = false;
    rtHitFace = false;
    rtRayEnd = from + dir * maxDist;
    rtWaterLen = 0.0;
    float waterIn = sunRay && inVoxelVolume(cell) && VX_DECODE(imageLoad(voxelImg, cell).r) == VX_WATER ? 0.0 : -1.0;

    ivec3 sides = ivec3(0, 2, 4) + ivec3(lessThan(stepDir, ivec3(0)));
    vec3 negStep = -vec3(stepDir);
    #ifdef SMOOTH_TERRAIN

    bool smoothOn = trackedEntityRadius > 0.0;
    bool inGround = false;
    float dMin = smoothOn ? groundDensity(from) : 0.0;
    if (smoothOn && inVoxelVolume(cell) && VX_DECODE(imageLoad(voxelImg, cell).r) == VX_GROUND) {

        float th = groundMarch(from, dir, 0.0, min(min(tMax.x, tMax.y), min(tMax.z, maxDist)), dMin);
        if (th >= 0.0) {
            rtHitFace = true; rtHitT = th; rtHitCell = cell; rtHitCode = VX_GROUND; rtHitNormal = -dir;
            return vec3(0.0);
        }
        inGround = true;
    }
    #endif

    if (cell != target && inVoxelVolume(cell) && !rtSkipStart) {
        uint code0 = VX_DECODE(imageLoad(voxelImg, cell).r);
        rtTriT = 0.0; rtTriN = -dir;
        if (voxelBlocks(code0, from, dir, cell, maxDist)) {
            rtHitFace = true; rtHitT = rtTriT; rtHitNormal = rtTriN; rtHitCell = cell; rtHitCode = code0;
            return vec3(0.0);
        }
    }
    #ifdef VOXEL_BRICKS

    ivec3 brickAt = cell >> 2;
    uint brick = inVoxelVolume(cell) ? imageLoad(voxelBrickImg, brickAt).r : 1u;
    #endif
    for (int i = 0; i < maxSteps; i++) {
        float tNext;
        int axis;
        uint side;
        #ifdef VOXEL_BRICKS
        if ((brick & 1u) == 0u) {

            ivec3 blo = (cell >> 2) << 2;
            int bsize = 4;

            if (maxDist > 30.0 && (brick & 2u) != 0u && any(notEqual(target >> 4, cell >> 4))) {
                ivec3 slo = (cell >> 4) << 4;
                vec3 sexit = (mix(vec3(slo), vec3(slo + 16), greaterThan(dir, vec3(0.0))) - from) / dir;
                sexit = mix(sexit, vec3(1e9), lessThan(abs(dir), vec3(1e-6)));
                float tS = min(sexit.x, min(sexit.y, sexit.z));
                ivec3 db = abs((clamp(ivec3(floor(from + dir * tS)), slo, slo + 15) >> 2) - (cell >> 2));
                int crossed = db.x + db.y + db.z;
                if (tS <= maxDist && i + crossed < maxSteps) { blo = slo; bsize = 16; i += crossed; }
            }
            vec3 bexit = (mix(vec3(blo), vec3(blo + bsize), greaterThan(dir, vec3(0.0))) - from) / dir;
            bexit = mix(bexit, vec3(1e9), lessThan(abs(dir), vec3(1e-6)));
            tNext = min(bexit.x, min(bexit.y, bexit.z));
            if (tNext > maxDist) { rtRayEscaped = true; break; }
            axis = bexit.x == tNext ? 0 : (bexit.y == tNext ? 1 : 2);
            cell = clamp(ivec3(floor(from + dir * tNext)), blo, blo + bsize - 1);
            cell[axis] = stepDir[axis] > 0 ? blo[axis] + bsize : blo[axis] - 1;
            side = uint(sides[axis]);
            tMax = (vec3(cell) + max(vec3(stepDir), 0.0) - from) / dir;
            tMax = mix(tMax, vec3(1e9), lessThan(abs(dir), vec3(1e-6)));
        } else
        #endif
        {
            tNext = min(tMax.x, min(tMax.y, tMax.z));
            if (tNext > maxDist) { rtRayEscaped = true; break; }
            if (tMax.x < tMax.y && tMax.x < tMax.z) { axis = 0; side = uint(sides.x); cell.x += stepDir.x; tMax.x += invAbs.x; }
            else if (tMax.y < tMax.z)               { axis = 1; side = uint(sides.y); cell.y += stepDir.y; tMax.y += invAbs.y; }
            else                                    { axis = 2; side = uint(sides.z); cell.z += stepDir.z; tMax.z += invAbs.z; }
        }
        if (!inVoxelVolume(cell)) { rtRayEscaped = true; rtRayEnd = from + dir * tNext; break; }
        if (cell == target) break;
        uint faces, code;
        #ifdef VOXEL_BRICKS
        if (any(notEqual(cell >> 2, brickAt))) { brickAt = cell >> 2; brick = imageLoad(voxelBrickImg, brickAt).r; }
        if ((brick & 5u) != 1u) {

            faces = 0u;
            code = (brick & (8u << uint(cell.y & 3))) != 0u ? VX_WATER : VX_EMPTY;
        } else
        #endif
        {
            faces = imageLoad(voxelFaceImg, cell).r;
            code = VX_DECODE(imageLoad(voxelImg, cell).r);
        }
        bool passFace = false;
        #ifdef SMOOTH_TERRAIN
        if (smoothOn) {

            bool wasIn = inGround;
            inGround = code == VX_GROUND;
            if (inGround) {
                float th = groundMarch(from, dir, tNext, min(min(tMax.x, tMax.y), min(tMax.z, maxDist)), dMin);
                if (th >= 0.0) {
                    rtHitFace = true; rtHitT = th; rtHitCell = cell; rtHitCode = code;
                    rtHitNormal = vec3(equal(ivec3(axis), ivec3(0, 1, 2))) * negStep;
                    return vec3(0.0);
                }
                continue;
            }
            passFace = wasIn;
            dMin = min(dMin, 0.38);
        }
        #endif
        if (!passFace && (faces & (65u << side)) != 0u &&
            ((faces & (1u << side)) != 0u || faceOpaque(faces, boundaryUv(from + dir * tNext, axis)))) {
            rtHitFace = true; rtHitT = tNext; rtHitCell = cell;
            rtHitNormal = vec3(equal(ivec3(axis), ivec3(0, 1, 2))) * negStep;
            rtHitCode = code;
            return vec3(0.0);
        }
        if (sunRay) {

            bool w = code == VX_WATER;
            if (w && waterIn < 0.0) waterIn = tNext;
            else if (!w && waterIn >= 0.0) { rtWaterLen += tNext - waterIn; waterIn = -1.0; }
        }
        if (code == VX_EMPTY || code == VX_GROUND) continue;
        if (code >= VX_LIGHT_BLOCK) {
            rtHitFace = true; rtHitT = tNext; rtHitCell = cell; rtHitCode = code;
            rtHitNormal = vec3(equal(ivec3(axis), ivec3(0, 1, 2))) * negStep;
            return vec3(0.0);
        }
        if (code >= VX_LIGHT || code == VX_LEAVES) continue;
        if (!isTintCode(code)) {

            rtTriT = tNext; rtTriN = vec3(equal(ivec3(axis), ivec3(0, 1, 2))) * negStep;
            bool blocked = shapes || code == VX_SHAPED || (code >= VX_SLAB_BOTTOM && code <= VX_POST)
                         ? voxelBlocks(code, from, dir, cell, maxDist) : (code != VX_PLANT && code != VX_ENTITY);
            if (blocked) {
                rtHitFace = true; rtHitT = rtTriT; rtHitNormal = rtTriN; rtHitCell = cell; rtHitCode = code;
                return vec3(0.0);
            }
            continue;
        }
        if (sunRay && code == VX_WATER) continue;
        trans *= tintColor(code);
        if (max(trans.r, max(trans.g, trans.b)) < 0.03) return vec3(0.0);
    }
    if (waterIn >= 0.0) rtWaterLen += max(length(rtRayEnd - from) - waterIn, 0.0);
    return trans;
}

bool voxelGridAgrees(vec3 vp, vec3 normal) {
    vec3 an = abs(normal);
    int axis = an.x > 0.99 ? 0 : (an.y > 0.99 ? 1 : (an.z > 0.99 ? 2 : -1));
    if (axis < 0 || abs(vp[axis] - round(vp[axis])) > 0.02) return true;
    ivec3 front = ivec3(floor(vp + normal * 0.5));
    if (!inVoxelVolume(front)) return true;
    uint side = uint(axis * 2 + (normal[axis] > 0.0 ? 0 : 1));
    return (imageLoad(voxelFaceImg, front).r & (65u << side)) != 0u;
}

vec3 sampleLpv(vec3 vpos) {
    vec3 p = vpos - 0.5;
    ivec3 b = ivec3(floor(p));
    vec3 f = p - floor(p);
    bool even = (frameCounter & 1) == 0;
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        ivec3 o = ivec3(i & 1, (i >> 1) & 1, (i >> 2) & 1);
        ivec3 c = b + o;
        if (!inVoxelVolume(c)) continue;
        vec3 w3 = mix(1.0 - f, f, vec3(o));
        vec3 v = even ? imageLoad(lpvImgA, c).rgb : imageLoad(lpvImgB, c).rgb;
        acc += v * (w3.x * w3.y * w3.z);
    }

    float m = max(acc.r, max(acc.g, acc.b));
    if (m <= 0.0) return vec3(0.0);
    float level = saturate(log2(m + 1.0) / 15.0);
    return (acc / m) * pow(level, 3.0) * 1.6;
}

vec3 lpvAt(ivec3 c) {
    if (!inVoxelVolume(c)) return vec3(0.0);
    vec3 v = (frameCounter & 1) == 0 ? imageLoad(lpvImgA, c).rgb : imageLoad(lpvImgB, c).rgb;
    float m = max(v.r, max(v.g, v.b));
    if (m <= 0.0) return vec3(0.0);
    float level = saturate(log2(m + 1.0) / 15.0);
    return (v / m) * pow(level, 3.0) * 1.6;
}

vec3 softLightPoint(vec3 origin, vec3 center, float dither) {
    vec3 d = normalize(center - origin);
    vec3 t = normalize(cross(d, abs(d.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 b = cross(d, t);
    float r = sqrt(dither) * min(RT_SHADOW_SOFTNESS * 2.0, 0.45);
    float a = dither * 157.07963;
    return center + (t * cos(a) + b * sin(a)) * r;
}

float lightFalloff(float d, float range) {
    float x = saturate(d / range);
    float window = (1.0 - x * x) * (1.0 - x * x);
    return window / (1.0 + d * d * 0.12);
}

#if RT_LIGHT_TRACES > 8
    #define RT_TRACE_COUNT 8
#else
    #define RT_TRACE_COUNT RT_LIGHT_TRACES
#endif

vec3 rtBlockLight(vec3 playerPos, vec3 normal, bool twoSided, float lmBlock, float dither,
                  vec3 viewDir, float smoothness, out float coverage) {
    vec3 vp = toVoxelSpace(playerPos);
    vec3 toEdge = min(vp, vec3(voxelSize()) - vp);
    coverage = smoothstep(1.0, 10.0, min(toEdge.x, min(toEdge.y, toEdge.z)));
    if (coverage <= 0.0) return vec3(0.0);

    vec3 flood = sampleLpv(vp + normal * 0.5) * BLOCKLIGHT_STRENGTH;

    float traceFade = 1.0 - saturate((length(playerPos) - RT_TRACE_FADE_START) / (RT_TRACE_FADE_END - RT_TRACE_FADE_START));
    if (!voxelGridAgrees(vp, normal)) traceFade = 0.0;
    if (traceFade <= 0.0 || (max(flood.r, max(flood.g, flood.b)) < 1e-4 && lmBlock < 0.02)) return flood;

    int   pick[RT_TRACE_COUNT];
    float pickImpact[RT_TRACE_COUNT];
    int picked = 0, minK = 0;
    float minImpact = 1e9;
    uint count = min(rtLightCount, uint(MAX_RT_LIGHTS));
    for (uint i = 0u; i < count; i++) {
        vec4 L = rtLights[i];
        float range = mod(L.w, 16.0);
        vec3 dv = L.xyz - vp;
        float d = length(dv);
        if (d >= range) continue;
        float power = lightFalloff(d, range);
        float ndl = saturate((dot(normal, dv / max(d, 1e-3)) + 0.15) / 1.15);
        if (twoSided) ndl = abs(dot(normal, dv / max(d, 1e-3))) * 0.6 + 0.4;
        float impact = power * max(ndl, 0.0);
        if (impact <= 0.001) continue;
        if (picked < RT_TRACE_COUNT) {
            pick[picked] = int(i); pickImpact[picked] = impact;
            if (impact < minImpact) { minImpact = impact; minK = picked; }
            picked++;
        } else if (impact > minImpact) {
            pick[minK] = int(i); pickImpact[minK] = impact;
            minImpact = pickImpact[0]; minK = 0;
            for (int k = 1; k < RT_TRACE_COUNT; k++) if (pickImpact[k] < minImpact) { minImpact = pickImpact[k]; minK = k; }
        }
    }

    vec3 origin = vp + normal * 0.03;
    float shininess = mix(6.0, 900.0, smoothness * smoothness);
    vec3 traced = vec3(0.0);
    float strongest = 0.0;
    for (int j = 0; j < picked; j++) {
        int best = 0;
        for (int k = 1; k < picked; k++) if (pickImpact[k] > pickImpact[best]) best = k;
        vec4 L = rtLights[pick[best]];
        if (j == 0) strongest = pickImpact[best];

        if (pickImpact[best] < strongest * 0.03) break;
        pickImpact[best] = -1.0;

        float range = mod(L.w, 16.0);
        vec3 dv = L.xyz - vp;
        float d = length(dv);
        vec3 l = dv / max(d, 1e-3);
        float power = lightFalloff(d, range);
        float ndl = saturate((dot(normal, l) + 0.15) / 1.15);
        if (twoSided) ndl = abs(dot(normal, l)) * 0.6 + 0.4;
        float spec = pow(saturate(dot(normal, normalize(l + viewDir + vec3(0.0, 1e-5, 0.0)))), shininess) * ndl;
        vec3 c = lightTypeColor(int(L.w / 16.0)) * power * (ndl + spec * mix(0.4, 2.0, smoothness));

        vec3 vis = vec3(1.0);
        ivec3 lightCell = ivec3(floor(L.xyz));
        if (ivec3(floor(origin)) != lightCell) {
            vec3 toL = softLightPoint(origin, L.xyz, fract(dither + float(j) * 0.618034)) - origin;
            float len = length(toL);
            vis = traceVoxels(origin, toL / max(len, 1e-3), len, lightCell, 36, true, false);
        }
        traced += c * vis;
    }
    traced *= 1.6 * BLOCKLIGHT_STRENGTH;

    return mix(flood, traced + flood * 0.2, traceFade);
}

int heldLightType() {
    int id = heldBlockLightValue >= heldBlockLightValue2 ? heldItemId : heldItemId2;
    if (id == 30001) return 1;
    if (id == 30002) return 2;
    if (id == 30003) return 9;
    if (id == 30004) return 3;
    if (id == 30005) return 7;
    if (id == 30006) return 5;
    if (id == 30007) return 4;
    return 0;
}

vec3 handLightPos() {
    float side = heldBlockLightValue >= heldBlockLightValue2 ? 1.0 : -1.0;
    return mat3(gbufferModelViewInverse) * vec3(0.32 * side, -0.26, -0.38) + gbufferModelViewInverse[3].xyz;
}

vec3 rtHandLight(vec3 playerPos, vec3 normal, bool isHand, float held, float dither) {
    vec3 lp = handLightPos();
    vec3 dv = lp - playerPos;
    float d = length(dv);
    if (held <= 0.0 || d > held + 1.0) return vec3(0.0);
    vec3 l = dv / max(d, 1e-3);
    float ndl = isHand ? 1.0 : saturate(dot(normal, l));
    if (ndl <= 0.0) return vec3(0.0);
    float power = lightFalloff(d, held + 1.0);
    vec3 vis = vec3(1.0);
    vec3 vp = toVoxelSpace(playerPos);
    if (!isHand && d > 0.6 && voxelGridAgrees(vp, normal)) {
        vec3 origin = vp + normal * 0.03;
        vec3 lightPos = toVoxelSpace(lp);
        vec3 toL = softLightPoint(origin, lightPos, dither) - origin;
        float len = length(toL);
        rtIgnoreEntities = true;
        vis = traceVoxels(origin, toL / len, len, ivec3(floor(lightPos)), 36, true, false);
        rtIgnoreEntities = false;
    }
    return lightTypeColor(heldLightType()) * power * ndl * vis * 1.6 * BLOCKLIGHT_STRENGTH;
}

#if defined FSH || defined RT_SHADING

vec3 rtSunShadow(vec3 playerPos, vec3 normal, vec3 startOffset, vec3 L, float dither, out float coverage) {
    vec3 t1 = normalize(cross(L, abs(L.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 t2 = cross(L, t1);
    float a = dither * TAU;

    float r = sqrt(fract(dither * 7.31 + 0.37)) * max(RT_SUN_SOFTNESS, 0.0047);
    vec3 dir = normalize(L + (t1 * cos(a) + t2 * sin(a)) * r);

    vec3 vis = vec3(1.0);
    vec3 farStart = playerPos + cameraPosition + startOffset + normal * 0.02;
    vec3 vp = toVoxelSpace(playerPos);
    vec3 toEdge = min(vp, vec3(voxelSize()) - vp);
    if (min(toEdge.x, min(toEdge.y, toEdge.z)) > 1.0 && voxelGridAgrees(vp, normal)) {

        rtIgnoreEntities = true;
        vis = traceVoxels(vp + startOffset, dir, 40.0, ivec3(-1000), 72, true, true);
        rtIgnoreEntities = false;
        if (rtWaterLen > 0.0) {

            vis *= exp(-WATER_ABSORB * rtWaterLen) * waterCaustics(playerPos + cameraPosition, rtWaterLen * max(dir.y, 0.05));
        }
        if (!rtRayEscaped || max(vis.r, max(vis.g, vis.b)) <= 0.0) { coverage = 1.0; return vis; }
        farStart = rtRayEnd + vec3(voxelOrigin());
    }
    coverage = farCovers(farStart) ? 1.0 : 0.0;
    if (coverage > 0.0) vis *= farTrace(farStart, dir, 220.0, fract(dither * 91.7) * 64.0 + float(frameCounter & 63));
    return vis;
}

float sunVisAt(vec3 vp, vec3 n, vec3 L) {
    if (dot(n, L) <= 0.0) return 0.0;
    vec3 o = vp + n * 0.05;
    vec3 t = traceVoxels(o, L, 24.0, ivec3(-1000), 32, false, true);
    if (!rtRayEscaped || max(t.r, max(t.g, t.b)) <= 0.0) return 0.0;
    return luminance(t) * farSunCheap(rtRayEnd + vec3(voxelOrigin()), L, 128.0);
}

float rtSunBounce(vec3 playerPos, vec3 normal, vec3 L, float dither) {
    vec3 vp = toVoxelSpace(playerPos);
    vec3 toEdge = min(vp, vec3(voxelSize()) - vp);
    if (min(toEdge.x, min(toEdge.y, toEdge.z)) < 11.0) return 0.0;
    vec3 t1 = normalize(cross(normal, abs(normal.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 t2 = cross(normal, t1);
    vec3 origin = vp + normal * 0.05;
    float sum = 0.0;
    rtIgnoreEntities = true;
    for (int k = 0; k < 2; k++) {
        float u1 = fract(dither + float(k) * 0.5), u2 = fract(dither * 13.37 + float(k) * 0.618 + 0.21);
        float r = sqrt(u1), a = u2 * TAU;
        vec3 dir = normalize(t1 * (r * cos(a)) + t2 * (r * sin(a)) + normal * sqrt(max(1.0 - u1, 0.0)));
        traceVoxels(origin, dir, 10.0, ivec3(-1000), 24, false, false);
        if (rtHitFace) {
            float ndl = dot(rtHitNormal, L);
            if (ndl > 0.0) sum += ndl * farSunCheap(origin + dir * rtHitT + rtHitNormal * 0.1 + vec3(voxelOrigin()), L, 128.0);
        }
    }
    rtIgnoreEntities = false;
    return sum * 0.5 * 0.3;
}

#ifdef PT_TRACE
#define PT_DISTANCE 20.0
#define PT_STEPS 40

vec3 voxelAlbedo(ivec3 cell, vec3 n) {
    int slot = n.y > 0.5 ? 0 : (n.y < -0.5 ? 1 : 2);
    uint m = imageLoad(voxelMatImg, ivec3(cell.x * 3 + slot, cell.y, cell.z)).r;
    if (m == 0u) m = imageLoad(voxelMatImg, ivec3(cell.x * 3 + 2, cell.y, cell.z)).r;
    if (m == 0u) m = imageLoad(voxelMatImg, ivec3(cell.x * 3, cell.y, cell.z)).r;
    if (m == 0u) return vec3(0.25);
    ivec2 origin = ivec2(int(m & 511u), int((m >> 9) & 511u)) * 16;
    float S = float(16 << int((m >> 18) & 3u));
    vec3 c = vec3(0.0);
    float w = 0.0;
    for (int i = 0; i < 4; i++) {
        vec2 f = vec2(float(i & 1), float(i >> 1)) * 0.5 + 0.25;
        vec4 t = texelFetch(blockAtlasTex, origin + ivec2(f * S), 0);
        c += t.rgb * t.a;
        w += t.a;
    }
    vec3 tint = vec3(uvec3(m >> 20, m >> 24, m >> 28) & 15u) / 15.0;
    return toLinear(w > 0.0 ? c / w * tint : vec3(0.5));
}

vec3 ptIndirect(vec3 playerPos, vec3 normal, vec2 rnd, float skyAccess, vec3 sunLight, vec3 skyLight) {
    vec3 vp = toVoxelSpace(playerPos);
    vec3 t1 = normalize(cross(normal, abs(normal.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 t2 = cross(normal, t1);
    float r = sqrt(rnd.x), a = rnd.y * TAU;
    vec3 dir = normalize(t1 * (r * cos(a)) + t2 * (r * sin(a)) + normal * sqrt(max(1.0 - rnd.x, 0.0)));
    vec3 origin = vp + normal * 0.02;
    vec3 trans = traceVoxels(origin, dir, PT_DISTANCE, ivec3(-1000), PT_STEPS, false, false);
    if (rtHitFace) {
        vec3 n = rtHitNormal;
        vec3 hp = origin + dir * rtHitT + n * 0.03;
        vec3 albedo = voxelAlbedo(rtHitCell, n);

        if (rtHitCode >= VX_LIGHT_BLOCK) return vec3(0.0);
        vec3 E = lpvAt(ivec3(floor(hp + n * 0.5))) * BLOCKLIGHT_STRENGTH;
        float ndl = dot(n, getLightDir());
        if (ndl > 0.0) E += sunLight * ndl * sunVisAt(hp, n, getLightDir());
        E += skyLight * skyAccess * (0.35 + 0.25 * n.y);
        return albedo * E;
    }

    #ifdef ENVPROBE_GLSL
    return envLevel(1, dir) * (PI * AMBIENT_STRENGTH) * skyAccess * trans;
    #else
    return getSky(dir, false) * (PI * AMBIENT_STRENGTH) * skyAccess * trans;
    #endif
}

vec3 voxelTexel(ivec3 cell, vec3 n, vec2 uv) {
    int slot = n.y > 0.5 ? 0 : (n.y < -0.5 ? 1 : 2);
    uint m = imageLoad(voxelMatImg, ivec3(cell.x * 3 + slot, cell.y, cell.z)).r;
    if (m == 0u) return voxelAlbedo(cell, n);
    ivec2 origin = ivec2(int(m & 511u), int((m >> 9) & 511u)) * 16;
    float S = float(16 << int((m >> 18) & 3u));
    vec4 t = texelFetch(blockAtlasTex, origin + ivec2(clamp(uv, 0.0, 0.999) * S), 0);
    vec3 tint = vec3(uvec3(m >> 20, m >> 24, m >> 28) & 15u) / 15.0;
    return toLinear(t.rgb * tint);
}

vec4 rtReflect(vec3 playerPos, vec3 dir, vec3 sunLight, vec3 skyLight, float skyAccess) {
    vec3 vp = toVoxelSpace(playerPos);
    vec3 toEdge = min(vp, vec3(voxelSize()) - vp);
    if (min(toEdge.x, min(toEdge.y, toEdge.z)) < 1.0) return vec4(0.0);
    vec3 origin = vp + dir * 0.08;
    traceVoxels(origin, dir, 32.0, ivec3(-1000), 40, true, false);
    if (!rtHitFace) return vec4(0.0);
    vec3 n = rtHitNormal;
    vec3 hp = origin + dir * rtHitT;
    vec3 an = abs(n);
    int axis = an.x > 0.9 ? 0 : (an.y > 0.9 ? 1 : 2);
    vec3 albedo = max(an.x, max(an.y, an.z)) > 0.99 ? voxelTexel(rtHitCell, n, boundaryUv(hp, axis)) : voxelAlbedo(rtHitCell, n);
    if (rtHitCode >= VX_LIGHT_BLOCK) return vec4(albedo * EMISSIVE_STRENGTH, 1.0);
    vec3 E = lpvAt(ivec3(floor(hp + n * 0.5))) * BLOCKLIGHT_STRENGTH;
    float ndl = dot(n, getLightDir());
    if (ndl > 0.0) E += sunLight * ndl * sunVisAt(hp, n, getLightDir());
    E += skyLight * skyAccess * (0.45 + 0.35 * n.y);
    return vec4(albedo * E, 1.0);
}
#endif
#endif

float rtAmbientOcclusion(vec3 playerPos, vec3 normal, float dither) {
    vec3 vp = toVoxelSpace(playerPos);
    vec3 toEdge = min(vp, vec3(voxelSize()) - vp);
    if (min(toEdge.x, min(toEdge.y, toEdge.z)) < 3.0 || !voxelGridAgrees(vp, normal)) return 1.0;
    vec3 origin = vp + normal * 0.05;
    vec3 t1 = normalize(cross(normal, abs(normal.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 t2 = cross(normal, t1);
    float occ = 0.0;
    const int rays = 5;
    rtIgnoreEntities = true;
    for (int i = 0; i < rays; i++) {
        vec2 dsk = vogelDisk(i, rays, dither * TAU);
        vec3 dir = normalize(t1 * dsk.x + t2 * dsk.y + normal * sqrt(max(1.0 - dot(dsk, dsk), 0.05)));
        vec3 v = traceVoxels(origin, dir, 1.7, ivec3(-1000), 6, false, false);
        if (max(v.r, max(v.g, v.b)) <= 0.0) occ += 1.0;
    }
    rtIgnoreEntities = false;
    return 1.0 - 0.7 * occ / float(rays);
}
#endif
