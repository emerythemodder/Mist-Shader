#ifndef SHADOW_DISTORT_GLSL
#define SHADOW_DISTORT_GLSL

vec3 distortShadowClip(vec3 c) {
    float f = length(c.xy) * SHADOW_DISTORT + (1.0 - SHADOW_DISTORT);
    return vec3(c.xy / f, c.z * 0.2);
}
#endif
