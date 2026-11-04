#ifndef VOXEL_COMMON_GLSL
#define VOXEL_COMMON_GLSL

#define VOXEL_SIZE_X 128
#define VOXEL_SIZE_Y 64
#define VOXEL_SIZE_Z 128
#define MAX_RT_LIGHTS 256
#define MAX_RT_TRIS 262144
#define RT_TRACE_FADE_START 16.0
#define RT_TRACE_FADE_END 40.0

#define VX_EMPTY 0u
#define VX_ENTITY 1u
#define VX_GROUND 2u
#define VX_GROUND_BIT 0x80000000u

#define VX_DECODE(v) ((((v) & VX_GROUND_BIT) != 0u) ? VX_GROUND : (v))
#define VX_SLAB_BOTTOM 4u
#define VX_SLAB_TOP 5u
#define VX_THIN 6u
#define VX_POST 7u
#define VX_TINT 10u
#define VX_WATER 28u
#define VX_LEAVES 29u
#define VX_PLANT 31u
#define VX_SHAPED 32u
#define VX_LIGHT 48u
#define VX_LIGHT_BLOCK 64u

layout(std430, binding = 1) buffer RTTriangles {
    uint rtTriCount;
    uint rtTriPad0, rtTriPad1, rtTriPad2;
    uvec4 rtTris[];
};

ivec3 voxelSize()   { return ivec3(VOXEL_SIZE_X, VOXEL_SIZE_Y, VOXEL_SIZE_Z); }
ivec3 voxelOrigin() { return ivec3(floor(cameraPosition)) - voxelSize() / 2; }
bool inVoxelVolume(ivec3 c) { return all(greaterThanEqual(c, ivec3(0))) && all(lessThan(c, voxelSize())); }
vec3 toVoxelSpace(vec3 playerPos) { return playerPos + cameraPosition - vec3(voxelOrigin()); }

uint packLocal(vec3 l) {
    uvec3 q = uvec3(clamp((l + 1.0) / 3.0, 0.0, 1.0) * 1023.0 + 0.5);
    return q.x | (q.y << 10) | (q.z << 20);
}
vec3 unpackLocal(uint v) {
    return vec3(uvec3(v, v >> 10, v >> 20) & 1023u) / 1023.0 * 3.0 - 1.0;
}
#endif
