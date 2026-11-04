#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/shadows.glsl"
#include "/lib/clouds.glsl"
#if defined USE_IBL && defined FSH
#include "/lib/envprobe.glsl"
#endif
#if defined USE_RT_LIGHTS && defined FSH
#define PT_TRACE
#include "/lib/rt_lights.glsl"
#endif
#include "/lib/rt_half_common.glsl"
#include "/lib/flashlight.glsl"
#if defined SNOW_TRACKS_READ && defined USE_SNOW_GEOMETRY && defined FSH
#include "/lib/snow.glsl"

float snowSelfShadow(vec3 worldPos, vec3 L, float dither) {
    float fade = snowDetailFade(worldPos - cameraPosition);
    if (fade <= 0.0 || L.y <= 0.02) return 1.0;
    vec3 dIgnore;
    float maxPress = SNOW_MAX_PRESS;

    float base = worldPos.y - snowSurface(worldPos, maxPress, dIgnore) * fade;
    float lit = 1.0;
    for (int i = 0; i < 10; i++) {
        float t = (float(i) + dither) * 0.22 + 0.05;
        vec3 p = worldPos + L * t;
        float h = base + snowSurface(vec3(p.x, base, p.z), maxPress, dIgnore) * fade;
        lit = min(lit, saturate((p.y - h) / (0.04 + t * 0.02) + 0.5));
    }
    return lit;
}
#endif

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

flat VARY vec3 directLight;
flat VARY vec3 ambientLight;

#ifdef VSH
void main() {
    gl_Position = ftransform();
    getLightColors(directLight, ambientLight);
}
#endif

#ifdef FSH
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex1;

#ifdef RT_HALF_GI
uniform sampler2D colortex10;
layout(location = 0) out vec4 out10;

void main() {
    vec2 view = vec2(viewWidth, viewHeight);
    ivec2 halfRes = ivec2(ceil(view * 0.5));
    ivec2 h = ivec2(gl_FragCoord.xy);
    out10 = texelFetch(colortex10, h, 0);
    #ifdef USE_PT
    if (h.x >= halfRes.x || h.y >= halfRes.y) return;

    ivec2 p = rtHalfSource(h);
    float depth = texelFetch(depthtex1, p, 0).r;
    if (depth >= 1.0 || depth < 0.56) return;
    vec4 c1 = texelFetch(colortex1, p, 0);
    int mat = int(texelFetch(colortex2, p, 0).r * 255.0 + 0.5);
    if (mat == 254 || mat == 250) return;

    vec2 uv = (vec2(p) + 0.5) / view;
    vec3 playerPos = uncurveWorld(viewToPlayer(screenToView(vec3(uv, depth))));
    vec3 normal = decodeNormal(c1.xy);
    vec2 lm = c1.zw;
    float cloud = 1.0;
    #ifdef USE_CLOUD_SHADOWS
    cloud = cloudShadow(playerPos + cameraPosition);
    #endif

    float skyAccess = smoothstep(0.02, 0.35, lm.y);

    uvec3 rv = uvec3(uvec2(p), uint(frameCounter)) * uvec3(1664525u, 1013904223u, 2654435761u);
    rv.x += rv.y * rv.z; rv.y += rv.z * rv.x; rv.z += rv.x * rv.y;
    rv ^= rv >> 16u;
    rv.x += rv.y * rv.z; rv.y += rv.z * rv.x;
    vec2 rnd = vec2(rv.xy) * (1.0 / 4294967296.0);
    vec3 giPos = mat == 8 && normal.y > 0.3 ? playerPos + vec3(0.0, 0.25, 0.0) : playerPos;
    vec3 gi = ptIndirect(giPos, normal, rnd, skyAccess, directLight * cloud, PI * ambientLight);
    if (any(isnan(gi)) || any(isinf(gi))) gi = vec3(0.0);
    gi = min(gi, vec3(60.0));
    out10 = vec4(gi, out10.a);
    #endif
}
#else
layout(location = 0) out vec4 out3;
layout(location = 1) out vec4 out9;
layout(location = 2) out vec4 out10;

void main() {
    out3 = vec4(1.0);
    out9 = vec4(0.0, 0.0, 0.0, 1.0);
    out10 = vec4(0.0);
    vec2 view = vec2(viewWidth, viewHeight);
    ivec2 halfRes = ivec2(ceil(view * 0.5));
    ivec2 h = ivec2(gl_FragCoord.xy);
    if (h.x >= halfRes.x || h.y >= halfRes.y) return;

    ivec2 p = rtHalfSource(h);
    float depth = texelFetch(depthtex1, p, 0).r;
    if (depth >= 1.0 || depth < 0.56) return;
    vec4 c1 = texelFetch(colortex1, p, 0);
    int mat = int(texelFetch(colortex2, p, 0).r * 255.0 + 0.5);
    if (mat == 254 || mat == 250) return;

    vec2 uv = (vec2(p) + 0.5) / view;
    vec3 playerPos = uncurveWorld(viewToPlayer(screenToView(vec3(uv, depth))));
    vec3 normal = decodeNormal(c1.xy);
    vec2 lm = c1.zw;
    float smoothness = texelFetch(colortex2, p, 0).g;
    bool isFoliage = mat == 2 || mat == 3;
    float dither = temporalNoise(vec2(p) + 0.5);
    vec3 L = getLightDir();
    float NdotL = dot(normal, L);
    vec3 V = -normalize(playerPos);

    vec3 sunMixed = vec3(1.0);
    float sunCov = 0.0;
    #ifdef USE_RT_SUN_SHADOWS
    if (NdotL > 0.0 || isFoliage) {
        vec3 start = isFoliage && NdotL <= 0.0 ? L * (mat == 2 ? 1.05 : 0.15) : normal * 0.03;
        float relief = 1.0;
        #if defined SNOW_TRACKS_READ && defined USE_SNOW_GEOMETRY
        if (mat == 8 && normal.y > 0.3) {

            start += vec3(0.0, 0.25, 0.0);
            relief = snowSelfShadow(playerPos + cameraPosition, L, dither);
        }
        #endif
        rtSkipStart = isFoliage;
        float cov;
        sunMixed = rtSunShadow(playerPos, normal, start, L, dither, cov) * relief;
        rtSkipStart = false;
        sunCov = cov;
    }
    #endif
    float cloud = 1.0;
    #ifdef USE_CLOUD_SHADOWS
    cloud = cloudShadow(playerPos + cameraPosition);
    #endif

    float ao = 1.0;
    #ifdef USE_RT_AO
    if (length(playerPos) < 36.0) ao = rtAmbientOcclusion(playerPos, normal, dither);
    #endif

    vec3 light = vec3(0.0);
    #ifdef USE_RT_LIGHTS
    float held = float(max(heldBlockLightValue, heldBlockLightValue2));
    float lmBlock = held > 0.0 ? max(lm.x, saturate((held - length(playerPos)) / 15.0)) : lm.x;
    float cov;
    light = rtBlockLight(playerPos, normal, isFoliage, lmBlock, dither, V, smoothness, cov);
    #ifdef HAND_LIGHT
    if (held > 0.0) light += rtHandLight(playerPos, normal, false, held, dither);
    #endif
    #ifdef USE_RT_SUN_BOUNCE
    if (luminance(directLight) > 0.01 && lm.y > 0.05)
        light += directLight * rtSunBounce(playerPos, normal, L, dither) * smoothstep(0.05, 0.4, lm.y) * cloud;
    #endif
    #endif

    vec3 gi = vec3(-1.0);

    float flashVis = 1.0;
    #if defined USE_FLASHLIGHT && defined USE_RT_LIGHTS
    if (flashlightOn()) {
        vec3 fo, fd;
        flashlightFrame(fo, fd);
        vec3 toL = fo - playerPos;
        float fDist = length(toL);
        toL /= max(fDist, 1e-4);
        if (fDist > 0.9 && fDist < 64.0 && dot(normal, toL) > 0.0 && flashlightBeam(dot(-toL, fd)) > 0.001) {
            vec3 vpF = toVoxelSpace(playerPos) + normal * 0.03;
            vec3 eF = min(vpF, vec3(voxelSize()) - vpF);
            if (min(eF.x, min(eF.y, eF.z)) > 1.0)
                flashVis = luminance(traceVoxels(vpF, toL, fDist - 0.8, ivec3(-1000), 96, true, false));
        }
    }
    #endif

    out3 = vec4(sunMixed, cloud);
    out9 = vec4(light, flashVis);
    out10 = vec4(gi, sunCov);
}
#endif
#endif
