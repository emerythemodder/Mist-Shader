#include "/lib/settings.glsl"

#ifdef VSH
void main() { gl_Position = ftransform(); }
#endif

#ifdef FSH
layout(location = 0) out vec4 out0;
void main() { discard; }
#endif
