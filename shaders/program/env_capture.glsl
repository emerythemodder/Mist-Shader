#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"

#ifdef USE_IBL
#define ENV_ACCESS
#define ENV_WRITE
#include "/lib/envprobe.glsl"
#if ENV_PASS == 0
#include "/lib/water.glsl"
#include "/lib/shadows.glsl"
#include "/lib/clouds.glsl"
#ifdef USE_RT_LIGHTS
#define PT_TRACE
#define RT_SHADING
#include "/lib/rt_lights.glsl"
#endif
#endif
#if ENV_PASS == 1
shared vec3 shAcc[64][9];
#endif
#endif

void main() {
#ifdef USE_IBL
#if ENV_PASS == 0
    ivec2 t = ivec2(gl_GlobalInvocationID.xy);

    if (((t.x & 1) | ((t.y & 1) << 1)) != (frameCounter & 3) && frameCounter > 4) return;
    vec3 dir = octDecode((vec2(t) + 0.5) / float(ENV_RES));
    vec3 direct, ambient;
    getLightColors(direct, ambient);
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
    vec3 c = vec3(-1.0);
    #ifdef USE_RT_LIGHTS

    rtIgnoreEntities = true;
    vec4 hit = rtReflect(vec3(0.0), dir, direct, PI * ambient, smoothstep(0.02, 0.35, eyeSky));
    rtIgnoreEntities = false;
    if (hit.a > 0.0) c = hit.rgb;
    #endif
    if (c.x < 0.0) {
        if (dir.y > -0.03) {

            vec3 sky = getSky(dir, false);
            #ifdef USE_VOLUMETRIC_CLOUDS
            vec4 cl = renderClouds(dir, direct, ambient, 0.5);
            sky = sky * saturate(cl.a) + max(cl.rgb, 0.0);
            #endif

            c = sky * mix(0.04, 1.0, eyeSky * eyeSky);
        } else {

            c = 0.2 * (direct * saturate(getLightDir().y) + PI * ambient * 0.6) * mix(0.1, 1.0, eyeSky);
        }
    }
    envStore(0, t, c);
#elif ENV_PASS == 1
    int gid = int(gl_GlobalInvocationID.x);
    if (gl_WorkGroupID.x == 22u) {

        int li = int(gl_LocalInvocationID.x);
        vec3 acc[9];
        for (int k = 0; k < 9; k++) acc[k] = vec3(0.0);
        float wsum = 0.0;
        for (int i = li; i < ENV_RES * ENV_RES; i += 64) {
            ivec2 tt = ivec2(i % ENV_RES, i / ENV_RES);
            vec2 p = (vec2(tt) + 0.5) / float(ENV_RES) * 2.0 - 1.0;

            vec3 v = vec3(p.x, 1.0 - abs(p.x) - abs(p.y), p.y);
            if (v.y < 0.0) v.xz = (1.0 - abs(v.zx)) * vec2(octSign(v.x), octSign(v.z));
            float dw = pow(2.0 / float(ENV_RES), 2.0) / pow(length(v), 3.0);
            vec3 n = normalize(v);
            vec3 L = envTexel(0, tt) * dw;
            acc[0] += L * 0.282095;
            acc[1] += L * 0.488603 * n.y; acc[2] += L * 0.488603 * n.z; acc[3] += L * 0.488603 * n.x;
            acc[4] += L * 1.092548 * n.x * n.y; acc[5] += L * 1.092548 * n.y * n.z;
            acc[6] += L * 0.315392 * (3.0 * n.z * n.z - 1.0);
            acc[7] += L * 1.092548 * n.x * n.z; acc[8] += L * 0.546274 * (n.x * n.x - n.y * n.y);
            wsum += dw;
        }
        for (int k = 0; k < 9; k++) shAcc[li][k] = acc[k];
        barrier();
        if (li == 0) {
            for (int k = 0; k < 9; k++) {
                vec3 s = vec3(0.0);
                for (int j = 0; j < 64; j++) s += shAcc[j][k];
                envSH[k] = vec4(s, 0.0);
            }
        }
        return;
    }

    int level = gid < 1024 ? 1 : (gid < 1280 ? 2 : (gid < 1344 ? 3 : 4));
    if (gid >= 1360) return;
    int local = gid - (ENV_OFFSET[level] - 4096);
    int s = ENV_SIZE[level];
    ivec2 tt = ivec2(local % s, local / s);
    vec3 N = octDecode((vec2(tt) + 0.5) / float(s));
    float pr = float(level) / 4.0;
    float a = max(pr * pr, 0.002);
    vec3 t1 = normalize(cross(N, abs(N.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 t2 = cross(N, t1);

    int count = level == 1 ? 48 : (level == 2 ? 96 : 160);
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < count; i++) {
        vec2 xi = vec2((float(i) + 0.5) / float(count), fract(float(i) * 0.618034 + 0.31));
        float cosT = sqrt((1.0 - xi.x) / (1.0 + (a * a - 1.0) * xi.x));
        float sinT = sqrt(max(1.0 - cosT * cosT, 0.0));
        float phi = TAU * xi.y;
        vec3 H = t1 * (sinT * cos(phi)) + t2 * (sinT * sin(phi)) + N * cosT;
        vec3 L = reflect(-N, H);
        float ndl = dot(N, L);
        if (ndl <= 0.0) continue;
        sum += envLevel(0, L) * ndl;
        wsum += ndl;
    }
    envStore(level, tt, sum / max(wsum, 1e-4));
#endif
#endif
}
