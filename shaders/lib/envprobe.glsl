#ifndef ENVPROBE_GLSL
#define ENVPROBE_GLSL

#define ENV_RES 64
#define ENV_TEXELS 5456
const int ENV_OFFSET[5] = int[5](0, 4096, 5120, 5376, 5440);
const int ENV_SIZE[5] = int[5](64, 32, 16, 8, 4);

#ifndef ENV_ACCESS
#define ENV_ACCESS readonly
#endif

layout(std430, binding = 2) ENV_ACCESS buffer EnvProbe {
    vec4 envSH[9];
    uvec2 envTexels[ENV_TEXELS];
};

float octSign(float v) { return v >= 0.0 ? 1.0 : -1.0; }
vec2 octEncode(vec3 d) {
    d /= abs(d.x) + abs(d.y) + abs(d.z);
    vec2 p = d.y >= 0.0 ? d.xz : (1.0 - abs(d.zx)) * vec2(octSign(d.x), octSign(d.z));
    return p * 0.5 + 0.5;
}
vec3 octDecode(vec2 uv) {
    vec2 p = uv * 2.0 - 1.0;
    vec3 d = vec3(p.x, 1.0 - abs(p.x) - abs(p.y), p.y);
    if (d.y < 0.0) d.xz = (1.0 - abs(d.zx)) * vec2(octSign(d.x), octSign(d.z));
    return normalize(d);
}

vec3 envTexel(int level, ivec2 t) {
    int s = ENV_SIZE[level];
    t = clamp(t, ivec2(0), ivec2(s - 1));
    uvec2 v = envTexels[ENV_OFFSET[level] + t.y * s + t.x];
    return vec3(unpackHalf2x16(v.x), unpackHalf2x16(v.y).x);
}
#ifdef ENV_WRITE
void envStore(int level, ivec2 t, vec3 c) {
    int s = ENV_SIZE[level];
    c = clamp(c, vec3(0.0), vec3(60000.0));
    envTexels[ENV_OFFSET[level] + t.y * s + t.x] = uvec2(packHalf2x16(c.rg), packHalf2x16(vec2(c.b, 1.0)));
}
#endif
vec3 envLevel(int level, vec3 dir) {
    float s = float(ENV_SIZE[level]);
    vec2 p = octEncode(dir) * s - 0.5;
    ivec2 i = ivec2(floor(p));
    vec2 f = p - vec2(i);
    return mix(mix(envTexel(level, i), envTexel(level, i + ivec2(1, 0)), f.x),
               mix(envTexel(level, i + ivec2(0, 1)), envTexel(level, i + ivec2(1, 1)), f.x), f.y);
}

vec3 envSpecular(vec3 R, float pr) {
    float l = clamp(pr, 0.0, 1.0) * 4.0;
    int l0 = int(floor(l));
    int l1 = min(l0 + 1, 4);
    return mix(envLevel(l0, R), envLevel(l1, R), l - float(l0));
}

vec3 envDiffuse(vec3 n) {

    const float a0 = 1.0, a1 = 2.0 / 3.0, a2 = 0.25;
    vec3 e = envSH[0].rgb * 0.282095 * a0
           + (envSH[1].rgb * n.y + envSH[2].rgb * n.z + envSH[3].rgb * n.x) * 0.488603 * a1
           + (envSH[4].rgb * n.x * n.y + envSH[5].rgb * n.y * n.z + envSH[7].rgb * n.x * n.z) * 1.092548 * a2
           + envSH[6].rgb * (0.315392 * (3.0 * n.z * n.z - 1.0)) * a2
           + envSH[8].rgb * (0.546274 * (n.x * n.x - n.y * n.y)) * a2;
    return max(e, vec3(0.0));
}

vec2 envBRDF(float NdotV, float pr) {
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
    vec4 r = pr * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NdotV)) * r.x + r.y;
    return vec2(-1.04, 1.04) * a004 + r.zw;
}
#endif
