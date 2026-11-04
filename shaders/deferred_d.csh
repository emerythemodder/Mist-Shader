#version 430 compatibility
#define IMAGE_CAPABLE
#define WORLD_OVERWORLD
#define CSH
#define ENV_PASS 0
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const ivec3 workGroups = ivec3(8, 8, 1);
#include "/program/env_capture.glsl"
