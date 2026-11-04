#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

VARY vec4 glcolor;
VARY vec2 lmcoord;
VARY vec3 playerPos;
VARY vec3 normalW;
flat VARY int matId;

#ifdef VSH
void main() {
    glcolor = gl_Color;
    lmcoord = lightmapRemap(gl_MultiTexCoord2.xy);
    playerPos = (gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
    normalW = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);

    matId = 1;
    if (dhMaterialId == DH_BLOCK_LEAVES) matId = 2;
    else if (dhMaterialId == DH_BLOCK_ILLUMINATED) matId = 4;
    else if (dhMaterialId == DH_BLOCK_LAVA) matId = 5;
    else if (dhMaterialId == DH_BLOCK_SNOW) matId = 8;

    vec3 p = playerPos;
    p.y -= curvatureDrop(p.xz);
    gl_Position = gl_ProjectionMatrix * (gbufferModelView * vec4(p, 1.0));
    gl_Position.xy *= zoomScale();
    gl_Position.xy += taaOffset() * gl_Position.w;
}
#endif

#ifdef FSH
layout(location = 0) out vec4 out0;
layout(location = 1) out vec4 out1;
layout(location = 2) out vec4 out2;

void main() {
    #ifdef DH_GENERIC

    if (matId != 4) { discard; return; }
    #endif

    if (length(playerPos.xz) < max(far - 32.0, far * 0.6)) { discard; return; }

    vec3 worldPos = playerPos + cameraPosition;
    vec3 albedo = glcolor.rgb;
    if (dh_hasTexture()) {

        vec4 tile = dh_sampleTexture();

        if (tile.r + tile.g + tile.b > 0.02) albedo = mix(albedo, clamp(albedo * tile.rgb * 2.0, 0.0, 1.0), tile.a);
    } else {

        float n = hash12(floor(worldPos.xz + 0.001 * worldPos.y)) * 0.6 + valueNoise(worldPos.xz * 0.35) * 0.4;
        albedo *= 0.88 + 0.24 * n;
    }

    float emissive = 0.0;
    if (matId == 4) emissive = smoothstep(0.5, 0.9, max(albedo.r, max(albedo.g, albedo.b)));
    if (matId == 5) emissive = 1.0;

    out0 = vec4(albedo, 1.0);
    out1 = vec4(encodeNormal(normalize(normalW)), lmcoord);
    out2 = vec4(float(matId) / 255.0, 0.0, 0.0, emissive);
}
#endif
