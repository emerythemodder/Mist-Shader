const float PI  = 3.14159265359;
const float TAU = 6.28318530718;

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2  saturate(vec2 x)  { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, 0.0, 1.0); }

float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 toLinear(vec3 c) { return pow(max(c, 0.0), vec3(2.2)); }
vec3 toGamma(vec3 c)  { return pow(max(c, 0.0), vec3(1.0 / 2.2)); }

float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }

float temporalNoise(vec2 fragCoord) {
    #ifdef TAA
    return ign(fragCoord + 5.588238 * float(frameCounter % 64));
    #else
    return ign(fragCoord);
    #endif
}

vec2 taaOffset() {
    #ifdef TAA
    const vec2 halton[8] = vec2[8](vec2(0.5, 0.3333333), vec2(0.25, 0.6666667), vec2(0.75, 0.1111111), vec2(0.125, 0.4444444),
                                   vec2(0.625, 0.7777778), vec2(0.375, 0.2222222), vec2(0.875, 0.5555556), vec2(0.0625, 0.8888889));
    return (halton[frameCounter % 8] - 0.5) * 2.0 / vec2(viewWidth, viewHeight);
    #else
    return vec2(0.0);
    #endif
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}
float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}
float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p, int octaves) {
    float s = 0.0, a = 0.5, n = 0.0;
    for (int i = 0; i < octaves; i++) {
        s += valueNoise(p) * a;
        n += a;
        p = mat2(1.6, 1.2, -1.2, 1.6) * p + 3.1;
        a *= 0.5;
    }
    return s / n;
}

vec2 octWrap(vec2 v) {
    return (1.0 - abs(v.yx)) * vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}
vec2 encodeNormal(vec3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    n.xy = n.z >= 0.0 ? n.xy : octWrap(n.xy);
    return n.xy * 0.5 + 0.5;
}
vec3 decodeNormal(vec2 f) {
    f = f * 2.0 - 1.0;
    vec3 n = vec3(f, 1.0 - abs(f.x) - abs(f.y));
    float t = saturate(-n.z);
    n.x += n.x >= 0.0 ? -t : t;
    n.y += n.y >= 0.0 ? -t : t;
    return normalize(n);
}

vec3 projectAndDivide(mat4 m, vec3 p) {
    vec4 h = m * vec4(p, 1.0);
    return h.xyz / h.w;
}

uniform float zoomAmt;
float zoomScale() {
    #ifdef USE_ZOOM
    return mix(1.0, ZOOM_FACTOR, zoomAmt);
    #else
    return 1.0;
    #endif
}
vec3 screenToView(vec3 s) {
    vec3 n = s * 2.0 - 1.0;
    n.xy /= zoomScale();
    return projectAndDivide(gbufferProjectionInverse, n);
}
vec3 viewToScreen(vec3 v) {
    vec3 n = projectAndDivide(gbufferProjection, v);
    n.xy *= zoomScale();
    return n * 0.5 + 0.5;
}
#ifdef DISTANT_HORIZONS

uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjectionInverse;
uniform mat4 dhPreviousProjection;
vec3 dhScreenToView(vec3 s) { vec3 n = s * 2.0 - 1.0; n.xy /= zoomScale(); return projectAndDivide(dhProjectionInverse, n); }
#endif
#ifdef VOXY

uniform sampler2D vxDepthTexOpaque;
uniform mat4 vxProjInv;
uniform mat4 vxProjPrev;
uniform mat4 vxProj;
vec3 lodScreenToView(vec3 s) { return projectAndDivide(vxProjInv, s * 2.0 - 1.0); }
#endif
vec3 viewToPlayer(vec3 v) { return mat3(gbufferModelViewInverse) * v + gbufferModelViewInverse[3].xyz; }

float linearizeDepth(float d) {
    float z = d * 2.0 - 1.0;
    return 2.0 * near * far / (far + near - z * (far - near));
}

vec2 vogelDisk(int i, int n, float phi) {
    float r = sqrt((float(i) + 0.5) / float(n));
    float th = float(i) * 2.39996323 + phi;
    return r * vec2(cos(th), sin(th));
}

float henyeyGreenstein(float mu, float g) {
    float g2 = g * g;
    return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5);
}

vec2 lightmapRemap(vec2 lm) { return clamp(lm * 33.05 / 32.0 - 1.05 / 32.0, 0.0, 1.0); }

vec3 sanitize(vec3 c) {
    if (any(isnan(c)) || any(isinf(c))) return vec3(0.0);
    return clamp(c, 0.0, 6.0e4);
}

float curvatureDrop(vec2 xz) {
    #ifdef USE_CURVED_WORLD
    float radius = float(CURVATURE_RADIUS);
    #ifdef DISTANT_HORIZONS

    radius = max(radius, 8000.0);
    #endif
    return dot(xz, xz) / (2.0 * radius);
    #else
    return 0.0;
    #endif
}
vec3 uncurveWorld(vec3 playerPos) { playerPos.y += curvatureDrop(playerPos.xz); return playerPos; }

vec4 taaClipPosition(vec3 playerPos) {
    playerPos.y -= curvatureDrop(playerPos.xz);
    vec4 clip = gbufferProjection * (gbufferModelView * vec4(playerPos, 1.0));
    clip.xy *= zoomScale();
    clip.xy += taaOffset() * clip.w;
    return clip;
}

bool outsideScreen(vec2 uv) { return uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0; }
