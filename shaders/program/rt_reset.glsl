#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

#ifdef USE_RT_LIGHTS
#include "/lib/rt_lights.glsl"
#endif

void main() {
    #ifdef USE_RT_LIGHTS
    rtLightCount = 0u;
    rtTriCount = 0u;
    #endif
}
