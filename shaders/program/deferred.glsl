#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/shadows.glsl"
#include "/lib/raytrace.glsl"
#include "/lib/clouds.glsl"
#include "/lib/flashlight.glsl"
#include "/lib/rt_half_common.glsl"
#include "/lib/materials.glsl"
#if defined USE_IBL && defined FSH
#include "/lib/envprobe.glsl"
#endif
#if defined USE_RT_LIGHTS && defined FSH
#include "/lib/rt_lights.glsl"
#endif
#if defined USE_SHADOWS && defined FSH
#include "/lib/body_shadow.glsl"
#elif defined USE_RT_LIGHTS && defined FSH

uniform sampler2D shadowtex0;
#endif

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

VARY vec2 texcoord;
flat VARY vec3 directLight;
flat VARY vec3 ambientLight;

#ifdef VSH
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
    getLightColors(directLight, ambientLight);
}
#endif

#ifdef FSH
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex5;
uniform sampler2D depthtex1;
uniform sampler2D colortex7;
#ifdef USE_RT_HALF
uniform sampler2D colortex3;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex13;

#ifdef VOXY

float lodSunShadow(vec3 viewPos, float dither) {
    vec3 Lv = normalize(shadowLightPosition);
    float dist = length(viewPos);
    float t0 = 0.6 + dist * 0.004;
    for (int i = 0; i < 28; i++) {
        float t = t0 * pow(1.24, float(i) + dither);
        vec3 q = viewPos + Lv * t;
        vec4 clip = vxProj * vec4(q, 1.0);
        if (clip.w <= 0.0) break;
        vec3 s = clip.xyz / clip.w * 0.5 + 0.5;
        if (any(lessThan(s.xy, vec2(0.0))) || any(greaterThan(s.xy, vec2(1.0)))) break;
        float thick = 6.0 + t * 0.35;
        float dL = texture(vxDepthTexOpaque, s.xy).r;
        if (dL < 1.0) {
            float z = lodScreenToView(vec3(s.xy, dL)).z;
            if (z > q.z + 0.25 && z < q.z + thick) return 0.0;
        }
        float dN = texture(depthtex1, s.xy).r;
        if (dN < 1.0) {
            float z = screenToView(vec3(s.xy, dN)).z;
            if (z > q.z + 0.25 && z < q.z + thick) return 0.0;
        }
    }
    return 1.0;
}
#endif

void rtHalfUpsample(ivec2 p, float depth, vec3 normal, out vec4 sun, out vec4 light, out vec4 gi, out float sunCov) {
    ivec2 halfRes = ivec2(ceil(vec2(viewWidth, viewHeight) * 0.5));
    ivec2 h0 = max(p - rtHalfOffset(), ivec2(0)) / 2;
    float z = linearizeDepth(depth);
    sun = vec4(0.0);
    light = vec4(0.0);
    gi = vec4(0.0);
    sunCov = 0.0;
    float wsum = 0.0, best = 1e9;
    vec4 nearSun = vec4(1.0), nearLight = vec4(0.0, 0.0, 0.0, 1.0), nearGi = vec4(0.0);
    float nearCov = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            ivec2 h = clamp(h0 + ivec2(x, y), ivec2(0), halfRes - 1);
            ivec2 r = rtHalfSource(h);
            float dz = abs(linearizeDepth(texelFetch(depthtex1, r, 0).r) - z) / max(z * 0.03, 0.05);
            float nd = saturate(dot(normal, decodeNormal(texelFetch(colortex1, r, 0).xy)));
            vec2 d = vec2(r - p);
            float w = exp(-dot(d, d) * 0.3 - dz * dz) * pow(nd, 6.0);
            vec4 a = texelFetch(colortex3, h, 0), b = texelFetch(colortex9, h, 0);
            #ifdef USE_PT
            vec4 g = texelFetch(colortex13, h, 0);
            #else
            vec4 g = vec4(0.0);
            #endif
            float c = texelFetch(colortex10, h, 0).a;
            sun += a * w;
            light += b * w;
            gi += g * w;
            sunCov += c * w;
            wsum += w;
            float cost = dot(d, d) + dz * 10.0 + (1.0 - nd) * 20.0;
            if (cost < best) { best = cost; nearSun = a; nearLight = b; nearGi = g; nearCov = c; }
        }
    }
    if (wsum > 1e-4) { sun /= wsum; light /= wsum; gi /= wsum; sunCov /= wsum; }
    else { sun = nearSun; light = nearLight; gi = nearGi; sunCov = nearCov; }
}
#endif

layout(location = 0) out vec4 out0;
layout(location = 1) out vec4 out1;
layout(location = 2) out vec4 out2;

void main() {
    vec4 c0 = texture(colortex0, texcoord);
    vec4 c1 = texture(colortex1, texcoord);
    vec4 c2 = texture(colortex2, texcoord);
    out1 = c1;
    out2 = c2;

    float depth = texture(depthtex1, texcoord).r;
    vec3 viewPos = screenToView(vec3(texcoord, depth));
    bool isLod = false;
    #ifdef VOXY
    if (depth >= 1.0) {
        float lodDepth = texture(vxDepthTexOpaque, texcoord).r;
        if (lodDepth < 1.0) { isLod = true; viewPos = lodScreenToView(vec3(texcoord, lodDepth)); }
    }
    #endif
    #ifdef DISTANT_HORIZONS
    if (depth >= 1.0 && !isLod) {
        float dhDepth = texture(dhDepthTex1, texcoord).r;
        if (dhDepth < 1.0) { isLod = true; viewPos = dhScreenToView(vec3(texcoord, dhDepth)); }
    }
    #endif
    vec3 playerPos = uncurveWorld(viewToPlayer(viewPos));
    vec3 worldDir = normalize(playerPos);
    float dither = temporalNoise(gl_FragCoord.xy);
    int mat = int(c2.r * 255.0 + 0.5);

    if (depth >= 1.0 && !isLod) {
        vec3 sky = getSky(worldDir, true);
        #ifdef USE_VOLUMETRIC_CLOUDS

        vec2 view = vec2(viewWidth, viewHeight);
        vec2 halfRes = ceil(view * 0.5);

        vec2 hp = clamp(texcoord * halfRes, vec2(0.5), halfRes - 0.5) - 0.5;
        ivec2 hi = ivec2(floor(hp));
        vec2 hf = hp - floor(hp);
        vec4 cl = vec4(0.0);
        float wsum = 0.0;
        for (int y = 0; y < 2; y++) {
            for (int x = 0; x < 2; x++) {
                vec4 c = texelFetch(colortex7, min(hi + ivec2(x, y), ivec2(halfRes) - 1), 0);
                float w = (x == 0 ? 1.0 - hf.x : hf.x) * (y == 0 ? 1.0 - hf.y : hf.y);
                if (c.a >= 0.0) { cl += c * w; wsum += w; }
            }
        }
        cl = wsum > 1e-4 ? cl / wsum : vec4(0.0, 0.0, 0.0, 1.0);
        sky = sky * saturate(cl.a) + max(cl.rgb, 0.0);
        #endif
        out0 = vec4(sanitize(sky), 1.0);
        out2 = vec4(0.0);
        return;
    }
    if (mat == 254) { out0 = c0; return; }

    vec3 albedo = toLinear(c0.rgb);
    vec3 normal = decodeNormal(c1.xy);
    #ifdef USE_RT_HALF
    vec4 rtS = vec4(1.0), rtL = vec4(0.0, 0.0, 0.0, 1.0), rtG = vec4(0.0);
    float rtSunCov = 0.0;
    if (!isLod && mat != 250) rtHalfUpsample(ivec2(gl_FragCoord.xy), depth, normal, rtS, rtL, rtG, rtSunCov);
    #endif
    vec2 lm = c1.zw;
    float smoothness = c2.g;
    float f0raw = c2.b;
    float emissive = c2.a;
    bool isHand = mat == 250;
    bool isFoliage = mat == 2 || mat == 3;
    bool isSnow = mat == 8;
    bool isMetal = f0raw >= 229.5 / 255.0;

    vec4 c5 = texture(colortex5, texcoord);
    bool extras = c5.z < 0.25;
    float texAO = extras ? 1.0 - c5.x : 1.0;
    float pomShadow = extras ? 1.0 - c5.y : 1.0;
    float matSss = extras && c5.w > 0.5 ? (c5.w - 0.5) * 2.0 : 0.0;
    float porosity = extras && c5.w > 0.0 && c5.w <= 0.5 ? c5.w * 2.0 : -1.0;

    #ifdef SNOW_COVER
    #ifdef WORLD_OVERWORLD

    if (snowCover > 0.002 && !isHand && mat != 6) {
        vec3 swp = playerPos + cameraPosition;
        float up = smoothstep(0.35, 0.85, normal.y) * smoothstep(0.85, 0.97, lm.y);
        float patchy = fbm(swp.xz * 0.9, 3);
        float cover = saturate(up * (snowCover * 1.6 - (1.0 - patchy) * 0.7));
        albedo = mix(albedo, vec3(0.82, 0.86, 0.9), cover);
        smoothness = mix(smoothness, 0.25, cover);
        f0raw = mix(f0raw, 0.02, cover);
    }
    #endif
    #endif

    #ifdef HAND_LIGHT
    float held = float(max(heldBlockLightValue, heldBlockLightValue2));
    if (held > 0.0) lm.x = max(lm.x, saturate((held - length(playerPos)) / 15.0));
    #endif

    #ifdef USE_RAIN_PUDDLES
    float wet = wetness * smoothstep(0.8, 0.95, lm.y) * (1.0 - snowyBiome);
    if (wet > 0.001 && !isHand && mat != 6 && !isFoliage) {
        vec3 wp = playerPos + cameraPosition;
        float up = smoothstep(0.7, 0.98, normal.y);
        float n = fbm(wp.xz * 0.08, 4);
        float puddle = saturate((n - (1.0 - 0.55 * wet * PUDDLE_AMOUNT)) * 6.0) * up;

        float soak = porosity >= 0.0 ? porosity : (isMetal ? 0.0 : 1.0);
        albedo *= mix(1.0, 0.62, wet * soak * (1.0 - puddle * 0.4));
        smoothness = mix(max(smoothness, 0.6 * wet * up), 0.97, puddle);
        normal = normalize(mix(normal, vec3(0.0, 1.0, 0.0), puddle));
        #ifdef RAIN_RIPPLES
        if (puddle > 0.05 && rainStrength > 0.01) {
            vec2 r = rainRipple(wp.xz, frameTimeCounter) * rainStrength * puddle;
            normal = normalize(normal + vec3(r.x, 0.0, r.y) * 0.4);
        }
        #endif
        out1.xy = encodeNormal(normal);
        out2.g = smoothness;
    }
    #endif

    vec3 f0 = isMetal ? labMetalF0(f0raw * 255.0, albedo) : vec3(f0raw > 0.0 ? f0raw : 0.04);
    vec3 L = getLightDir();
    vec3 V = -worldDir;
    float NdotL = dot(normal, L);
    float skyShadowFallback = smoothstep(0.85, 0.95, lm.y);

    vec3 shadow = vec3(0.0);
    #ifdef USE_SHADOWS
    #ifdef USE_RT_HALF
    if (isHand || isLod) {

        shadow = vec3(skyShadowFallback);
    } else if (NdotL > 0.0 || isFoliage) {
        shadow = mix(vec3(skyShadowFallback), rtS.rgb, rtSunCov);
    }
    #else
    shadow = vec3(skyShadowFallback);
    #endif
    #ifdef VOXY
    if (isLod && luminance(shadow) > 0.0 && NdotL > 0.0) shadow *= lodSunShadow(viewPos, dither);
    #endif

    shadow *= smoothstep(0.0, 0.15, lm.y);

    shadow *= pomShadow;

    if (!isHand && !isLod && luminance(shadow) > 0.0) shadow *= bodyShadow(playerPos, normal, dither);
    #ifdef USE_CLOUD_SHADOWS
    #ifdef USE_RT_HALF
    if (!isHand && !isLod) shadow *= rtS.a;
    else if (!isHand && luminance(shadow) > 0.0) shadow *= cloudShadow(playerPos + cameraPosition);
    #else
    if (!isHand && luminance(shadow) > 0.0) shadow *= cloudShadow(playerPos + cameraPosition);
    #endif
    #endif
    #elif defined WORLD_OVERWORLD
    shadow = vec3(skyShadowFallback);
    #endif

    float diff = saturate(NdotL);
    if (isSnow) diff = saturate((NdotL + 0.15) / 1.15);
    if (mat == 3) diff = 0.55 + 0.45 * saturate(L.y);
    else if (mat == 2) diff = saturate((NdotL + 0.5) / 1.5);
    vec3 directDiffuse = directLight * shadow * diff;

    #ifdef SUBSURFACE_SCATTERING

    if (matSss > 0.0 && !isFoliage) {
        float mu = dot(worldDir, L);
        float phase = pow(saturate(mu), 4.0) * 1.5 + 0.25;
        directDiffuse += directLight * luminance(shadow) * phase * matSss * 0.35 * (1.0 - saturate(NdotL));
    }
    if (isFoliage) {
        float mu = dot(worldDir, L);
        float sssPhase = pow(saturate(mu), 6.0) * 2.0 + 0.3;

        float sssVis = luminance(shadow) * smoothstep(0.0, 0.3, lm.y);
        directDiffuse += directLight * sssVis * sssPhase * 0.5 * (1.0 - saturate(NdotL));
    }
    #endif

    float alpha = max((1.0 - smoothness) * (1.0 - smoothness), 0.02);
    vec3 spec = vec3(0.0);
    if (NdotL > 0.0) spec = min(ggxSpecular(normal, V, L, alpha, f0) * directLight * shadow, vec3(40.0));
    #ifdef USE_IBL

    if (!isHand && !isLod) {
        float pr = 1.0 - smoothness;
        vec3 Rv = reflect(-V, normal);
        vec2 ab = envBRDF(saturate(dot(normal, V)), pr);
        float traced = smoothstep(0.4, 0.85, smoothness);
        float eyeSkyS = float(eyeBrightnessSmooth.y) / 240.0;
        float occS = saturate(mix(1.0, lm.y, eyeSkyS));
        spec += envSpecular(Rv, pr) * (f0 * ab.x + ab.y) * occS * occS * (1.0 - traced);
    }
    #endif

    float ao = texAO;
    bool voxelAo = false;
    #ifdef USE_RT_AO
    voxelAo = !isHand && length(playerPos) < 36.0;
    if (voxelAo) ao *= rtAmbientOcclusion(playerPos, normal, dither);
    #endif

    float ptCov = 0.0;
    #ifdef USE_PT
    if (!isHand && !isLod) {
        vec3 vpP = toVoxelSpace(playerPos);
        vec3 eP = min(vpP, vec3(voxelSize()) - vpP);
        ptCov = smoothstep(4.0, 12.0, min(eP.x, min(eP.y, eP.z))) * step(0.5, rtG.a);
    }
    #endif
    float skyL = lm.y * lm.y;

    vec3 ambientTerm = ambientLight * skyL * mix(0.55, 1.0, normal.y * 0.5 + 0.5) * 1.8;
    #ifdef USE_IBL

    float eyeSkyI = float(eyeBrightnessSmooth.y) / 240.0;
    float probeOcc = saturate(mix(1.0, lm.y, eyeSkyI));

    if (!isHand && !isLod) ambientTerm = envDiffuse(normal) * (PI * AMBIENT_STRENGTH) * probeOcc * probeOcc;
    #endif
    #ifdef WORLD_OVERWORLD

    float fakeBounce = 1.0;
    #ifdef USE_RT_SUN_BOUNCE
    {
        vec3 vpB = toVoxelSpace(playerPos);
        vec3 eB = min(vpB, vec3(voxelSize()) - vpB);
        fakeBounce = 1.0 - smoothstep(11.0, 16.0, min(eB.x, min(eB.y, eB.z)));
    }
    #endif
    #ifndef USE_IBL
    ambientTerm += directLight * saturate(L.y) * skyL * (0.5 - 0.5 * normal.y) * 0.1 * fakeBounce;
    #endif
    #endif
    #ifdef USE_PT

    ambientTerm = mix(ambientTerm, rtG.rgb, ptCov);
    #endif
    vec3 blockL = blockLightColor(lm.x);
    #ifdef USE_RT_LIGHTS

    #ifdef USE_RT_HALF
    vec3 vpL = toVoxelSpace(playerPos);
    vec3 eL = min(vpL, vec3(voxelSize()) - vpL);
    float rtCoverage = isLod ? 0.0 : smoothstep(1.0, 10.0, min(eL.x, min(eL.y, eL.z)));
    blockL = mix(blockL, rtL.rgb, rtCoverage);
    #ifdef HAND_LIGHT
    if (held > 0.0 && isHand) blockL += rtHandLight(playerPos, normal, true, held, dither) * rtCoverage;
    #endif
    #else
    float rtCoverage;
    vec3 rtLight = rtBlockLight(playerPos, normal, isFoliage, lm.x, dither, V, smoothness, rtCoverage);
    blockL = mix(blockL, rtLight, rtCoverage);
    #ifdef HAND_LIGHT
    if (held > 0.0) blockL += rtHandLight(playerPos, normal, isHand, held, dither) * rtCoverage;
    #endif
    #endif
    #endif
    #ifdef USE_FLASHLIGHT

    if (!isHand) {
        vec3 fL;
        vec3 fE = flashlightLight(playerPos, normal, fL);
        #ifdef USE_RT_HALF
        if (!isLod) fE *= rtL.a;
        #endif
        float fN = saturate(dot(normal, fL));
        if (fN > 0.0) {
            blockL += fE;
            spec += min(ggxSpecular(normal, V, fL, alpha, f0) * fE / fN, vec3(40.0));
        }
    }
    #endif
    vec3 minL = MIN_LIGHT + nightVision * vec3(0.3);

    vec3 color;
    if (isMetal) {
        color = albedo * ((ambientTerm + minL) * ao + blockL * mix(1.0, ao, 0.5)) * 0.6;
    } else {
        color = albedo * (directDiffuse + (ambientTerm + minL) * ao + blockL * mix(1.0, ao, 0.5));
    }
    color += spec;

    if (!isHand) color += ambientLight * skyL * ao * schlick(saturate(dot(normal, V)), 0.02) * 0.3 * (1.0 - 0.5 * float(isFoliage));
    color += albedo * emissive * EMISSIVE_STRENGTH;

    #ifdef SPAWN_WARNING

    if (!isHand && !isLod && max(heldBlockLightValue, heldBlockLightValue2) > 0 && normal.y > 0.9
        && (mat == 1 || mat == 7 || mat == 8 || mat == 9) && c1.z < 0.5 / 15.0 && length(playerPos) < 24.0) {
        vec2 f = fract(playerPos.xz + cameraPosition.xz);
        float line = min(abs(f.x - f.y), abs(f.x + f.y - 1.0));
        float mark = (1.0 - smoothstep(0.03, 0.06, line)) * step(0.12, f.x) * step(f.x, 0.88);
        color += vec3(0.6, 0.02, 0.02) * mark * 0.15 * (1.0 - smoothstep(18.0, 24.0, length(playerPos)));
    }
    #endif

    #if !defined USE_SHADOWS && defined USE_RT_LIGHTS
    if (texelFetch(shadowtex0, ivec2(0), 0).r < 0.0) color = vec3(0.0);
    #endif
    out0 = vec4(sanitize(color), 1.0);
}
#endif
