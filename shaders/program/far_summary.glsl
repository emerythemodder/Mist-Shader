#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const ivec3 workGroups = ivec3(64, 64, 1);

#ifdef USE_RT_LIGHTS
#define FAR_OCC_WRITE
#include "/lib/far_occ.glsl"
shared uint groupTop;
layout(r32ui) uniform uimage3D voxelBrickImg;
layout(r32ui) uniform uimage3D voxelImg;
layout(r32ui) uniform uimage3D voxelFaceImg;
shared uint groupBricks;
#endif

void main() {
    #ifdef USE_RT_LIGHTS
    if (gl_LocalInvocationIndex == 0u) groupTop = 0u;
    barrier();
    ivec2 c = ivec2(gl_GlobalInvocationID.xy);
    atomicMax(groupTop, imageLoad(farOccImg, ivec3(c.x, FAR_TOP, c.y)).r);
    barrier();
    if (gl_LocalInvocationIndex == 0u) imageStore(farOccImg, ivec3(gl_WorkGroupID.x, FAR_COARSE, gl_WorkGroupID.y), uvec4(groupTop));

    if (gl_WorkGroupID.y < 4u) {
        if (gl_LocalInvocationIndex == 0u) groupBricks = 0u;
        barrier();
        uint l = gl_LocalInvocationIndex;
        ivec3 b = ivec3(gl_WorkGroupID.x & 7u, gl_WorkGroupID.y, gl_WorkGroupID.x >> 3u) * 4 + ivec3(l & 3u, (l >> 2u) & 3u, l >> 4u);
        uint word = imageLoad(voxelBrickImg, b).r;
        if (word != 0u) atomicOr(groupBricks, 1u);
        barrier();
        if (groupBricks == 0u) imageStore(voxelBrickImg, b, uvec4(2u));
        else if (word != 0u) {

            uint water = 0u;
            bool open = true;
            for (int y = 0; y < 4 && open; y++) {
                uint nWater = 0u, nAir = 0u;
                for (int z = 0; z < 4; z++) for (int x = 0; x < 4; x++) {
                    ivec3 v = b * 4 + ivec3(x, y, z);
                    uint code = imageLoad(voxelImg, v).r;
                    if (imageLoad(voxelFaceImg, v).r != 0u) open = false;
                    if (code == 28u) nWater++; else if (code == 0u) nAir++;
                }
                if (nWater == 16u) water |= 1u << uint(y); else if (nAir != 16u) open = false;
            }
            if (open) imageStore(voxelBrickImg, b, uvec4(1u | 4u | (water << 3)));
        }
    }
    #endif
}
