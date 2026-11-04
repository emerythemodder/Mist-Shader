#ifndef CONTACT_GLSL
#define CONTACT_GLSL

layout(rg32f) uniform image2D waterLevelImg;
layout(rg32f) uniform image2D rippleInjectImg;

#define CONTACT_WATER 0
#define CONTACT_SNOW 1
#define CONTACT_BODY 1
ivec2 contactTexel(ivec2 cell, int kind) {
    ivec2 t = cell & (RIPPLE_RES - 1);
    return ivec2(t.x * 2 + kind, t.y);
}

void bodyContact(vec3 worldPos) {
    vec2 d = abs(worldPos.xz - cameraPosition.xz);
    if (max(d.x, d.y) > 30.0) return;
    ivec2 t = contactTexel(ivec2(floor(worldPos.xz * RIPPLE_CELLS)), CONTACT_BODY);
    vec2 old = imageLoad(rippleInjectImg, t).xy;
    if (int(old.y) != frameCounter || worldPos.y < old.x) imageStore(rippleInjectImg, t, vec4(worldPos.y, float(frameCounter), 0.0, 0.0));
}
#endif
