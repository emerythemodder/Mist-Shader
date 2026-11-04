#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/clouds.glsl"

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

VARY vec2 texcoord;
flat VARY vec3 directLight;
flat VARY vec3 ambientLight;
flat VARY float cloudShade;

#ifdef VSH
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
    getLightColors(directLight, ambientLight);

    cloudShade = 1.0;
    #ifdef USE_CLOUD_SHADOWS
    cloudShade = cloudShadow(cameraPosition);
    #endif
}
#endif

#ifdef FSH
uniform sampler2D depthtex0;
uniform sampler3D sunVisSampler;
layout(location = 0) out vec4 out0;

vec3 sunInAir(vec3 p) {
    vec3 vp = p + cameraPosition - vec3(ivec3(floor(cameraPosition)) - ivec3(64, 32, 64));
    vec3 c = vp * 0.5 - 0.5;
    if (any(lessThan(c, vec3(0.0))) || any(greaterThan(c, vec3(63.0, 31.0, 63.0)))) return vec3(1.0);
    ivec3 i = ivec3(floor(c));
    vec3 f = c - vec3(i);
    vec3 acc = vec3(0.0);
    for (int k = 0; k < 8; k++) {
        ivec3 o = ivec3(k & 1, (k >> 1) & 1, k >> 2);
        vec3 w = mix(1.0 - f, f, vec3(o));

        acc += texelFetch(sunVisSampler, min(i + o, ivec3(63, 31, 63)), 0).rgb * (w.x * w.y * w.z);
    }
    return acc;
}

void main() {
#ifdef USE_VOLUMETRIC_LIGHT
    vec2 view = vec2(viewWidth, viewHeight);
    vec2 halfRes = ceil(view * 0.5);
    if (gl_FragCoord.x > halfRes.x || gl_FragCoord.y > halfRes.y) { out0 = vec4(0.0); return; }
    vec2 uv = gl_FragCoord.xy / halfRes;
    float d0 = texelFetch(depthtex0, min(ivec2(uv * view), ivec2(view) - 1), 0).r;
    vec3 pp = viewToPlayer(screenToView(vec3(uv, d0)));
    float dist = length(pp);
    vec3 dir = pp / dist;
    float maxD = min(dist, 96.0);
    float stepL = maxD / float(VL_STEPS);
    float dither = temporalNoise(gl_FragCoord.xy);
    bool underwater = isEyeInWater == 1;

    vec3 acc = vec3(0.0);
    for (int i = 0; i < VL_STEPS; i++) {
        float t = stepL * (float(i) + dither);
        vec3 p = dir * t;
        vec3 vis = sunInAir(p);
        if (underwater) {
            acc += vis * exp(-WATER_ABSORB * t);
        } else {
            float h = p.y + cameraPosition.y;
            acc += vis * exp(-max(h - 63.0, 0.0) / 35.0);
        }
    }
    acc *= stepL;

    vec3 L = getLightDir();
    float mu = dot(dir, L);
    vec3 vl;
    if (underwater) {
        float phase = mix(1.0, henyeyGreenstein(mu, 0.6), 0.6);
        vl = directLight * vec3(0.25, 0.75, 0.8) * phase * acc * 0.035 * VL_DENSITY;
    } else {
        float lowSun = saturate(1.0 - abs(getSunDir().y) * 4.0);
        float phase = mix(1.0, henyeyGreenstein(mu, 0.72), 0.7);

        float coef = 0.0003 * sqrt(VL_DENSITY) * (1.0 + rainStrength * 6.0 + lowSun * 2.0);
        vl = directLight * phase * acc * coef;
    }
    vl *= cloudShade;
    out0 = vec4(sanitize(vl), 1.0);
#else
    out0 = vec4(0.0);
#endif
}
#endif
