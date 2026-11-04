#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

VARY vec4 glcolor;
VARY vec2 lmcoord;
VARY vec3 playerPos;
flat VARY int isWater;
flat VARY vec3 directLight;
flat VARY vec3 ambientLight;

#ifdef VSH
void main() {
    glcolor = gl_Color;
    lmcoord = lightmapRemap(gl_MultiTexCoord2.xy);
    playerPos = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    isWater = dhMaterialId == DH_BLOCK_WATER ? 1 : 0;
    vec3 p = playerPos;
    p.y -= curvatureDrop(p.xz);
    gl_Position = gl_ProjectionMatrix * (gbufferModelView * vec4(p, 1.0));
    gl_Position.xy *= zoomScale();
    gl_Position.xy += taaOffset() * gl_Position.w;
    getLightColors(directLight, ambientLight);
}
#endif

#ifdef FSH
layout(location = 0) out vec4 out0;

void main() {
    if (length(playerPos.xz) < max(far - 32.0, far * 0.6)) { discard; return; }
    vec3 V = -normalize(playerPos);
    float skyL = lmcoord.y;
    if (isWater == 1) {
        vec3 n = waterNormal(playerPos + cameraPosition, length(playerPos), 4);
        float F = schlick(saturate(dot(n, V)), 0.02);
        vec3 R = reflect(-V, n);
        R.y = abs(R.y);
        vec3 refl = getSky(R, false) * skyL * skyL;
        vec3 body = toLinear(glcolor.rgb) * (ambientLight * (0.2 + 0.8 * skyL) + directLight * 0.04) * 0.35;
        vec3 col = mix(body, refl, F);
        #ifdef WORLD_OVERWORLD
        col += min(ggxSpecular(n, V, getLightDir(), 0.03, vec3(0.02)) * directLight, vec3(30.0)) * skyL;
        #endif
        out0 = vec4(col, mix(0.82, 1.0, F));
    } else {

        vec3 col = toLinear(glcolor.rgb) * (ambientLight * skyL + directLight * 0.3 * skyL + MIN_LIGHT);
        out0 = vec4(col, glcolor.a);
    }
}
#endif
