#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif
VARY vec2 texcoord;

#ifdef VSH
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
#endif

#ifdef FSH
uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;

layout(location = 0) out vec4 out0;
layout(location = 1) out vec4 out1;

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;
    #ifdef USE_VOLUMETRIC_LIGHT

    vec2 view = vec2(viewWidth, viewHeight);
    vec2 halfRes = ceil(view * 0.5);
    float dc = linearizeDepth(texture(depthtex0, texcoord).r);
    vec2 hp = texcoord * halfRes - 0.5;
    vec3 vl = vec3(0.0);
    float ws = 0.0;
    for (int x = -1; x <= 2; x++) {
        for (int y = -1; y <= 2; y++) {
            vec2 tap = floor(hp) + vec2(float(x), float(y));
            vec2 d = hp - tap;
            if (any(lessThan(tap, vec2(0.0))) || any(greaterThanEqual(tap, halfRes))) continue;
            vec2 tapUV = (tap + 0.5) / halfRes;
            float ds = linearizeDepth(texelFetch(depthtex0, min(ivec2(tapUV * view), ivec2(view) - 1), 0).r);
            float w = exp(-dot(d, d) * 0.8) / (1.0 + abs(ds - dc) * 4.0 / max(dc, 1.0));
            vl += texelFetch(colortex4, ivec2(tap), 0).rgb * w;
            ws += w;
        }
    }
    color += vl / max(ws, 1e-4);
    #endif
    color = sanitize(color);
    out0 = vec4(color, 1.0);

    out1 = vec4(color, log2(max(luminance(color), 1e-6)));
}
#endif
