#version 430 compatibility
#define IMAGE_CAPABLE
#define WORLD_OVERWORLD
#define FSH
/* RENDERTARGETS: 11,12 */
/*
const int colortex10Format = RGBA16F;
const int colortex11Format = RGBA16F;
const int colortex12Format = RGBA16F;
const int colortex13Format = RGBA16F;
const int colortex14Format = RGBA16F;
const bool colortex11Clear = false;
const bool colortex12Clear = false;
*/
#include "/program/pt_accum.glsl"
