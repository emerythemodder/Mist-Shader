#version 430 compatibility
#define IMAGE_CAPABLE
#define WORLD_OVERWORLD
#define CSH
#define MPM_PASS 2
#define MPM_K 0
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
const ivec3 workGroups = ivec3(640, 1, 1);
#include "/program/mpm.glsl"
