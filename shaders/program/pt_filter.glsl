#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

#ifdef VSH
void main() { gl_Position = ftransform(); }
#endif

#ifdef FSH
uniform sampler2D PT_FILTER_IN;
uniform sampler2D colortex12;

layout(location = 0) out vec4 outGi;

void main() {
    vec2 view = vec2(viewWidth, viewHeight);
    ivec2 halfRes = ivec2(ceil(view * 0.5));
    ivec2 h = ivec2(gl_FragCoord.xy);
    outGi = vec4(0.0);
    if (h.x >= halfRes.x || h.y >= halfRes.y) return;
    vec4 c = texelFetch(PT_FILTER_IN, h, 0);
    vec4 g0 = texelFetch(colortex12, h, 0);
    outGi = c;
    if (g0.x <= 0.0) return;
    bool empty = c.a <= 0.0;

    vec3 n0 = decodeNormal(g0.yz);
    float l0 = luminance(c.rgb);
    float sigmaL = empty ? 1e6 : 0.25 + 6.0 / c.a;
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            ivec2 q = h + ivec2(x, y) * PT_FILTER_STEP;
            if (any(lessThan(q, ivec2(0))) || any(greaterThanEqual(q, halfRes))) continue;
            vec4 s = texelFetch(PT_FILTER_IN, q, 0);
            vec4 g = texelFetch(colortex12, q, 0);
            if (s.a <= 0.0 || g.x <= 0.0) continue;
            float k = (x == 0 ? 0.5 : 0.25) * (y == 0 ? 0.5 : 0.25);
            float wz = exp(-abs(g.x - g0.x) / (0.015 * g0.x * float(PT_FILTER_STEP) + 0.03));
            float wn = pow(saturate(dot(decodeNormal(g.yz), n0)), 32.0);
            float wl = exp(-abs(luminance(s.rgb) - l0) / (sigmaL * (l0 + 0.02)));
            float w = k * wz * wn * wl;
            sum += s.rgb * w;
            wsum += w;
        }
    }
    if (wsum > 1e-5) outGi = vec4(sum / wsum, max(c.a, empty ? 1.0 : 0.0));
}
#endif
