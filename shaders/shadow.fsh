#version 430 compatibility

#define IMAGE_CAPABLE
#define WORLD_OVERWORLD
#define FSH
/* RENDERTARGETS: 0 */
/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA8;
const int colortex4Format = RGBA16F;
const int colortex5Format = RGBA16;
const int colortex6Format = R32F;
const int shadowcolor0Format = RGBA8;
const bool colortex6Clear = false;
const int colortex7Format = RGBA16F;
const bool colortex7Clear = false;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 1.0);
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
*/
#include "/program/shadow.glsl"
