#ifndef RIPPLE_ACT_GLSL
#define RIPPLE_ACT_GLSL
#ifdef RIPPLE_ACT_WRITE
layout(std430, binding = 3) buffer RippleAct { float rippleAct[64 * 64]; };
#else
layout(std430, binding = 3) readonly buffer RippleAct { float rippleAct[64 * 64]; };
#endif
int rippleActIndex(ivec2 cell) { ivec2 g = (cell & (RIPPLE_RES - 1)) >> 4; return g.y * 64 + g.x; }
#ifdef RIPPLE_ACT_WRITE
void rippleMarkActive(ivec2 cell) { rippleAct[rippleActIndex(cell)] = float(frameCounter); }
#endif

bool rippleActive(vec2 worldXZ) { return rippleAct[rippleActIndex(ivec2(floor(worldXZ * RIPPLE_CELLS)))] == float(frameCounter); }
#endif
