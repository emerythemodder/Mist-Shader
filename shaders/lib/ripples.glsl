#define RIPPLE_RANGE 24.0
#define FRAME_COUNTER_WRAP 720720

layout(rgba16f) uniform image2D rippleImgA;
layout(rgba16f) uniform image2D rippleImgB;
layout(r32f)  uniform image2D rippleClockImg;
#include "/lib/ripple_act.glsl"
#include "/lib/contact.glsl"

ivec2 rippleCell(vec2 worldXZ) { return ivec2(floor(worldXZ * RIPPLE_CELLS)); }
ivec2 rippleTexel(ivec2 cell)  { return cell & (RIPPLE_RES - 1); }

bool inRippleRange(vec3 worldPos) {
    vec2 d = abs(worldPos.xz - cameraPosition.xz);
    return max(d.x, d.y) < RIPPLE_RANGE;
}

void stampWaterLevel(vec3 worldPos) {
    if (!inRippleRange(worldPos)) return;
    imageStore(waterLevelImg, contactTexel(rippleCell(worldPos.xz), CONTACT_WATER), vec4(worldPos.y, float(frameCounter), 0.0, 0.0));
}

bool waterLevelAt(ivec2 cell, out float level, int maxAge) {
    vec2 s = imageLoad(waterLevelImg, contactTexel(cell, CONTACT_WATER)).xy;
    int age = frameCounter - int(s.y);
    if (age < 0) age += FRAME_COUNTER_WRAP;
    level = s.x;
    return s.y > 0.0 && age <= maxAge;
}

bool waterLevelAt(ivec2 cell, out float level) { return waterLevelAt(cell, level, 1200); }

bool waterLevelNear(vec2 worldXZ, out float level) {
    ivec2 c = rippleCell(worldXZ);
    if (waterLevelAt(c, level)) return true;
    for (int k = 0; k < 16; k++) {
        float a = float(k) * 0.785398 + (k < 8 ? 0.0 : 0.3927);
        if (waterLevelAt(c + ivec2(round(vec2(cos(a), sin(a)) * (k < 8 ? 4.0 : 10.0))), level)) return true;
    }
    return false;
}

void injectRipple(vec3 worldPos, float strength) {
    if (!inRippleRange(worldPos)) return;
    ivec2 c = rippleCell(worldPos.xz);
    for (int y = -1; y <= 1; y++)
        for (int x = -1; x <= 1; x++)
            imageStore(rippleInjectImg, contactTexel(c + ivec2(x, y), CONTACT_WATER), vec4(strength, float(frameCounter), 0.0, 0.0));
    #ifdef RIPPLE_ACT_WRITE
    rippleMarkActive(c);
    #endif
}

void injectRippleParticle(vec3 worldPos, float strength) {
    if (!inRippleRange(worldPos)) return;
    ivec2 tx = contactTexel(rippleCell(worldPos.xz), CONTACT_WATER);
    vec2 old = imageLoad(rippleInjectImg, tx).xy;
    if (int(old.y) == frameCounter && old.x >= strength) return;
    imageStore(rippleInjectImg, tx, vec4(-strength, float(frameCounter), 0.0, 0.0));
    #ifdef RIPPLE_ACT_WRITE
    rippleMarkActive(rippleCell(worldPos.xz));
    #endif
}

vec4 rippleCellState(ivec2 cell) {
    ivec2 t = rippleTexel(cell);
    return (frameCounter & 1) == 0 ? imageLoad(rippleImgB, t) : imageLoad(rippleImgA, t);
}

#include "/lib/ripple_look.glsl"
