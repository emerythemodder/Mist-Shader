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
uniform sampler2D colortex8;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

layout(location = 0) out vec4 out0;
layout(location = 1) out vec4 out1;

vec3 compress(vec3 c)   { return c / (1.0 + max(c.r, max(c.g, c.b))); }
vec3 decompress(vec3 c) { return c / max(1.0 - max(c.r, max(c.g, c.b)), 1e-4); }

vec3 toYCoCg(vec3 c) {
    return vec3(dot(c, vec3(0.25, 0.5, 0.25)), dot(c, vec3(0.5, 0.0, -0.5)), dot(c, vec3(-0.25, 0.5, -0.25)));
}
vec3 fromYCoCg(vec3 c) {
    return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);
}

vec3 sampleHistory(vec2 uv) {
    vec2 size = vec2(viewWidth, viewHeight);
    vec2 pos = uv * size;
    vec2 center = floor(pos - 0.5) + 0.5;
    vec2 f = pos - center;
    vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    vec2 w3 = f * f * (-0.5 + 0.5 * f);
    vec2 w12 = w1 + w2;
    vec2 p0 = (center - 1.0) / size;
    vec2 p3 = (center + 2.0) / size;
    vec2 p12 = (center + w2 / w12) / size;
    vec3 c = vec3(0.0);
    c += texture(colortex8, vec2(p12.x, p0.y)).rgb  * (w12.x * w0.y);
    c += texture(colortex8, vec2(p0.x,  p12.y)).rgb * (w0.x  * w12.y);
    c += texture(colortex8, vec2(p12.x, p12.y)).rgb * (w12.x * w12.y);
    c += texture(colortex8, vec2(p3.x,  p12.y)).rgb * (w3.x  * w12.y);
    c += texture(colortex8, vec2(p12.x, p3.y)).rgb  * (w12.x * w3.y);
    float wsum = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
    return max(c / wsum, 0.0);
}

vec3 clipToBox(vec3 hist, vec3 center, vec3 lo, vec3 hi) {
    vec3 ext = max((hi - lo) * 0.5, vec3(1e-5));
    vec3 d = hist - center;
    vec3 unit = abs(d / ext);
    float m = max(unit.x, max(unit.y, unit.z));
    return m > 1.0 ? center + d / m : hist;
}

void main() {
    vec2 uv = texcoord;
    vec3 current = texture(colortex0, uv).rgb;

#ifdef TAA
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);

    vec3 m1 = vec3(0.0), m2 = vec3(0.0);
    vec3 lo = vec3(1e9), hi = vec3(-1e9);
    float closest = 1.0;
    vec2 closestUV = uv;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 o = vec2(float(x), float(y)) * texel;
            vec3 c = toYCoCg(compress(texture(colortex0, uv + o).rgb));
            m1 += c; m2 += c * c;
            lo = min(lo, c); hi = max(hi, c);
            float d = texture(depthtex0, uv + o).r;
            if (d < closest) { closest = d; closestUV = uv + o; }
        }
    }
    vec3 mean = m1 / 9.0;
    vec3 sigma = sqrt(max(m2 / 9.0 - mean * mean, 0.0));
    vec3 boxLo = max(lo, mean - sigma * 1.25);
    vec3 boxHi = min(hi, mean + sigma * 1.25);

    vec2 prevUV = uv;
    if (closest >= 0.56) {
        vec3 vpos = screenToView(vec3(closestUV, closest));
        mat4 prevProj = gbufferPreviousProjection;
        #ifdef VOXY
        if (closest >= 1.0) {
            float lodDepth = texture(vxDepthTexOpaque, closestUV).r;
            if (lodDepth < 1.0) { vpos = lodScreenToView(vec3(closestUV, lodDepth)); prevProj = vxProjPrev; }
        }
        #endif
        #ifdef DISTANT_HORIZONS
        if (closest >= 1.0) {
            float dhDepth = texture(dhDepthTex0, closestUV).r;
            if (dhDepth < 1.0) { vpos = dhScreenToView(vec3(closestUV, dhDepth)); prevProj = dhPreviousProjection; }
        }
        #endif
        vec3 pp = viewToPlayer(vpos) + cameraPosition - previousCameraPosition;
        vec4 pc = prevProj * (gbufferPreviousModelView * vec4(pp, 1.0));
        pc.xy *= zoomScale();
        prevUV = uv + (pc.xy / pc.w * 0.5 + 0.5 - closestUV);
    }

    vec3 cur = toYCoCg(compress(current));
    vec3 result = cur;
    vec4 histRaw = texture(colortex8, prevUV);
    if (!outsideScreen(prevUV) && !(any(isnan(histRaw)) || any(isinf(histRaw)))) {
        vec3 hist = toYCoCg(compress(sampleHistory(prevUV)));
        hist = clipToBox(hist, clamp(mean, boxLo, boxHi), boxLo, boxHi);

        float motion = length((prevUV - uv) * vec2(viewWidth, viewHeight));
        float alpha = mix(0.08, 0.25, saturate(motion / 16.0));

        if (int(texture(colortex2, uv).r * 255.0 + 0.5) == 254) alpha = max(alpha, 0.5);
        result = mix(hist, cur, alpha);
    }
    vec3 outColor = sanitize(decompress(clamp(fromYCoCg(result), 0.0, 0.995)));
#else
    vec3 outColor = current;
#endif
    out0 = vec4(outColor, 1.0);
    out1 = vec4(outColor, 1.0);
}
#endif
