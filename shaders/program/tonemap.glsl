#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"

const bool colortex0MipmapEnabled = true;
const bool colortex4MipmapEnabled = true;

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif
VARY vec2 texcoord;
#ifndef AUTO_EXPOSURE
flat VARY float hourAdapt;
#endif
#ifdef LENS_FLARE

flat VARY vec3 flareLight;
flat VARY vec3 flareSun;
#endif

#ifdef VSH
#ifdef LENS_FLARE
uniform sampler2D colortex0;
uniform sampler2D depthtex0;
#endif
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
    vec3 dl, al;
    getLightColors(dl, al);
    #ifndef AUTO_EXPOSURE

    float lightNow = luminance(dl) * 0.5 + luminance(al) / AMBIENT_STRENGTH;
    hourAdapt = clamp(pow(2.6 / max(lightNow, 1e-5), 0.55), 1.0, 7.0);
    #endif
    #ifdef LENS_FLARE
    flareLight = dl;
    flareSun = vec3(0.0);
    vec3 sunDirW = mat3(gbufferModelViewInverse) * normalize(sunPosition);
    float daylight = smoothstep(0.0, 0.12, sunDirW.y) * (1.0 - rainStrength);
    vec4 sc = gbufferProjection * vec4(sunPosition, 1.0);
    sc.xy *= zoomScale();
    if (daylight > 0.0 && sc.w > 0.0) {
        vec2 s = sc.xy / sc.w * 0.5 + 0.5;
        if (!any(lessThan(s, vec2(-0.1))) && !any(greaterThan(s, vec2(1.1)))) {
            float vis = 0.0;
            for (int i = 0; i < 9; i++) {
                vec2 p = s + vec2(float(i % 3) - 1.0, float(i / 3) - 1.0) * 0.006;
                bool skyHere = !outsideScreen(p) && textureLod(depthtex0, p, 0.0).r >= 1.0;
                #ifdef DISTANT_HORIZONS
                skyHere = skyHere && textureLod(dhDepthTex0, p, 0.0).r >= 1.0;
                #endif
                #ifdef VOXY
                skyHere = skyHere && textureLod(vxDepthTexOpaque, p, 0.0).r >= 1.0;
                #endif
                if (skyHere) vis += luminance(textureLod(colortex0, p, 0.0).rgb) > 0.5 * luminance(dl) ? 1.0 : 0.3;
            }
            flareSun = vec3(s, vis / 9.0 * daylight);
        }
    }
    #endif
}
#endif

#ifdef FSH
uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;
uniform float centerDepthSmooth;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

#ifdef HEAT_HAZE

vec2 heatHaze(vec2 uv) {
    #if defined WORLD_NETHER
    float heat = 1.0;
    #elif defined WORLD_OVERWORLD
    vec3 sunW = mat3(gbufferModelViewInverse) * normalize(sunPosition);
    float heat = saturate((biomeHeat - 1.2) * 2.0) * (1.0 - saturate(biomeHumidity * 3.0))
               * smoothstep(0.1, 0.4, sunW.y) * (1.0 - rainStrength);
    #else
    float heat = 0.0;
    #endif
    if (heat <= 0.0) return vec2(0.0);
    float d = texture(depthtex0, uv).r;
    if (d >= 1.0 || d < 0.56) return vec2(0.0);
    float dist = linearizeDepth(d);
    float far01 = smoothstep(12.0, 70.0, dist);
    vec2 q = uv * vec2(viewWidth / viewHeight, 1.0) * vec2(90.0, 45.0) + vec2(0.0, frameTimeCounter * 3.0);
    vec2 n = vec2(valueNoise(q), valueNoise(q + 17.3)) - 0.5;
    return n * 0.0016 * heat * far01;
}
#endif

#ifdef DEPTH_OF_FIELD

vec3 depthOfField(vec2 uv, vec3 sharp) {
    float d = texture(depthtex0, uv).r;
    if (d < 0.56) return sharp;
    float z = linearizeDepth(d), focus = linearizeDepth(centerDepthSmooth);
    float coc = abs(z - focus) / max(z, 1e-3) * DOF_STRENGTH;
    float lod = clamp(coc * 6.0, 0.0, 4.0);
    if (lod < 0.05) return sharp;
    vec2 px = exp2(lod) / vec2(viewWidth, viewHeight) * 0.5;
    vec3 blur = (textureLod(colortex0, uv + px * vec2( 1.0,  0.3), lod).rgb + textureLod(colortex0, uv + px * vec2(-0.3,  1.0), lod).rgb
               + textureLod(colortex0, uv + px * vec2(-1.0, -0.3), lod).rgb + textureLod(colortex0, uv + px * vec2( 0.3, -1.0), lod).rgb) * 0.25;
    return mix(sharp, blur, saturate(lod));
}
#endif

#ifdef MOTION_BLUR

vec3 motionBlur(vec2 uv, vec3 color) {
    float d = texture(depthtex0, uv).r;
    if (d < 0.56) return color;
    vec3 pp = viewToPlayer(screenToView(vec3(uv, d))) + cameraPosition - previousCameraPosition;
    vec4 pc = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(pp, 1.0));
    pc.xy *= zoomScale();
    vec2 vel = (uv - (pc.xy / pc.w * 0.5 + 0.5)) * MOTION_BLUR_STRENGTH;
    vel = clamp(vel, vec2(-0.05), vec2(0.05));
    if (dot(vel, vel) < 1e-7) return color;
    float jitter = temporalNoise(gl_FragCoord.xy);
    vec3 acc = color;
    for (int i = 1; i <= 6; i++) acc += texture(colortex0, uv - vel * ((float(i) - jitter) / 6.0)).rgb;
    return acc / 7.0;
}
#endif

layout(location = 0) out vec4 out0;
layout(location = 1) out vec4 out1;

#ifdef LENS_FLARE

float apertureShape(vec2 p, float r) {

    float a = atan(p.y, p.x);
    float k = cos(PI / 6.0) / cos(mod(a + PI / 6.0, PI / 3.0) - PI / 6.0);
    return length(p) / (r * mix(1.0, k, 0.7));
}
vec3 lensFlare(vec2 uv, vec3 sunLight) {

    vec2 s = flareSun.xy;
    float vis = flareSun.z;
    if (vis <= 0.001) return vec3(0.0);

    vec2 aspect = vec2(viewWidth / viewHeight, 1.0);
    vec2 toC = 0.5 - s;
    vec3 f = vec3(0.0);
    const float gp[5] = float[5](0.42, 0.78, 1.18, 1.52, 1.9);
    const float gs[5] = float[5](0.035, 0.055, 0.02, 0.085, 0.045);
    for (int i = 0; i < 5; i++) {
        vec2 c = s + toC * gp[i] * 2.0;
        float d = apertureShape((uv - c) * aspect, gs[i]);
        float body = 1.0 - smoothstep(0.75, 1.0, d);
        float rim = exp(-pow((d - 0.93) / 0.07, 2.0));
        vec3 coat = mix(vec3(0.55, 0.75, 1.0), vec3(1.0, 0.75, 0.45), fract(float(i) * 0.37 + 0.2));
        f += (body * 0.5 + rim) * coat * (0.006 / (1.0 + float(i)));
    }
    return f * sunLight * vis;
}
#endif

vec3 filmCurve(vec3 c) {
    float L = luminance(c);
    vec3 x = mix(vec3(L), c, 0.86);
    x = (clamp(log2(max(x, vec3(1e-10))), -12.0, 4.5) + 12.0) / 16.5;
    const float mid = (log2(0.18) + 12.0) / 16.5;
    x = (x - mid) * CONTRAST + mid;
    const float k = 8.0, x0 = 0.6;
    float lo = 1.0 / (1.0 + exp(k * x0)), hi = 1.0 / (1.0 + exp(-k * (1.0 - x0)));
    vec3 y = (1.0 / (1.0 + exp(-k * (x - x0))) - lo) / (hi - lo);
    y = mix(vec3(luminance(y)), y, 1.0 / 0.86);
    return saturate(y);
}

void main() {
    vec2 res = vec2(viewWidth, viewHeight);
    vec2 uv = texcoord;
    #ifdef HEAT_HAZE
    uv += heatHaze(uv);
    #endif
    vec3 color = texture(colortex0, uv).rgb;
    #ifdef DEPTH_OF_FIELD
    color = depthOfField(uv, color);
    #endif
    #ifdef MOTION_BLUR
    color = motionBlur(uv, color);
    #endif

    #ifdef CHROMATIC_ABERRATION

    {
        vec2 c = uv - 0.5;
        float r2 = dot(c * vec2(viewWidth / viewHeight, 1.0), c * vec2(viewWidth / viewHeight, 1.0));
        float k = 0.0028 * r2;
        color.r = (texture(colortex0, 0.5 + c * (1.0 + k)).r * 2.0 + texture(colortex0, 0.5 + c * (1.0 + k * 0.5)).r) / 3.0;
        color.b = (texture(colortex0, 0.5 + c * (1.0 - k)).b * 2.0 + texture(colortex0, 0.5 + c * (1.0 - k * 0.5)).b) / 3.0;
    }
    #endif

    #ifdef BLOOM

    vec3 bloom = vec3(0.0);
    float bw = 0.0;
    for (int i = 1; i <= 7; i++) {
        float lod = float(i);
        vec2 size = res / exp2(lod);
        vec2 p = uv * size - 0.5;
        vec2 f = fract(p), ip = floor(p);
        vec2 f2 = f * f, f3 = f2 * f;
        vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0, w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
        vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0, w3 = f3 / 6.0;
        vec2 g0 = w0 + w1, g1 = w2 + w3;
        vec2 h0 = (w1 / g0 - 1.0 + ip + 0.5) / size, h1 = (w3 / g1 + 1.0 + ip + 0.5) / size;
        vec3 lvl = (textureLod(colortex4, vec2(h0.x, h0.y), lod).rgb * g0.x + textureLod(colortex4, vec2(h1.x, h0.y), lod).rgb * g1.x) * g0.y
                 + (textureLod(colortex4, vec2(h0.x, h1.y), lod).rgb * g0.x + textureLod(colortex4, vec2(h1.x, h1.y), lod).rgb * g1.x) * g1.y;
        float w = exp(-0.35 * lod);
        bloom += lvl * w;
        bw += w;
    }
    bloom /= bw;
    float bs = BLOOM_STRENGTH * 0.5 * (1.0 + float(isEyeInWater == 1) * 2.0 + rainStrength);
    color = mix(color, bloom, saturate(bs));
    #endif

    #ifdef LENS_FLARE
    color += lensFlare(texcoord, flareLight);
    #endif

    #ifdef PURKINJE

    float lumP = luminance(color);
    float scotopic = 1.0 - smoothstep(0.0006, 0.025, lumP);
    #ifndef AUTO_EXPOSURE

    scotopic = max(scotopic, smoothstep(2.5, 6.0, hourAdapt) * 0.9);
    #endif
    color = mix(color, vec3(0.55, 0.7, 1.0) * lumP * 1.25, scotopic * 0.65);
    #endif

    float exposure;
    #ifdef AUTO_EXPOSURE

    float maxLod = floor(log2(max(res.x, res.y)));
    float logAvg = textureLod(colortex4, vec2(0.5), maxLod - 1.0).a * 0.5 + textureLod(colortex4, vec2(0.5, 0.45), maxLod - 2.0).a * 0.5;
    float target = clamp(0.18 / max(exp2(logAvg), 1e-6), 0.3, 12.0);
    float prev = texture(colortex6, vec2(0.5)).r;
    if (!(prev > 0.0) || prev > 100.0) prev = target;
    float speed = target < prev ? 2.5 : 1.0;
    exposure = exp2(mix(log2(prev), log2(target), 1.0 - exp(-frameTime * speed)));
    #else

    float eb = float(eyeBrightnessSmooth.y) / 240.0;
    exposure = 0.25 * mix(4.0, hourAdapt, eb);
    #endif
    out1 = vec4(exposure);
    color *= exposure * EXPOSURE_BIAS;

    #ifdef VIGNETTE

    {
        vec2 ndc = uv * 2.0 - 1.0;
        vec2 tanHalf = vec2(1.0 / gbufferProjection[0][0], 1.0 / gbufferProjection[1][1]) / zoomScale();
        float t2 = dot(ndc * tanHalf, ndc * tanHalf);
        float cos4 = 1.0 / ((1.0 + t2) * (1.0 + t2));
        color *= mix(1.0, cos4, VIGNETTE_STRENGTH);
    }
    #endif

    float lumS = luminance(color);
    color = max(mix(vec3(lumS), color, SATURATION), 0.0);
    color = filmCurve(color);

    #ifdef VITALS_FX
    {

        vec2 v = texcoord - 0.5;
        float edge = saturate(dot(v, v) * 2.4);
        float hp = currentPlayerHealth < 0.0 ? 1.0 : currentPlayerHealth;
        float low = 1.0 - smoothstep(0.15, 0.4, hp);
        float beat = pow(0.5 + 0.5 * sin(frameTimeCounter * mix(5.0, 9.5, low)), 6.0);
        color = mix(color, vec3(luminance(color)), low * 0.55);
        color = mix(color, vec3(0.42, 0.0, 0.0), saturate(edge * (low * (0.45 + 0.55 * beat) + hurtFlash * 0.7)));
        if (isEyeInWater == 1 && currentPlayerAir >= 0.0) {
            float suffocate = 1.0 - smoothstep(0.0, 0.35, currentPlayerAir);
            color *= 1.0 - saturate(edge * 1.8) * suffocate;
        }
    }
    #endif

    out0 = vec4(color, 1.0);
}
#endif
