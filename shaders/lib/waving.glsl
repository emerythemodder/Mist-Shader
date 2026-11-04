#ifdef PLANT_BEND_READ

uniform sampler2D bendSampler;
#define BEND_RES 256
#define BEND_CELLS 4.0
vec4 bendTexel(ivec2 cell, int k) {
    ivec2 t = cell & (BEND_RES - 1);
    return texelFetch(bendSampler, ivec2(t.x * 2 + k, t.y), 0);
}

vec3 plantBend(vec3 worldPos, int id, vec3 midBlock, out float bendAmount) {
    bendAmount = 0.0;
    bool tall = id == 10006;
    bool leaves = id == 10002;
    if (!(id == 10003 || tall || leaves)) return vec3(0.0);
    vec3 center = worldPos + midBlock / 64.0;
    vec2 rel = abs(center.xz - cameraPosition.xz);
    if (max(rel.x, rel.y) > 30.0) return vec3(0.0);

    vec2 p = center.xz * BEND_CELLS - 0.5;
    ivec2 i = ivec2(floor(p));
    vec2 f = p - vec2(i);
    vec2 B = mix(mix(bendTexel(i, 0).xy, bendTexel(i + ivec2(1, 0), 0).xy, f.x),
                 mix(bendTexel(i + ivec2(0, 1), 0).xy, bendTexel(i + ivec2(1, 1), 0).xy, f.x), f.y);
    float contactY = bendTexel(ivec2(floor(center.xz * BEND_CELLS)), 1).x;

    float baseY = floor(center.y) - (tall ? 1.0 : 0.0);
    float plantH = tall ? 2.0 : 1.0;
    float gate = leaves ? step(baseY - 1.9, contactY) * step(contactY, baseY + 1.1)
                        : smoothstep(baseY - 1.0, baseY - 0.5, contactY) * (1.0 - smoothstep(baseY + plantH - 0.1, baseY + plantH + 0.4, contactY));
    B *= gate;
    float m = length(B);
    if (m < 1e-3) return vec3(0.0);
    vec2 dir = B / m;
    bendAmount = saturate(m);
    if (leaves) return vec3(dir.x, -0.3 * m, dir.y) * min(m, 1.0) * 0.14 * PLANT_BEND_STRENGTH;

    float s = clamp(worldPos.y - baseY, 0.0, plantH);
    float theta = min(m, 1.15) * (tall ? 1.05 : 1.3) * PLANT_BEND_STRENGTH;
    float k = max(theta / plantH, 1e-3);
    float side = (1.0 - cos(k * s)) / k;
    float up = sin(k * s) / k;
    return vec3(dir.x * side, up - s, dir.y * side);
}
#endif

vec3 getWaving(vec3 worldPos, int id, vec3 midBlock, float skyL) {
    vec3 bend = vec3(0.0);
    float held = 0.0;
    #ifdef PLANT_BEND_READ
    bend = plantBend(worldPos, id, midBlock, held);
    #endif
#ifdef WAVING_PLANTS
    if (id == 10018) {

        float tu = frameTimeCounter * WAVING_SPEED * 0.8;
        vec3 p = worldPos;
        float sx = sin(tu * 1.1 + p.x * 0.4 + p.z * 0.25) + 0.4 * sin(tu * 2.3 + p.z * 0.9);
        float sz = cos(tu * 0.9 + p.z * 0.35 + p.x * 0.2) + 0.4 * cos(tu * 1.9 + p.x * 0.8);
        return vec3(sx, 0.0, sz) * 0.05;
    }
    float strength;
    bool isTop = midBlock.y < 0.0;
    if (id == 10003)      strength = isTop ? 0.09 : 0.0;
    else if (id == 10006) strength = isTop ? 0.16 : 0.09;
    else if (id == 10002) strength = 0.035;
    else return bend;

    strength *= skyL * (1.0 + rainStrength * 1.2) * (1.0 - held * 0.85);
    float t = frameTimeCounter * WAVING_SPEED;
    vec3 p = worldPos;
    float gust = 0.6 + 0.4 * sin(t * 0.35 + p.x * 0.03 + p.z * 0.02);
    float w1 = sin(t * 1.6 + p.x * 0.5 + p.z * 0.35) + 0.5 * sin(t * 2.7 + p.z * 0.9 - p.x * 0.3);
    float w2 = cos(t * 1.3 + p.z * 0.45 + p.x * 0.2) + 0.5 * sin(t * 3.3 + p.x * 1.1);
    return bend + vec3(w1, id == 10002 ? w2 * 0.3 : 0.0, w2) * strength * gust;
#else
    return bend;
#endif
}
