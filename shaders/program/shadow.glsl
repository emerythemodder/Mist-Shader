#if defined FSH
#define RIPPLE_ACT_WRITE
#endif
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/shadow_distort.glsl"
#include "/lib/waving.glsl"

#if defined USE_RIPPLES && defined FSH
#include "/lib/ripples.glsl"
#endif
#if defined USE_RT_LIGHTS && defined GSH
#define FAR_OCC_WRITE
#include "/lib/rt_lights.glsl"
#endif

#if defined USE_SNOW_TRACKS && defined FSH
#define SNOW_IMAGES
#include "/lib/snow.glsl"
#endif

#if defined USE_PLANT_BEND && defined FSH
#include "/lib/contact.glsl"
#endif

uniform sampler2D gtexture;

#ifdef VSH
in vec4 mc_Entity;
in vec3 at_midBlock;
#if defined SMOOTH_TERRAIN && defined USE_RT_LIGHTS
in uvec4 at_neighbors;
flat out uint vsSolidMask;
#endif

out vec2 vsTexcoord;
out vec4 vsGlcolor;
out vec3 vsPlayerPos;
flat out int vsBlockId;
flat out int vsIsTerrain;
flat out float vsNormalY;
out vec3 vsWorldPos;
out vec3 vsNormal;
out vec3 vsBlockCenter;

void main() {
    vsTexcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vsGlcolor = gl_Color;
    int blockId = int(mc_Entity.x + 0.5);
    vsBlockId = blockId;

    int isTerrain = dot(at_midBlock, at_midBlock) > 1e-6 ? 1 : 0;
    #ifdef MC_RENDER_STAGE_TERRAIN_SOLID
    if (renderStage == MC_RENDER_STAGE_TERRAIN_SOLID || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT ||
        renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED || renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT) isTerrain = 1;
    #endif

    #ifdef MC_RENDER_STAGE_BLOCK_ENTITIES
    if (renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES || renderStage == MC_RENDER_STAGE_ENTITIES) isTerrain = 0;
    #endif
    vsIsTerrain = isTerrain;
    vec4 vertexPos = gl_Vertex;
    #ifdef PHYSICS_OCEAN_V3

    vec4 physics_position = physics_oceanVertex(gl_Vertex);
    if (blockId == 10001) vertexPos = physics_position;
    #endif
    vec3 playerPos = (shadowModelViewInverse * (gl_ModelViewMatrix * vertexPos)).xyz;
    vsNormalY = (mat3(shadowModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal)).y;
    vsWorldPos = playerPos + cameraPosition;
    vsBlockCenter = vsWorldPos + at_midBlock / 64.0;
    vsNormal = mat3(shadowModelViewInverse) * (gl_NormalMatrix * gl_Normal);
    #if defined SMOOTH_TERRAIN && defined USE_RT_LIGHTS
    vsSolidMask = at_neighbors.z & 0x3FFFFFFu;
    #endif

#ifdef USE_SHADOWS
    vec2 lm = lightmapRemap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    playerPos += getWaving(playerPos + cameraPosition, blockId, at_midBlock, lm.y);
    vec4 clip = shadowProjection * (shadowModelView * vec4(playerPos, 1.0));
    gl_Position = vec4(distortShadowClip(clip.xyz), 1.0);
#else
    gl_Position = vec4(-10.0, -10.0, -10.0, 1.0);
#endif
    vsPlayerPos = playerPos;
}
#endif

#ifdef GSH
layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;

in vec2 vsTexcoord[];
in vec4 vsGlcolor[];
in vec3 vsPlayerPos[];
flat in int vsBlockId[];
flat in int vsIsTerrain[];
flat in float vsNormalY[];
in vec3 vsWorldPos[];
in vec3 vsNormal[];
in vec3 vsBlockCenter[];
#if defined SMOOTH_TERRAIN && defined USE_RT_LIGHTS
flat in uint vsSolidMask[];
#endif

out vec2 texcoord;
out vec4 glcolor;
out vec3 playerPos;
flat out int blockId;
flat out int isTerrain;
flat out float normalY;
out float baseY;

void main() {
    #ifdef USE_RT_LIGHTS
    vec3 e1 = vsWorldPos[1] - vsWorldPos[0], e2 = vsWorldPos[2] - vsWorldPos[0];
    vec3 geoN = cross(e1, e2);

    ivec3 vc = ivec3(floor((vsWorldPos[0] + vsWorldPos[1] + vsWorldPos[2]) / 3.0)) - voxelOrigin();
    bool nearVolume = all(greaterThanEqual(vc, ivec3(-1))) && all(lessThanEqual(vc, voxelSize()));
    if (nearVolume && dot(geoN, geoN) > 1e-12) {
        if (vsIsTerrain[0] == 1) {

            bool holes = false;
            if (onGrid(vsWorldPos[0]) && onGrid(vsWorldPos[1]) && onGrid(vsWorldPos[2])) {
                vec2 lo = min(vsTexcoord[0], min(vsTexcoord[1], vsTexcoord[2]));
                vec2 hi = max(vsTexcoord[0], max(vsTexcoord[1], vsTexcoord[2]));
                for (int k = 0; k < 16 && !holes; k++)
                    holes = textureLod(gtexture, mix(lo, hi, (vec2(k & 3, k >> 2) + 0.5) / 4.0), 0.0).a < 0.5;
            }

            vec3 tint = max(vsGlcolor[0].rgb, max(vsGlcolor[1].rgb, vsGlcolor[2].rgb));
            #ifdef SMOOTH_TERRAIN
            vxGroundMask = vsSolidMask[0];
            #endif
            voxelizeTriangle(vsWorldPos[0], vsWorldPos[1], vsWorldPos[2], vsTexcoord[0], vsTexcoord[1], vsTexcoord[2],
                             holes, vsBlockId[0], vec2(textureSize(gtexture, 0)), tint, vsBlockCenter[0]);
        } else {

            vec2 uvc = (vsTexcoord[0] + vsTexcoord[1] + vsTexcoord[2]) / 3.0;
            float a = texture(gtexture, uvc).a;
            for (int i = 0; i < 3; i++) a = max(a, texture(gtexture, mix(vsTexcoord[i], uvc, 0.25)).a);
            if (a * vsGlcolor[0].a > 0.1) voxelizeEntityTriangle(vsWorldPos[0], vsWorldPos[1], vsWorldPos[2]);
        }
    }

    if (vsIsTerrain[0] == 1) farOccMarkTriangle(vsWorldPos[0], vsWorldPos[1], vsWorldPos[2], vsBlockId[0], vsBlockCenter[0]);
    #endif

    bool raster = vsIsTerrain[0] == 0;
    #ifdef USE_RIPPLES
    raster = raster || (vsBlockId[0] == 10001 && vsNormalY[0] > 0.5);
    #endif
    #ifdef USE_SNOW_TRACKS
    raster = raster || ((vsBlockId[0] == 10019 || vsBlockId[0] == 10029 || vsBlockId[0] == 10053) && vsNormalY[0] > 0.5);
    #endif
    if (!raster) return;
    for (int i = 0; i < 3; i++) {
        gl_Position = gl_in[i].gl_Position;
        texcoord = vsTexcoord[i];
        glcolor = vsGlcolor[i];
        playerPos = vsPlayerPos[i];
        blockId = vsBlockId[i];
        isTerrain = vsIsTerrain[i];
        normalY = vsNormalY[i];
        baseY = vsPlayerPos[i].y + cameraPosition.y;
        EmitVertex();
    }
    EndPrimitive();
}
#endif

#ifdef FSH
in vec2 texcoord;
in vec4 glcolor;
in vec3 playerPos;
flat in int blockId;
flat in int isTerrain;
flat in float normalY;
in float baseY;

layout(location = 0) out vec4 shadowOut;

void main() {
    vec3 worldPos = playerPos + cameraPosition;
    if (isTerrain == 1) {

        #ifdef USE_RIPPLES
        if (blockId == 10001) stampWaterLevel(worldPos);
        #endif
        #ifdef USE_SNOW_TRACKS
        if (blockId == 10019 || blockId == 10029 || blockId == 10053) stampSnowLevel(vec3(worldPos.x, baseY, worldPos.z));
        #endif
        discard;
    }
    vec4 c = texture(gtexture, texcoord) * glcolor;
    if (c.a < 0.1) discard;

    #if defined USE_SNOW_TRACKS || defined USE_PLANT_BEND

    bodyContact(worldPos);
    #endif

    #ifdef USE_RIPPLES

    vec3 eye = cameraPosition - relativeEyePosition;

    bool me = length(worldPos.xz - eye.xz) < 0.45 && worldPos.y < eye.y + 0.5 && worldPos.y > eye.y - 2.2;
    if (!me) {
        float level;
        if (waterLevelNear(worldPos.xz, level) && worldPos.y < level + 0.15 && worldPos.y > level - 1.2)
            injectRipple(worldPos, entityId == 20002 ? 0.9 : 0.6);
    }
    #endif

    shadowOut = vec4(toLinear(c.rgb), 0.0);
}
#endif
