#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/waving.glsl"
#include "/lib/materials.glsl"
#if defined PROGRAM_ENTITIES && defined USE_RIPPLES && defined FSH

    #include "/lib/ripples.glsl"
#endif
#if defined PROGRAM_TERRAIN && !defined PROGRAM_TERRAIN_SOLID

    #define TERRAIN_GSH
#endif
#if defined PROGRAM_TERRAIN && defined SNOW_TRACKS_READ

    #include "/lib/snow.glsl"
#endif

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

#if defined TERRAIN_GSH && defined VSH
out vec2 vsTexcoord;
out vec2 vsLm;
out vec4 vsColor;
out mat3 vsTbn;
flat out int vsMat;
out vec3 vsPlayer;

vec4 spriteRect;
int blockIdV;
#define texcoord vsTexcoord
#define lmcoord vsLm
#define glcolor vsColor
#define tbn vsTbn
#define matId vsMat
#define playerPosV vsPlayer
#elif !defined GSH
VARY vec2 texcoord;
VARY vec2 lmcoord;
VARY vec4 glcolor;
VARY mat3 tbn;
flat VARY int matId;
#if defined TERRAIN_GSH && defined FSH
const vec4 spriteRect = vec4(0.0);
const int blockIdV = 0;
#define playerPosV (snowWorld - cameraPosition)
#else
flat VARY vec4 spriteRect;
flat VARY int blockIdV;
VARY vec3 playerPosV;
#endif
#endif
#if defined TERRAIN_GSH && defined FSH
in vec3 snowWorld;
flat in vec2 snowInfo;
#endif

#ifdef VSH
in vec4 mc_Entity;
in vec4 at_tangent;
in vec3 at_midBlock;
in vec4 mc_midTexCoord;

#if defined PROGRAM_TERRAIN && defined SMOOTH_TERRAIN

in uvec4 at_neighbors;
#ifndef TRACKED_RADIUS_UNIFORM
#define TRACKED_RADIUS_UNIFORM
uniform float trackedEntityRadius;
#endif

bool smoothGround(int id) { return trackedEntityRadius > 0.0 && id >= 10053 && id <= 10055; }
bool neighborBit(uint bits, ivec3 o) {
    int i = (o.x + 1) + (o.y + 1) * 3 + (o.z + 1) * 9;
    return ((bits >> uint(i < 13 ? i : i - 1)) & 1u) != 0u;
}

bool netsPoint(uint solid, ivec3 c, out vec3 offset, out vec3 nrm) {
    vec3 sum = vec3(0.0), open = vec3(0.0);
    float n = 0.0;
    for (int k = 0; k < 8; k++) {
        vec3 ck = (vec3(k & 1, (k >> 1) & 1, k >> 2) - 0.5) * vec3(c);
        bool sk = ((solid >> uint(k)) & 1u) != 0u;
        if (!sk) open += ck;
        for (int a = 0; a < 3; a++) {
            int k2 = k | (1 << a);
            if (k2 == k || sk == (((solid >> uint(k2)) & 1u) != 0u)) continue;
            vec3 e = vec3(0.0);
            e[a] = 0.5 * float(c[a]);
            sum += ck + e;
            n += 1.0;
        }
    }
    offset = n > 0.5 ? sum / n * SMOOTH_STRENGTH : vec3(0.0);
    nrm = dot(open, open) > 1e-4 ? normalize(open) : vec3(0.0, 1.0, 0.0);
    return n > 0.5 && dot(open, open) > 1e-4;
}

bool groundCorner(ivec3 c, out vec3 offset, out vec3 nrm) {
    offset = vec3(0.0); nrm = vec3(0.0, 1.0, 0.0);
    uint solid = 1u;
    for (int k = 1; k < 8; k++) {
        ivec3 o = ivec3(k & 1, (k >> 1) & 1, k >> 2) * c;
        if (neighborBit(at_neighbors.z, o)) {
            if (!neighborBit(at_neighbors.x, o)) return false;
            solid |= 1u << uint(k);
        } else if (neighborBit(at_neighbors.y, o)) return false;
    }
    return netsPoint(solid, c, offset, nrm);
}

float smoothFaceUp(int axis, ivec3 c, vec3 faceN) {
    int u = axis == 0 ? 1 : 0, v = axis == 2 ? 1 : 2;
    vec3 p[4];
    for (int q = 0; q < 4; q++) {
        ivec3 cq = c;
        cq[u] = (q & 1) == 0 ? -1 : 1;
        cq[v] = (q & 2) == 0 ? -1 : 1;
        vec3 off, nrm;
        groundCorner(cq, off, nrm);
        p[q] = vec3(cq) * 0.5 + off;
    }
    vec3 n = cross(p[3] - p[0], p[2] - p[1]);
    if (dot(n, faceN) < 0.0) n = -n;
    return dot(n, n) > 1e-8 ? normalize(n).y : 0.0;
}

vec3 plantOnGround(vec3 toCentre) {
    int below = int(at_neighbors.w >> 16u) - 1;
    if (trackedEntityRadius <= 0.0 || below < 10053 || below > 10055 || neighborBit(at_neighbors.x, ivec3(0, 1, 0))
        || neighborBit(at_neighbors.x, ivec3(0, -1, 0))) return vec3(0.0);
    vec3 corner[4];
    for (int q = 0; q < 4; q++) {
        ivec3 c = ivec3((q & 1) == 0 ? -1 : 1, 1, (q & 2) == 0 ? -1 : 1);
        uint solid = 1u;
        bool stays = false;
        for (int k = 1; k < 8; k++) {
            ivec3 o = ivec3(0, -1, 0) + ivec3(k & 1, (k >> 1) & 1, k >> 2) * c;
            if (all(equal(o, ivec3(0)))) continue;
            if (neighborBit(at_neighbors.z, o)) solid |= 1u << uint(k);
            else if (neighborBit(at_neighbors.y, o)) stays = true;
        }
        vec3 nrm;
        corner[q] = vec3(0.0);
        if (!stays) netsPoint(solid, c, corner[q], nrm);
    }
    vec2 f = clamp(0.5 - toCentre.xz, 0.0, 1.0);
    return mix(mix(corner[0], corner[1], f.x), mix(corner[2], corner[3], f.x), f.y);
}
#endif

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = lightmapRemap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    glcolor = gl_Color;

    vec2 midTc = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
    vec2 halfTc = abs(texcoord - midTc);
    spriteRect = vec4(midTc - halfTc, halfTc * 2.0);
    blockIdV = int(mc_Entity.x + 0.5);
    playerPosV = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;

    mat3 toWorld = mat3(gbufferModelViewInverse);

    vec3 tangent = at_tangent.xyz;
    if (dot(tangent, tangent) < 1e-6)
        tangent = abs(gl_Normal.y) < 0.99 ? cross(gl_Normal, vec3(0.0, 1.0, 0.0)) : vec3(1.0, 0.0, 0.0);
    vec3 N = normalize(gl_NormalMatrix * gl_Normal);
    vec3 T = normalize(gl_NormalMatrix * tangent);
    vec3 B = normalize(gl_NormalMatrix * (cross(tangent, gl_Normal) * (at_tangent.w < 0.0 ? -1.0 : 1.0)));
    tbn = mat3(toWorld * T, toWorld * B, toWorld * N);

    gl_Position = ftransform();

#if defined PROGRAM_TERRAIN
    int id = int(mc_Entity.x + 0.5);
    matId = 1;
    if (id == 10002) matId = 2;
    else if (id == 10003 || id == 10006 || id == 10018) matId = 3;
    else if (id == 10004 || (id >= 10009 && id <= 10015) || id == 10017) matId = 4;
    else if (id == 10005) matId = 5;
    else if (id >= 10060 && id <= 10071) matId = 7;
    else if (id == 10019 || id == 10029) matId = 8;

    vec3 playerPos = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    #ifdef SMOOTH_TERRAIN
    if (smoothGround(id)) {

        matId = 9;
        vec3 sOff, sN;
        vec3 toCentre = at_midBlock / 64.0, faceN = tbn[2], ac = abs(toCentre);
        bool onCorner = all(greaterThan(ac, vec3(0.45))) && all(lessThan(ac, vec3(0.55)));
        ivec3 sc = ivec3(-sign(toCentre));
        if (onCorner && groundCorner(sc, sOff, sN)) {
            playerPos += sOff;
            float hand = dot(cross(tbn[2], tbn[0]), tbn[1]) < 0.0 ? -1.0 : 1.0;
            vec3 Tw = tbn[0] - sN * dot(tbn[0], sN);
            Tw = dot(Tw, Tw) > 1e-6 ? normalize(Tw) : normalize(cross(sN, abs(sN.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
            tbn = mat3(Tw, cross(sN, Tw) * hand, sN);
        }

        if (id == 10055 && onCorner && abs(faceN.y) < 0.5) {
            int axis = abs(faceN.x) > 0.5 ? 0 : 2;
            float k = mix(1.0, 0.18, smoothstep(0.3, 0.6, smoothFaceUp(axis, sc, faceN)));
            texcoord.y = spriteRect.y + (texcoord.y - spriteRect.y) * k;
        }
    } else if (id == 10003) {
        playerPos += plantOnGround(at_midBlock / 64.0);
    }
    #endif
    vec3 wave = getWaving(playerPos + cameraPosition, id, at_midBlock, lmcoord.y);
    gl_Position = taaClipPosition(playerPos + wave);
    playerPosV = playerPos + wave;
#elif defined PROGRAM_ENTITIES
    matId = 6;
    if (int(mc_Entity.x + 0.5) == 829925) matId = 8;
    gl_Position = taaClipPosition((gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz);
#elif defined PROGRAM_HAND
    matId = 250;
    gl_Position.xy += taaOffset() * gl_Position.w;
#else
    matId = 1;
    gl_Position = taaClipPosition((gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz);
#endif
}
#endif

#ifdef GSH
layout(triangles) in;
layout(triangle_strip, max_vertices = 35) out;

in vec2 vsTexcoord[];
in vec2 vsLm[];
in vec4 vsColor[];
in mat3 vsTbn[];
flat in int vsMat[];
in vec3 vsPlayer[];

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out mat3 tbn;
flat out int matId;
out vec3 snowWorld;
flat out vec2 snowInfo;

void emitBary(vec3 w, int kind, float yTop, float yBot, float maxPress) {
    vec3 p = vsPlayer[0] * w.x + vsPlayer[1] * w.y + vsPlayer[2] * w.z;
    vec3 world = p + cameraPosition;
    #ifdef USE_SNOW_GEOMETRY
    if (kind != 0) {
        float fade = snowDetailFade(p);
        if (fade > 0.0) {
            vec3 deform;

            float h = snowSurface(vec3(world.x, yTop, world.z), maxPress, deform) * fade;
            p.y += kind == 1 ? h : h * saturate((world.y - yBot) / max(yTop - yBot, 1e-3));
        }
    }
    #endif
    gl_Position = taaClipPosition(p);
    texcoord = vsTexcoord[0] * w.x + vsTexcoord[1] * w.y + vsTexcoord[2] * w.z;
    lmcoord = vsLm[0] * w.x + vsLm[1] * w.y + vsLm[2] * w.z;
    glcolor = vsColor[0] * w.x + vsColor[1] * w.y + vsColor[2] * w.z;
    tbn = vsTbn[0] * w.x + vsTbn[1] * w.y + vsTbn[2] * w.z;
    matId = vsMat[0];
    snowWorld = world;
    snowInfo = vec2(kind == 1 ? 1.0 : 0.0, maxPress);
    EmitVertex();
}

void main() {
    int kind = 0;
    float yTop = 0.0, yBot = 0.0, maxPress = 0.0;
    bool detail = false;
    if (vsMat[0] == 8) {
        vec3 geoN = normalize(cross(vsPlayer[1] - vsPlayer[0], vsPlayer[2] - vsPlayer[0]));
        kind = geoN.y > 0.9 ? 1 : (abs(geoN.y) < 0.1 ? 2 : 0);
        yTop = max(vsPlayer[0].y, max(vsPlayer[1].y, vsPlayer[2].y)) + cameraPosition.y;
        yBot = min(vsPlayer[0].y, min(vsPlayer[1].y, vsPlayer[2].y)) + cameraPosition.y;
        maxPress = snowMaxPress(yTop);
        #ifdef USE_SNOW_GEOMETRY
        float near = min(length(vsPlayer[0].xz), min(length(vsPlayer[1].xz), length(vsPlayer[2].xz)));
        detail = kind != 0 && near < SNOW_DETAIL_END + 1.5;
        #endif
    }
    if (!detail) {
        for (int i = 0; i < 3; i++) {
            gl_Position = gl_in[i].gl_Position;
            texcoord = vsTexcoord[i];
            lmcoord = vsLm[i];
            glcolor = vsColor[i];
            tbn = vsTbn[i];
            matId = vsMat[i];
            snowWorld = vsPlayer[i] + cameraPosition;
            snowInfo = vec2(kind == 1 ? 1.0 : 0.0, maxPress);
            EmitVertex();
        }
        EndPrimitive();
        return;
    }

    const int N = SNOW_SUBDIV;
    for (int j = 0; j < N; j++) {
        float b = float(j) / float(N), b1 = float(j + 1) / float(N);
        for (int i = 0; i <= N - j; i++) {
            float c = float(i) / float(N);
            emitBary(vec3(1.0 - b - c, b, c), kind, yTop, yBot, maxPress);
            if (i < N - j) emitBary(vec3(1.0 - b1 - c, b1, c), kind, yTop, yBot, maxPress);
        }
        EndPrimitive();
    }
}
#endif

#ifdef FSH
uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform ivec2 atlasSize;
uniform vec4 entityColor;

layout(location = 0) out vec4 out0;
layout(location = 1) out vec4 out1;
layout(location = 2) out vec4 out2;
layout(location = 3) out vec4 out5;

void main() {
    vec2 uv = texcoord;
    vec2 uvDx = dFdx(texcoord), uvDy = dFdy(texcoord);
    float pomShadow = 1.0;
    #if defined PARALLAX && defined PROGRAM_TERRAIN

    bool genHeights = false;
    vec2 spriteTexels = spriteRect.zw * vec2(atlasSize);
    {
        float distP = length(playerPosV);
        float fade = 1.0 - smoothstep(POM_DISTANCE * 0.7, POM_DISTANCE, distP);
        if (fade > 0.0 && matId != 3 && matId != 8 && spriteRect.z > 0.0) {

            vec2 mid = spriteRect.xy + spriteRect.zw * 0.5;
            float lodAvg = log2(max(spriteTexels.x, 1.0));
            if (textureLod(normals, mid, lodAvg).a < 0.985 || textureLod(normals, spriteRect.xy + spriteRect.zw * 0.25, 0.0).a < 0.985) {
                pomSource = 1;
            }
            #ifdef GENERATED_PARALLAX
            else if ((blockIdV >= 10051 && blockIdV <= 10055) || (blockIdV >= 10060 && blockIdV <= 10070)) {
                bool flatN = true;
                for (int k = 0; k < 4; k++) {
                    vec3 nn = textureLod(normals, spriteRect.xy + spriteRect.zw * (vec2(k & 1, k >> 1) * 0.5 + 0.25), 0.0).xyz;
                    flatN = flatN && abs(nn.x - 0.5) + abs(nn.y - 0.5) < 0.03;
                }
                if (flatN) {
                    pomSource = 2;
                    genHeights = true;

                    pomAvgLum = dot(textureLod(gtexture, mid, lodAvg).rgb, vec3(0.2126, 0.7152, 0.0722));
                    pomContrast = blockIdV == 10052 ? -3.0 : 3.0;
                    pomDepthScale = 0.5;
                }
            }
            #endif
            if (pomSource != 0) {
                vec3 Vw = -playerPosV / max(distP, 1e-4);
                vec3 Lw = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
                mat3 tbnN = mat3(normalize(tbn[0]), normalize(tbn[1]), normalize(tbn[2]));
                vec3 viewTS = vec3(dot(Vw, tbnN[0]), dot(Vw, tbnN[1]), dot(Vw, tbnN[2]));
                vec3 lightTS = vec3(dot(Lw, tbnN[0]), dot(Lw, tbnN[1]), dot(Lw, tbnN[2]));
                float pomDepth;
                uv = parallaxUv(texcoord, spriteRect, viewTS, lightTS, fade, gtexture, normals, pomShadow, pomDepth);
            }
        }
    }
    #endif
    vec4 albedo = textureGrad(gtexture, uv, uvDx, uvDy) * glcolor;
    if (albedo.a < 0.1) discard;

    #ifdef PROGRAM_ENTITIES

    if (entityId == 20010) discard;
    albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
    #endif

    vec3 normal = normalize(tbn[2]);
    Material mtl = decodeMaterial(textureGrad(normals, uv, uvDx, uvDy), textureGrad(specular, uv, uvDx, uvDy));
    #ifdef NORMAL_MAPPING
    normal = normalize(tbn * mtl.normalTS);
    #else
    mtl.ao = 1.0;
    #endif
    #if defined PARALLAX && defined PROGRAM_TERRAIN

    if (genHeights) normal = normalize(tbn * pomNormal(gtexture, normals, uv, spriteRect, spriteTexels));
    #endif
    if (any(isnan(normal))) normal = vec3(0.0, 1.0, 0.0);
    #ifdef PROGRAM_TERRAIN

    if (!gl_FrontFacing) normal = -normal;
    #endif
    if (matId == 3) normal = vec3(0.0, 1.0, 0.0);
    float snowSmooth = -1.0, snowGlitter = 0.0;

    #if defined PROGRAM_TERRAIN && defined SNOW_TRACKS_READ

    if (blockIdV == 10053 && tbn[2].y > 0.5) {
        vec2 rimGradS;
        float packedS;
        vec4 trS = snowDeformSmooth(playerPosV + cameraPosition, rimGradS, packedS);
        if (trS.x + trS.y > 0.002) {

            vec2 g = -trS.zw * 0.26 + rimGradS * 0.13;
            normal = normalize(normal + vec3(-g.x, 0.0, -g.y));
            float pressS = saturate(trS.x * 1.6 + packedS * 0.6);
            albedo.rgb *= mix(1.0, 0.74, pressS) * mix(1.0, 1.06, saturate(trS.y * 2.0));
        }
    }
    #endif

    #if defined TERRAIN_GSH && defined SNOW_TRACKS_READ

    if (matId == 8 && snowInfo.x > 0.5) {
        vec3 w = snowWorld;

        const float e = 0.03;
        float r0 = snowRelief(w.xz);
        vec2 gRelief = vec2(snowRelief(w.xz + vec2(e, 0.0)) - r0, snowRelief(w.xz + vec2(0.0, e)) - r0) / e;
        vec2 rimGrad;
        float packedTraffic;
        vec4 tr = snowDeformSmooth(w, rimGrad, packedTraffic);
        vec3 deform = vec3(tr.x, tr.y, packedTraffic);
        vec2 g = gRelief * (1.0 - tr.x) - r0 * tr.zw - tr.zw * snowInfo.y + rimGrad * 0.05;
        float fp = length(fwidth(w.xz));
        float near = 1.0 - smoothstep(0.004, 0.03, fp);
        if (near > 0.0) {
            vec2 q = w.xz * 38.0;
            float n0 = valueNoise(q), nx = valueNoise(q + vec2(0.25, 0.0)), nz = valueNoise(q + vec2(0.0, 0.25));
            g += vec2(nx - n0, nz - n0) * 4.0 * 0.06 * (1.0 - deform.x * 0.7) * near;
        }
        normal = normalize(vec3(-g.x, 1.0, -g.y));

        float packedSnow = saturate(deform.x * 0.6 + deform.z * 0.8);
        albedo.rgb *= mix(vec3(1.0), vec3(0.86, 0.9, 0.97), packedSnow);
        snowSmooth = mix(0.25, 0.5, packedSnow);

        vec2 cellG = floor(w.xz * 70.0);
        float r = hash12(cellG);
        if (r > 0.975 && near > 0.0) {
            vec2 tilt = hash22(cellG + 17.0) - 0.5;
            normal = normalize(normal + vec3(tilt.x, 0.0, tilt.y) * 0.9);
            snowSmooth = 0.93;
            snowGlitter = near;
        }
    }
    #endif

    float smoothness = 0.0, f0 = 0.0, emissive = 0.0;
    #ifdef PBR_SPECULAR
    #if defined INTEGRATED_PBR && defined PROGRAM_TERRAIN

    if (!mtl.hasSpecular) {
        if (!integratedMaterial(blockIdV, albedo.rgb, mtl)) { mtl.smoothness = 0.0; mtl.f0 = 0.0; }
    }
    #endif
    smoothness = mtl.smoothness;
    f0 = mtl.f0;
    emissive = mtl.emissive;
    #endif
    if (snowSmooth >= 0.0) { smoothness = snowSmooth; f0 = mix(0.02, 0.06, snowGlitter); }
    if (matId == 4) emissive = max(emissive, smoothstep(0.55, 0.9, max(albedo.r, max(albedo.g, albedo.b))));
    if (matId == 5) emissive = 1.0;
    #ifdef EMISSIVE_ORES
    if (matId == 7) {

        float mx = max(albedo.r, max(albedo.g, albedo.b)), mn = min(albedo.r, min(albedo.g, albedo.b));
        float sat = (mx - mn) / max(mx, 1e-3);
        emissive = max(emissive, smoothstep(0.3, 0.6, sat) * smoothstep(0.2, 0.5, mx) * 0.3);
    }
    #endif

    out0 = vec4(albedo.rgb, 1.0);
    out1 = vec4(encodeNormal(normal), lmcoord);
    out2 = vec4(float(matId) / 255.0, smoothness, f0, emissive);

    float poreSss = mtl.sss > 0.0 ? 0.5 + 0.5 * mtl.sss : 0.5 * mtl.porosity;
    out5 = vec4(1.0 - mtl.ao, 1.0 - pomShadow, 0.0, poreSss);

    #if defined PROGRAM_ENTITIES && defined USE_RIPPLES

    {
        vec3 wp = playerPosV + cameraPosition;
        vec3 eye = cameraPosition - relativeEyePosition;
        bool me = length(wp.xz - eye.xz) < 0.45 && wp.y < eye.y + 0.5 && wp.y > eye.y - 2.2;
        float level;
        if (!me && waterLevelNear(wp.xz, level) && wp.y < level + 0.15 && wp.y > level - 1.2)
            injectRipple(wp, entityId == 20002 ? 0.9 : 0.6);
    }
    #endif
}
#endif
