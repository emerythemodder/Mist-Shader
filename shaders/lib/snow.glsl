#define SNOW_RES 1024
#define SNOW_CELLS 16.0
#define SNOW_DETAIL_START 14.0
#define SNOW_DETAIL_END 22.0
#define SNOW_SUBDIV 5

#define SNOW_MAX_PRESS 0.22

ivec2 snowCell(vec2 worldXZ) { return ivec2(floor(worldXZ * SNOW_CELLS)); }
ivec2 snowTexel(ivec2 cell)  { return cell & (SNOW_RES - 1); }

#ifdef SNOW_IMAGES
layout(rgba16f) uniform image2D snowDeformImg;
#include "/lib/contact.glsl"

void stampSnowLevel(vec3 worldPos) {
    vec2 d = abs(worldPos.xz - cameraPosition.xz);
    if (max(d.x, d.y) > 30.0) return;
    imageStore(waterLevelImg, contactTexel(snowCell(worldPos.xz), CONTACT_SNOW), vec4(worldPos.y, float(frameCounter), 0.0, 0.0));
}
bool snowLevelAt(ivec2 cell, out float level) {
    vec2 s = imageLoad(waterLevelImg, contactTexel(cell, CONTACT_SNOW)).xy;
    int age = frameCounter - int(s.y);
    if (age < 0) age += 720720;
    level = s.x;
    return age <= 4;
}

float snowPress(float y, float level) {
    return y < level - 0.6 ? 0.0 : saturate((level + 0.12 - y) / 0.25);
}
#endif

#ifndef SNOW_IMAGES
uniform sampler2D snowDeformSampler;
vec4 snowDeformTexel(ivec2 cell) { return texelFetch(snowDeformSampler, snowTexel(cell), 0); }
#else
vec4 snowDeformTexel(ivec2 cell) { return imageLoad(snowDeformImg, snowTexel(cell)); }
#endif

vec3 snowDeform(vec3 worldPos) {
    vec2 rel = abs(worldPos.xz - cameraPosition.xz);
    if (max(rel.x, rel.y) > 30.0) return vec3(0.0);
    vec2 p = worldPos.xz * SNOW_CELLS - 0.5;
    ivec2 i = ivec2(floor(p));
    vec2 f = p - vec2(i);
    vec3 acc = vec3(0.0);
    for (int k = 0; k < 4; k++) {
        ivec2 o = ivec2(k & 1, k >> 1);
        vec4 v = snowDeformTexel(i + o);
        float match = 1.0 - smoothstep(0.35, 0.6, abs(worldPos.y - (v.g + cameraPosition.y)));
        vec2 w = mix(1.0 - f, f, vec2(o));
        acc += v.rba * match * (w.x * w.y);
    }
    return acc;
}

vec4 snowDeformSmooth(vec3 worldPos, out vec2 rimGrad, out float packedSnow) {
    rimGrad = vec2(0.0);
    packedSnow = 0.0;
    vec2 rel = abs(worldPos.xz - cameraPosition.xz);
    if (max(rel.x, rel.y) > 30.0) return vec4(0.0);
    vec2 p = worldPos.xz * SNOW_CELLS - 0.5;
    ivec2 i = ivec2(floor(p));
    vec2 t = p - vec2(i);
    vec2 it = 1.0 - t, t2 = t * t, t3 = t2 * t;
    vec2 w[4]  = vec2[4](it * it * it / 6.0, (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0,
                         (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0, t3 / 6.0);
    vec2 dw[4] = vec2[4](-0.5 * it * it, 1.5 * t2 - 2.0 * t, -1.5 * t2 + t + 0.5, 0.5 * t2);
    vec4 acc = vec4(0.0);
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            vec4 v = snowDeformTexel(i + ivec2(x - 1, y - 1));
            float match = 1.0 - smoothstep(0.35, 0.6, abs(worldPos.y - (v.g + cameraPosition.y)));
            vec3 m = v.rba * match;
            float ww = w[x].x * w[y].y;
            vec2 dd = vec2(dw[x].x * w[y].y, w[x].x * dw[y].y) * SNOW_CELLS;
            acc += vec4(m.x * ww, m.y * ww, m.x * dd);
            rimGrad += m.y * dd;
            packedSnow += m.z * ww;
        }
    }
    return acc;
}

vec2 snowWind() { return vec2(0.83, 0.56); }

float snowRelief(vec2 p) {
    vec2 w = snowWind();
    vec2 q = vec2(dot(p, w), dot(p, vec2(-w.y, w.x)));
    float drift = valueNoise(q * vec2(0.16, 0.42) + 3.1);
    float mound = valueNoise(p * 0.55 + 7.3);
    float lump = valueNoise(p * 1.9 + 1.7);
    return (drift - 0.5) * 0.11 + (mound - 0.5) * 0.06 + (lump - 0.5) * 0.025 + 0.035;
}

float snowSurface(vec3 worldPos, float maxPress, out vec3 deform) {
    deform = snowDeform(worldPos);
    float relief = snowRelief(worldPos.xz) * (1.0 - deform.x);
    return relief - deform.x * maxPress + deform.y * 0.05;
}

float snowDetailFade(vec3 playerPos) {
    return 1.0 - smoothstep(SNOW_DETAIL_START, SNOW_DETAIL_END, length(playerPos.xz));
}

float snowMaxPress(float topY) {
    float layer = fract(topY);
    float thick = layer < 0.01 ? 1.0 : layer;
    return min(SNOW_MAX_PRESS, max(thick - 0.02, 0.02));
}
