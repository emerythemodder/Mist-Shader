#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/clouds.glsl"

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

flat VARY vec3 directLight;
flat VARY vec3 ambientLight;

#ifdef VSH
void main() {
    gl_Position = ftransform();
    getLightColors(directLight, ambientLight);
}
#endif

#ifdef FSH
uniform sampler2D colortex7;
uniform sampler2D depthtex1;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
layout(location = 0) out vec4 out0;

void main() {
    vec2 view = vec2(viewWidth, viewHeight);
    vec2 halfRes = ceil(view * 0.5);
    vec2 frag = gl_FragCoord.xy;
    if (frag.x > halfRes.x || frag.y > halfRes.y) { out0 = vec4(0.0, 0.0, 0.0, -1.0); return; }

#ifdef USE_VOLUMETRIC_CLOUDS

    ivec2 full = ivec2(frag - 0.5) * 2;
    ivec2 fullMax = ivec2(view) - 1;
    bool anySky = false;
    for (int k = 0; k < 4; k++) {
        ivec2 q = min(full + ivec2(k & 1, k >> 1), fullMax);
        bool terrain = texelFetch(depthtex1, q, 0).r < 1.0;
        #ifdef DISTANT_HORIZONS
        terrain = terrain || texelFetch(dhDepthTex1, q, 0).r < 1.0;
        #endif
        #ifdef VOXY
        terrain = terrain || texelFetch(vxDepthTexOpaque, q, 0).r < 1.0;
        #endif
        anySky = anySky || !terrain;
    }
    if (!anySky) { out0 = vec4(0.0, 0.0, 0.0, -1.0); return; }

    vec2 uv = frag / halfRes;
    vec3 dir = normalize(mat3(gbufferModelViewInverse) * normalize(screenToView(vec3(uv, 1.0))));

    vec4 prev = vec4(0.0, 0.0, 0.0, -1.0);
    vec3 pv = mat3(gbufferPreviousModelView) * dir;
    vec4 pc = gbufferPreviousProjection * vec4(pv, 0.0);
    pc.xy *= zoomScale();
    if (pv.z < 0.0 && pc.w > 0.0) {
        vec2 puv = pc.xy / pc.w * 0.5 + 0.5;
        if (!outsideScreen(puv)) {
            vec2 texel = clamp(puv * halfRes, vec2(0.5), halfRes - 0.5);
            vec4 p = texture(colortex7, texel / view);
            if (!(any(isnan(p)) || any(isinf(p))) && p.a >= 0.0 && p.a <= 1.0) prev = p;
        }
    }

    ivec2 ip = ivec2(frag);
    int phase = (ip.x & 1) + 2 * (ip.y & 1);
    bool traceNow = phase == (frameCounter & 3) || prev.a < 0.0;

    vec4 cl;
    if (traceNow) {
        float dither = fract(ign(frag + 5.588238 * float(frameCounter % 64)));
        cl = renderClouds(dir, directLight, ambientLight, dither);
        if (prev.a >= 0.0) cl = mix(prev, cl, 0.35);
    } else {
        cl = prev;
    }
    cl.rgb = sanitize(cl.rgb);
    out0 = vec4(cl.rgb, saturate(cl.a));
#else
    out0 = vec4(0.0, 0.0, 0.0, 1.0);
#endif
}
#endif
