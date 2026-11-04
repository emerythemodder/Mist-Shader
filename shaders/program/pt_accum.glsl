#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/rt_half_common.glsl"

#define PT_FRAMES 32.0

#ifdef VSH
void main() { gl_Position = ftransform(); }
#endif

#ifdef FSH
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D depthtex1;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

layout(location = 0) out vec4 out11;
layout(location = 1) out vec4 out12;

void main() {
    out11 = vec4(0.0);
    out12 = vec4(0.0);
    vec2 view = vec2(viewWidth, viewHeight);
    ivec2 halfRes = ivec2(ceil(view * 0.5));
    ivec2 h = ivec2(gl_FragCoord.xy);
    if (h.x >= halfRes.x || h.y >= halfRes.y) return;
    ivec2 p = rtHalfSource(h);
    float depth = texelFetch(depthtex1, p, 0).r;
    if (depth >= 1.0 || depth < 0.56) return;
    int mat = int(texelFetch(colortex2, p, 0).r * 255.0 + 0.5);
    if (mat == 254 || mat == 250) return;

    vec3 normal = decodeNormal(texelFetch(colortex1, p, 0).xy);
    vec3 viewPos = screenToView(vec3((vec2(p) + 0.5) / view, depth));
    vec3 raw = texelFetch(colortex10, h, 0).rgb;
    bool sampled = raw.r >= 0.0;

    vec3 prevView = (gbufferPreviousModelView * vec4(viewToPlayer(viewPos) + cameraPosition - previousCameraPosition, 1.0)).xyz;
    vec4 prevClip = gbufferPreviousProjection * vec4(prevView, 1.0);
    prevClip.xy *= zoomScale();
    vec4 hist = vec4(0.0);
    float wsum = 0.0;
    if (prevClip.w > 0.0) {
        vec2 puv = prevClip.xy / prevClip.w * 0.5 + 0.5;
        float expectZ = -prevView.z;
        vec2 hp = puv * view * 0.5 - 0.5;
        ivec2 b = ivec2(floor(hp));
        vec2 f = hp - vec2(b);
        for (int i = 0; i < 4; i++) {
            ivec2 o = ivec2(i & 1, i >> 1);
            ivec2 q = b + o;
            if (any(lessThan(q, ivec2(0))) || any(greaterThanEqual(q, halfRes))) continue;
            vec4 g = texelFetch(colortex12, q, 0);
            if (g.x <= 0.0) continue;
            float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
            w *= step(abs(g.x - expectZ), 0.04 * expectZ + 0.08) * step(0.85, dot(decodeNormal(g.yz), normal));
            hist += texelFetch(colortex11, q, 0) * w;
            wsum += w;
        }
    }
    vec3 acc = raw;
    float frames = 0.0;
    if (wsum > 0.05) {
        hist /= wsum;
        frames = hist.a;
        acc = hist.rgb;

        float lh = luminance(acc), lr = luminance(raw);
        if (sampled && frames > 3.0 && lr > lh * 5.0 + 0.2) raw *= (lh * 5.0 + 0.2) / lr;
    }
    if (sampled) {
        frames = min(frames + 1.0, PT_FRAMES);
        acc = mix(acc, raw, 1.0 / frames);
    } else if (frames <= 0.0) {
        acc = vec3(0.0);
    }
    if (any(isnan(acc)) || any(isinf(acc))) { acc = vec3(0.0); frames = 0.0; }
    out11 = vec4(acc, frames);
    out12 = vec4(-viewPos.z, encodeNormal(normal), 1.0);
}
#endif
