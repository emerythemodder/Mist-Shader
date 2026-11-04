#if defined VSH && defined PROGRAM_TEXTURED
#define RIPPLE_ACT_WRITE
#endif
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"

#if defined PROGRAM_TEXTURED && defined USE_RT_LIGHTS && defined FSH
    #define PARTICLE_RT
    #include "/lib/water.glsl"
    #include "/lib/shadows.glsl"
    #include "/lib/rt_lights.glsl"
#endif

#if defined USE_RIPPLES && defined VSH && defined PROGRAM_TEXTURED
    #define PARTICLE_RIPPLES
    #include "/lib/ripples.glsl"
#endif

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

VARY vec2 texcoord;
VARY vec2 lmcoord;
VARY vec4 glcolor;
VARY vec3 normalW;
VARY vec3 playerPosV;
flat VARY vec3 directLight;
flat VARY vec3 ambientLight;

#ifdef VSH
void main() {
    playerPosV = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    gl_Position = taaClipPosition(playerPosV);
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = lightmapRemap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    glcolor = gl_Color;
    normalW = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
    getLightColors(directLight, ambientLight);
    #ifdef PARTICLE_RIPPLES
    #ifdef MC_RENDER_STAGE_PARTICLES
    if (renderStage == MC_RENDER_STAGE_PARTICLES)
    #endif
    {
        vec3 wp = playerPosV + cameraPosition;
        float level;
        if (waterLevelNear(wp.xz, level) && abs(wp.y - level) < 0.12) injectRippleParticle(wp, 0.3);
    }
    #endif
}
#endif

#ifdef FSH
uniform sampler2D gtexture;
layout(location = 0) out vec4 out0;
#if !defined PROGRAM_WEATHER && !defined PROGRAM_GLINT
layout(location = 1) out vec4 out1;
#endif

void main() {
    #if defined PROGRAM_CLOUDS && defined USE_VOLUMETRIC_CLOUDS
    discard;
    #endif

    #ifdef PROGRAM_BASIC
    vec4 c = glcolor;
    #else
    vec4 c = texture(gtexture, texcoord) * glcolor;
    #endif
    #ifdef PROGRAM_TEXTURED
    if (c.a < 0.1) discard;
    #else
    if (c.a < 0.004) discard;
    #endif

    vec3 col = toLinear(c.rgb);
    #if defined PROGRAM_EMISSIVE || defined PROGRAM_GLINT
    col *= EMISSIVE_STRENGTH * 0.5;
    #elif defined PROGRAM_BASIC
    col *= 0.25 + ambientLight;
    #elif defined PROGRAM_CLOUDS
    vec3 L = getLightDir();
    col *= directLight * (0.5 + 0.5 * saturate(dot(normalW, L))) * 0.8 + ambientLight * 1.2;
    #elif defined PROGRAM_WEATHER
    col *= ambientLight * 1.5 + blockLightColor(lmcoord.x) * 0.5;
    c.a *= 0.4;
    #else
    float sk = lmcoord.y * lmcoord.y;
    vec3 sunVis = vec3(0.45 * sk * sk);
    vec3 blockL = blockLightColor(lmcoord.x);
    #ifdef PARTICLE_RT
    {
        vec3 vp = toVoxelSpace(playerPosV);
        vec3 toEdge = min(vp, vec3(voxelSize()) - vp);
        float cov = smoothstep(2.0, 8.0, min(toEdge.x, min(toEdge.y, toEdge.z)));
        if (cov > 0.0) {
            float dither = temporalNoise(gl_FragCoord.xy);
            vec3 L = getLightDir();
            vec3 vis = vec3(1.0);
            #ifdef WORLD_OVERWORLD
            vec3 sd = normalize(L + vec3(dither - 0.5, 0.0, fract(dither * 7.3) - 0.5) * RT_SUN_SOFTNESS);
            vis = traceVoxels(vp, sd, 32.0, ivec3(-1000), 72, true, true);
            if (rtRayEscaped && max(vis.r, max(vis.g, vis.b)) > 0.0) vis *= farTrace(rtRayEnd + vec3(voxelOrigin()), sd, 200.0, dither * 64.0);
            #endif
            sunVis = mix(sunVis, vis * 0.6 * smoothstep(0.0, 0.2, lmcoord.y), cov);
            blockL = mix(blockL, max(sampleLpv(vp) * BLOCKLIGHT_STRENGTH, blockLightColor(lmcoord.x) * 0.25), cov);
        }
    }
    #endif
    col *= directLight * sunVis + ambientLight * sk * 1.1 + blockL + MIN_LIGHT + nightVision * 0.2;
    #endif

    out0 = vec4(col, c.a);
    #if !defined PROGRAM_WEATHER && !defined PROGRAM_GLINT
    out1 = vec4(254.0 / 255.0, 0.0, 0.0, 1.0);
    #endif
}
#endif
