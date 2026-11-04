#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/shadows.glsl"

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
const ivec3 workGroups = ivec3(16, 8, 16);

#if defined USE_VOLUMETRIC_LIGHT && defined USE_RT_SUN_SHADOWS
#define PT_TRACE
#include "/lib/rt_lights.glsl"
layout(rgba16f) uniform image3D sunVisImg;
#endif

void main() {
#if defined USE_VOLUMETRIC_LIGHT && defined USE_RT_SUN_SHADOWS
    ivec3 cell = ivec3(gl_GlobalInvocationID);
    vec3 vp = vec3(cell * 2) + 1.0;
    vec3 L = getLightDir();
    vec3 vis = traceVoxels(vp, L, 48.0, ivec3(-1000), 80, true, true);
    if (rtWaterLen > 0.0) vis *= exp(-WATER_ABSORB * rtWaterLen);
    if (rtRayEscaped && max(vis.r, max(vis.g, vis.b)) > 0.0) {
        vec3 w = rtRayEnd + vec3(voxelOrigin());
        if (farCovers(w)) vis *= farTrace(w, L, 200.0, 0.0);
    }
    imageStore(sunVisImg, cell, vec4(vis, 1.0));
#endif
}
