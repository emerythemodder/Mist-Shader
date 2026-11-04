#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/shadows.glsl"
#if defined USE_RIPPLES && defined FSH && !defined PROGRAM_HAND
    #include "/lib/ripples.glsl"
    #define WATER_RIPPLES_ACTIVE
#endif
#if defined USE_MPM && !defined PROGRAM_HAND
    #include "/lib/mpm.glsl"
    #define WATER_MPM
#endif
#ifdef FSH
    #include "/lib/foam.glsl"
    #include "/lib/flashlight.glsl"
    #include "/lib/far_occ.glsl"
#endif
#ifdef PROGRAM_HAND
    #undef WATER_GSH
#endif

#define WATER_SUB 12
#define WATER_GS_INVOCATIONS 6
#define WATER_GS_VERTICES 28
#define WATER_DETAIL 26.0

#if defined VSH && defined WATER_GSH
out vec2 vsTexcoord;
out vec2 vsLm;
out vec4 vsColor;
out vec3 vsPlayer;
out vec3 vsNormal;
flat out int vsIsWater;
out float vsBaseY;
out vec3 vsSea;
#define texcoord vsTexcoord
#define lmcoord vsLm
#define glcolor vsColor
#define playerPos vsPlayer
#define normalW vsNormal
#define isWater vsIsWater
#elif defined VSH || defined FSH
#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif
VARY vec2 texcoord;
VARY vec2 lmcoord;
VARY vec4 glcolor;
VARY vec3 playerPos;
VARY vec3 normalW;
flat VARY int isWater;
#if defined FSH && defined WATER_GSH

vec3 directLight, ambientLight;
#else
flat VARY vec3 directLight;
flat VARY vec3 ambientLight;
#endif
#endif
#if defined FSH && defined WATER_GSH
in float waterBaseY;
in vec3 waterSea;

#endif

#if defined VSH && defined WATER_GSH && defined USE_RIPPLES

uniform sampler2D waterLevelSampler;
float waterFetch(vec3 worldPos) {
    vec2 up = -waterWind();
    for (int i = 1; i <= 28; i++) {
        vec2 q = worldPos.xz + up * float(i);
        vec2 rel = abs(q - cameraPosition.xz);
        if (max(rel.x, rel.y) > 23.0) return 28.0;
        ivec2 c = ivec2(floor(q * RIPPLE_CELLS)) & (RIPPLE_RES - 1);
        vec2 s = texelFetch(waterLevelSampler, ivec2(c.x * 2, c.y), 0).xy;
        int age = frameCounter - int(s.y);
        if (age < 0) age += 720720;
        if (age > 36000 || abs(s.x - worldPos.y) > 0.3) return float(i) - 0.5;
    }
    return 28.0;
}

float waterShoreDistance(vec3 worldPos) {
    float d = 3.0;

    vec2 relV = abs(worldPos.xz - cameraPosition.xz);
    if (max(relV.x, relV.y) > 26.0) return d;
    for (int k = 0; k < 8; k++) {
        float a = float(k) * 0.785398;
        vec2 dir = vec2(cos(a), sin(a));
        for (int i = 1; i <= 6; i++) {
            float r = float(i) * 0.5;
            if (r >= d) break;
            vec2 q = worldPos.xz + dir * r;
            ivec2 c = ivec2(floor(q * RIPPLE_CELLS)) & (RIPPLE_RES - 1);
            vec2 s = texelFetch(waterLevelSampler, ivec2(c.x * 2, c.y), 0).xy;
            int age = frameCounter - int(s.y);
            if (age < 0) age += 720720;
            vec2 rel = abs(q - cameraPosition.xz);
            if (max(rel.x, rel.y) < 23.0 && (age > 36000 || abs(s.x - worldPos.y) > 0.3)) { d = r - 0.5; break; }
        }
    }
    return max(d, 0.0);
}
#endif

#ifdef VSH
in vec4 mc_Entity;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = lightmapRemap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    glcolor = gl_Color;
    isWater = int(mc_Entity.x + 0.5) == 10001 ? 1 : 0;
    #ifdef PROGRAM_HAND
    isWater = 0;
    #endif
    vec4 vertexPos = gl_Vertex;
    #ifdef PHYSICS_OCEAN_V3

    vec4 physics_position = physics_oceanVertex(gl_Vertex);
    if (isWater == 1) vertexPos = physics_position;
    #endif
    playerPos = (gbufferModelViewInverse * (gl_ModelViewMatrix * vertexPos)).xyz;
    vec3 sea = vec3(1.0);
    #ifdef WATER_GSH
    vsBaseY = playerPos.y + cameraPosition.y;
    #ifdef USE_RIPPLES
    if (isWater == 1) {

        float F = waterFetch(playerPos + cameraPosition);
        sea = vec3(mix(0.06, 1.0, pow(saturate(F / 28.0), 0.75)), smoothstep(6.0, 28.0, F),
                   smoothstep(0.0, 2.5, waterShoreDistance(playerPos + cameraPosition)));
    }
    #endif
    vsSea = sea;
    #endif
    #if defined WATER_WAVES && !defined PHYSICS_OCEAN_V3 && !defined PROGRAM_HAND

    if (isWater == 1) {
        vec3 wp = playerPos + cameraPosition;
        if (fract(wp.y) > 0.02) {
            float lift = waterSwell(wp.xz, frameTimeCounter * WAVE_SPEED) * waterSwellHeight() * sea.y * sea.z;
            #ifdef WATER_MPM

            vec3 hsM;
            float wM = mpmCover(wp.xz, wp.y, hsM);
            if (wM > 0.0) lift = mix(lift, hsM.x - wp.y, wM);
            #endif
            playerPos.y += lift;
        }
    }
    #endif
    #ifdef PROGRAM_HAND
    gl_Position = ftransform();
    gl_Position.xy += taaOffset() * gl_Position.w;
    #else
    gl_Position = taaClipPosition(playerPos);
    #endif
    normalW = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
    #ifndef WATER_GSH
    getLightColors(directLight, ambientLight);
    #endif
}
#endif

#ifdef GSH

layout(triangles, invocations = WATER_GS_INVOCATIONS) in;
layout(triangle_strip, max_vertices = WATER_GS_VERTICES) out;

in vec2 vsTexcoord[];
in vec2 vsLm[];
in vec4 vsColor[];
in vec3 vsPlayer[];
in vec3 vsNormal[];
flat in int vsIsWater[];
in float vsBaseY[];
in vec3 vsSea[];

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 playerPos;
out vec3 normalW;
flat out int isWater;
out float waterBaseY;
out vec3 waterSea;

#ifdef WATER_MPM
float cornerMpm[3];

float mpmLift(vec2 xz, float baseY, out float w) {
    vec3 hs;
    w = mpmCover(xz, baseY, hs);
    return w > 0.0 ? (hs.x - baseY) * w : 0.0;
}
#endif

#ifdef USE_RIPPLES

bool faceRipples;

float rippleDisplacement(vec2 xz) {
    if (!rippleActive(xz)) return 0.0;
    vec2 p = xz * RIPPLE_CELLS - 0.5;
    ivec2 i = ivec2(floor(p));
    vec2 t = p - floor(p);
    vec2 it = 1.0 - t, t2 = t * t, t3 = t2 * t;
    vec2 w[4] = vec2[4](it * it * it / 6.0, (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0,
                        (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0, t3 / 6.0);
    float h = 0.0;
    for (int y = 0; y < 4; y++)
        for (int x = 0; x < 4; x++)
            h += rippleHeightAt(i + ivec2(x - 1, y - 1)) * (w[x].x * w[y].y);
    return h * 0.01;
}
#endif

void emitWater(vec3 b, bool surface, float yTop, float yBot) {
    vec3 p = vsPlayer[0] * b.x + vsPlayer[1] * b.y + vsPlayer[2] * b.z;
    float baseY = vsBaseY[0] * b.x + vsBaseY[1] * b.y + vsBaseY[2] * b.z;
    vec3 sea = vsSea[0] * b.x + vsSea[1] * b.y + vsSea[2] * b.z;
    vec3 wp = vec3(p.x + cameraPosition.x, baseY, p.z + cameraPosition.z);

    float dist = length(p.xz);
    float fade = 1.0 - smoothstep(WATER_DETAIL - 10.0, WATER_DETAIL - 2.0, dist);
    float move = surface ? 1.0 : saturate((baseY - yBot) / max(yTop - yBot, 1e-3));
    if (fract(surface ? baseY : yTop) <= 0.02 || fract(surface ? baseY : yTop) >= 0.995) move = 0.0;

    float px = viewHeight * gbufferProjection[1][1] * zoomScale() * 0.5 / max(length(p), 0.1);
    float hfWaves = smoothstep(24.0, 64.0, px);
    float hfRipples = smoothstep(14.0, 48.0, px);
    if (fade > 0.0 && move > 0.0) {
        float h = 0.0;
        #ifdef WATER_WAVES
        float t = frameTimeCounter * WAVE_SPEED;
        float amp = 0.13 * WAVE_HEIGHT * (1.0 + rainStrength * 0.8) / (1.0 + dist * 0.012);
        h += (waveHeight(wp.xz, t, 6) - 0.47) * amp * sea.x * sea.z * hfWaves;
        #endif
        float ripW = 1.0;
        #ifdef WATER_MPM

        float wM;
        h += (mpmLift(wp.xz, baseY, wM) - (cornerMpm[0] * b.x + cornerMpm[1] * b.y + cornerMpm[2] * b.z)) * hfWaves;
        ripW = 1.0 - wM;
        #endif
        #ifdef USE_RIPPLES
        float wRip = (1.0 - smoothstep(18.0, 24.0, dist)) * hfRipples * ripW;
        if (wRip > 0.0 && faceRipples) h += rippleDisplacement(wp.xz) * wRip;
        #endif
        p.y += h * fade * move;
    }
    gl_Position = taaClipPosition(p);
    texcoord = vsTexcoord[0] * b.x + vsTexcoord[1] * b.y + vsTexcoord[2] * b.z;
    lmcoord = vsLm[0] * b.x + vsLm[1] * b.y + vsLm[2] * b.z;
    glcolor = vsColor[0] * b.x + vsColor[1] * b.y + vsColor[2] * b.z;
    normalW = vsNormal[0] * b.x + vsNormal[1] * b.y + vsNormal[2] * b.z;
    playerPos = p;
    isWater = vsIsWater[0];
    waterBaseY = baseY;
    waterSea = sea;
    EmitVertex();
}

void main() {
    bool detail = false, surface = false;
    float yTop = 0.0, yBot = 0.0;
    #if !defined PHYSICS_OCEAN_V3
    if (vsIsWater[0] == 1) {
        float near = min(length(vsPlayer[0].xz), min(length(vsPlayer[1].xz), length(vsPlayer[2].xz)));
        #ifdef USE_WATER_GEOMETRY
        detail = near < WATER_DETAIL;
        #endif
        surface = abs(vsNormal[0].y) > 0.5;
        yTop = max(vsBaseY[0], max(vsBaseY[1], vsBaseY[2]));
        yBot = min(vsBaseY[0], min(vsBaseY[1], vsBaseY[2]));
    }
    #endif

    int N = WATER_SUB;
    if (detail) {
        vec2 halfView = vec2(viewWidth, viewHeight) * 0.5;
        float ext = 1e4;
        if (min(gl_in[0].gl_Position.w, min(gl_in[1].gl_Position.w, gl_in[2].gl_Position.w)) > 0.05) {
            vec2 s0 = gl_in[0].gl_Position.xy / gl_in[0].gl_Position.w * halfView;
            vec2 s1 = gl_in[1].gl_Position.xy / gl_in[1].gl_Position.w * halfView;
            vec2 s2 = gl_in[2].gl_Position.xy / gl_in[2].gl_Position.w * halfView;
            ext = max(length(s1 - s0), max(length(s2 - s1), length(s0 - s2)));
        }
        N = ext > 72.0 ? 12 : (ext > 36.0 ? 6 : (ext > 18.0 ? 3 : 1));
        detail = N > 1;
    }
    if (!detail) {

        if (gl_InvocationID != 0) return;
        for (int i = 0; i < 3; i++) {
            gl_Position = gl_in[i].gl_Position;
            texcoord = vsTexcoord[i];
            lmcoord = vsLm[i];
            glcolor = vsColor[i];
            playerPos = vsPlayer[i];
            normalW = vsNormal[i];
            isWater = vsIsWater[i];
            waterBaseY = vsBaseY[i];
            waterSea = vsSea[i];
            EmitVertex();
        }
        EndPrimitive();
        return;
    }

    int rowA = gl_InvocationID, rowB = N - 1 - gl_InvocationID;
    if (rowA > rowB) return;
    #ifdef USE_RIPPLES
    {

        vec2 lo = min(vsPlayer[0].xz, min(vsPlayer[1].xz, vsPlayer[2].xz)) + cameraPosition.xz - 1e-3;
        vec2 hi = max(vsPlayer[0].xz, max(vsPlayer[1].xz, vsPlayer[2].xz)) + cameraPosition.xz + 1e-3;
        ivec2 g0 = ivec2(floor(lo * RIPPLE_CELLS)) >> 4, g1 = ivec2(floor(hi * RIPPLE_CELLS)) >> 4;
        faceRipples = any(greaterThan(g1 - g0, ivec2(2)));
        for (int y = g0.y; y <= g1.y && !faceRipples; y++)
            for (int x = g0.x; x <= g1.x && !faceRipples; x++)
                faceRipples = rippleAct[(y & 63) * 64 + (x & 63)] == float(frameCounter);
    }
    #endif
    #ifdef WATER_MPM
    for (int k = 0; k < 3; k++) {
        float wk;
        cornerMpm[k] = fract(vsBaseY[k]) > 0.02 ? mpmLift(vsPlayer[k].xz + cameraPosition.xz, vsBaseY[k], wk) : 0.0;
    }
    #endif
    for (int r = 0; r < 2; r++) {
        int j = r == 0 ? rowA : rowB;
        if (r == 1 && rowB == rowA) break;

        for (int v = 0; v <= 2 * (N - j); v++) {
            float b = float(j + (v & 1)) / float(N), c = float(v >> 1) / float(N);
            emitWater(vec3(1.0 - b - c, b, c), surface, yTop, yBot);
        }
        EndPrimitive();
    }
}
#endif

#ifdef FSH
uniform sampler2D gtexture;
layout(location = 0) out vec4 out0;
layout(location = 1) out vec4 out1;
layout(location = 2) out vec4 out2;

void main() {
    vec3 n = normalize(normalW);
    float foam = 0.0;
    #ifdef WATER_GSH
    vec3 sea = waterSea;
    #else
    vec3 sea = vec3(1.0);
    #endif
    #ifdef WATER_GSH
    float waterLevelHere = waterBaseY;
    #else
    float waterLevelHere = playerPos.y + cameraPosition.y;
    #endif
    if (isWater == 1) {
        #ifdef PHYSICS_OCEAN_V3

        PhysicsOceanData ocean = physics_oceanFragment();
        foam = saturate(ocean.foam);
        #endif
        vec3 worldPos = playerPos + cameraPosition;
        float footprint = length(fwidth(worldPos.xz));
        float tW = frameTimeCounter * WAVE_SPEED;
        if (abs(n.y) > 0.5) {
            vec3 wn = vec3(0.0, 1.0, 0.0);
            float foamAmount = 0.0;
            vec2 foamDrift = vec2(0.0);
            #ifdef PHYSICS_OCEAN_V3
            wn = normalize(ocean.normal);
            if (wn.y < 0.0) wn = -wn;
            #else
            #ifdef WATER_WAVES

            float px = length(fwidth(worldPos.xz));
            int iters = int(mix(16.0, 6.0, smoothstep(0.02, 0.6, px)));
            wn = waterNormal(worldPos, length(playerPos), iters);
            wn = normalize(vec3(wn.x / wn.y * sea.x, 1.0, wn.z / wn.y * sea.x));

            float hS = waterSwellHeight() * sea.y * sea.z;
            vec2 slope = vec2(waterSwell(worldPos.xz + vec2(0.1, 0.0), tW) - waterSwell(worldPos.xz - vec2(0.1, 0.0), tW),
                              waterSwell(worldPos.xz + vec2(0.0, 0.1), tW) - waterSwell(worldPos.xz - vec2(0.0, 0.1), tW)) / 0.2 * hS;
            wn = normalize(vec3(wn.x / wn.y - slope.x, 1.0, wn.z / wn.y - slope.y));

            float wind = sea.x * saturate(WAVE_HEIGHT / 2.0) * (1.0 + rainStrength * 0.6 + thunderStrength * 0.6);
            if (n.y > 0.0 && wind > 0.2) {
                float crest = waveHeight(worldPos.xz, tW, 8);
                foamAmount += windFoam(worldPos.xz, frameTimeCounter, crest, wind);
                foamDrift = waterWind() * frameTimeCounter * 0.05;
            }
            #endif
            #endif
            float wMpm = 0.0;
            #ifdef WATER_MPM

            if (n.y > 0.0) {
                vec3 hsM;
                wMpm = mpmCover(worldPos.xz, waterLevelHere, hsM);
                if (wMpm > 0.0) wn = normalize(vec3(wn.x / wn.y - hsM.y * wMpm, 1.0, wn.z / wn.y - hsM.z * wMpm));
            }
            #endif

            float flowSlope = length(n.xz) / max(abs(n.y), 0.1);
            if (n.y > 0.0 && flowSlope > 0.1) foamAmount += flowFoam(worldPos.xz, normalize(n.xz), flowSlope, frameTimeCounter);

            #ifdef WATER_RIPPLES_ACTIVE
            #ifdef WATER_GSH
            vec3 levelPos = vec3(worldPos.x, waterBaseY, worldPos.z);
            #else
            vec3 levelPos = worldPos;
            #endif
            if (n.y > 0.0) stampWaterLevel(levelPos);
            float fade = 1.0 - smoothstep(RIPPLE_RANGE - 6.0, RIPPLE_RANGE, length(playerPos.xz));
            if (fade > 0.0) {

                vec3 rs = rippleSurface(worldPos.xz);
                float fresh = smoothstep(0.25, 0.9, rs.z);

                vec2 g = rs.xy * (1.0 - smoothstep(0.06, 0.25, footprint)) * (1.0 - wMpm) + rippleChop(worldPos.xz, frameTimeCounter, fresh, footprint);
                g *= fade / max(1.0, length(g) / 1.0);
                wn = normalize(vec3(wn.x / wn.y - g.x, 1.0, wn.z / wn.y - g.y));
                foamAmount = max(foamAmount, rs.z * fade);
            }
            #endif
            #ifdef USE_WATER_FOAM
            if (n.y > 0.0) foam = max(foam, foamCover(worldPos.xz, foamAmount * FOAM_AMOUNT, footprint, frameTimeCounter, foamDrift));
            #endif
            n = n.y > 0.0 ? wn : vec3(wn.x, -wn.y, wn.z);
        } else {

            vec3 tA = normalize(cross(n, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
            float across = dot(worldPos, tA);
            float fall = worldPos.y + frameTimeCounter * 4.0;
            float s1 = valueNoise(vec2(across * 6.0, fall * 0.8));
            float s2 = valueNoise(vec2(across * 13.0 + 7.1, fall * 1.6 + 3.0));
            float streak = s1 * 0.65 + s2 * 0.35;
            foam = max(foam, smoothstep(0.42, 0.78, streak) * 0.8);
            float rip = valueNoise(vec2(across * 9.0, fall * 2.2)) - 0.5;
            n = normalize(n + tA * rip * 0.35 + vec3(0.0, (s2 - 0.5) * 0.25, 0.0));
        }
        out0 = vec4(0.0);
        out1 = vec4(glcolor.rgb, foam);
        out2 = vec4(encodeNormal(n), 0.8 + 0.19 * sea.x, lmcoord.y);
        return;
    }

    vec4 c = texture(gtexture, texcoord) * glcolor;
    if (c.a < 0.01) discard;
    #ifdef WATER_GSH
    getLightColors(directLight, ambientLight);
    #endif
    vec3 col = toLinear(c.rgb);

    vec3 L = getLightDir();
    float NdotL = saturate(dot(n, L));
    vec3 sh = vec3(smoothstep(0.85, 0.95, lmcoord.y));
    #if defined USE_SHADOWS && !defined PROGRAM_HAND

    vec3 sunStart = playerPos + cameraPosition + n * 0.05;
    if (NdotL > 0.0 && farCovers(sunStart)) sh = vec3(farTrace(sunStart, L, 160.0, 0.0));
    #endif
    float sk = lmcoord.y * lmcoord.y;
    vec3 light = directLight * sh * NdotL + ambientLight * sk + blockLightColor(lmcoord.x) + MIN_LIGHT;
    #ifdef USE_FLASHLIGHT
    vec3 fL;
    light += flashlightLight(playerPos, n, fL);
    #endif

    out0 = vec4(col * light, c.a);
    out1 = vec4(1.0 / 255.0, 0.0, 0.0, 1.0);
    out2 = vec4(encodeNormal(n), 0.5, lmcoord.y);
}
#endif
