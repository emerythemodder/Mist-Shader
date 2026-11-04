#ifndef BODY_SHADOW_GLSL
#define BODY_SHADOW_GLSL
#include "/lib/shadow_distort.glsl"

uniform sampler2D shadowtex0;

float bodyShadowTexel(vec2 c) {
    float f = length(c) * SHADOW_DISTORT + (1.0 - SHADOW_DISTORT);
    return 2.0 * shadowDistance / float(shadowMapResolution) * f * f / (1.0 - SHADOW_DISTORT);
}

float bodyShadow(vec3 playerPos, vec3 normal, float dither) {
    vec3 L = getLightDir();
    vec4 c = shadowProjection * (shadowModelView * vec4(playerPos, 1.0));
    if (any(greaterThan(abs(c.xy), vec2(0.995)))) return 1.0;
    float texel = bodyShadowTexel(c.xy);

    float NdotL = dot(normal, L);
    vec3 p = playerPos + normal * texel * (0.6 + 1.4 * saturate(1.0 - abs(NdotL)));
    c = shadowProjection * (shadowModelView * vec4(p, 1.0));
    vec3 sc = distortShadowClip(c.xyz) * 0.5 + 0.5;

    float depthToBlocks = 1.0 / (0.1 * abs(shadowProjection[2][2]));
    float bias = (0.03 + texel * 0.5) / depthToBlocks;
    float zr = sc.z - bias;
    float uvPerBlock = 1.0 / (texel * float(shadowMapResolution));

    float sunR = max(RT_SUN_SOFTNESS, 0.0047);
    float ang = dither * TAU;
    mat2 rot = mat2(cos(ang), sin(ang), -sin(ang), cos(ang));

    float searchR = max(24.0 * sunR, texel * 1.5) * uvPerBlock;
    float blockers = 0.0, nb = 0.0;
    for (int i = 0; i < 8; i++) {
        float r = sqrt((float(i) + 0.5) / 8.0);
        float a = float(i) * 2.39996;
        vec2 o = rot * vec2(cos(a), sin(a)) * r * searchR;
        float d = texture(shadowtex0, sc.xy + o).r;
        if (d < zr) { blockers += d; nb += 1.0; }
    }
    if (nb < 0.5) return 1.0;
    float gap = max(sc.z - blockers / nb, 0.0) * depthToBlocks;
    float pen = max(gap * 2.0 * sunR, texel * 0.75) * uvPerBlock;
    float lit = 0.0;
    for (int i = 0; i < 12; i++) {
        float r = sqrt((float(i) + 0.5) / 12.0);
        float a = float(i) * 2.39996 + 1.1;
        vec2 o = rot * vec2(cos(a), sin(a)) * r * pen;
        lit += step(zr, texture(shadowtex0, sc.xy + o).r);
    }
    return lit / 12.0;
}
#endif
