#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
const ivec3 workGroups = ivec3(16, 8, 16);

#ifdef USE_RT_LIGHTS
#include "/lib/rt_lights.glsl"

bool writeA;

vec3 prevLight(ivec3 c) {
    if (!inVoxelVolume(c)) return vec3(0.0);
    return writeA ? imageLoad(lpvImgB, c).rgb : imageLoad(lpvImgA, c).rgb;
}
#endif

void main() {
#ifdef USE_RT_LIGHTS
    ivec3 c = ivec3(gl_GlobalInvocationID);
    if (!inVoxelVolume(c)) return;
    writeA = (frameCounter & 1) == 0;

    uint code = VX_DECODE(imageLoad(voxelImg, c).r);

    ivec3 shift = ivec3(floor(cameraPosition)) - ivec3(floor(previousCameraPosition));
    ivec3 pc = c + shift;

    uint faces = imageLoad(voxelFaceImg, c).r;
    float cover = (faces & 0xFC0u) != 0u ? faceCoverage(faces) : 0.0;
    vec3 sum = vec3(0.0);
    for (int s = 0; s < 6; s++) {
        if ((faces & (1u << uint(s))) != 0u) continue;
        ivec3 o = ivec3(0);
        o[s >> 1] = (s & 1) == 0 ? -1 : 1;
        float k = (faces & (64u << uint(s))) != 0u ? 1.0 - 0.8 * cover : 1.0;
        sum += prevLight(pc + o) * k;
    }
    vec3 light = sum * (0.975 / 6.0);
    if (isTintCode(code)) light *= tintColor(code);
    else if (code == VX_PLANT) light *= 0.95;
    else if (code == VX_SHAPED || (code >= VX_SLAB_BOTTOM && code <= VX_POST)) light *= 0.85;

    if (code >= VX_LIGHT) {
        uint type = lightCodeType(code);
        float range = lightTypeRange(type);
        light += lightTypeColor(int(type)) * (exp2(range) - 1.0);

        bool interior = true;
        for (int i = 0; i < 6; i++) {
            ivec3 o = ivec3(0);
            o[i >> 1] = (i & 1) == 0 ? 1 : -1;
            uint n = inVoxelVolume(c + o) ? VX_DECODE(imageLoad(voxelImg, c + o).r) : VX_EMPTY;

            if (n != code && !(type == 6u && o.y == 1 && n == VX_EMPTY)) { interior = false; break; }
        }
        vec3 center = vec3(c) + 0.5;
        float distToCam = length(center - toVoxelSpace(vec3(0.0)));
        if (!interior && distToCam < RT_TRACE_FADE_END + 16.0) {
            uint idx = atomicAdd(rtLightCount, 1u);
            if (idx < uint(MAX_RT_LIGHTS)) rtLights[idx] = vec4(center, float(type) * 16.0 + range);
        }
    }

    if (any(isnan(light)) || any(isinf(light))) light = vec3(0.0);
    light = min(light, vec3(60000.0));
    if (writeA) imageStore(lpvImgA, c, vec4(light, 1.0));
    else        imageStore(lpvImgB, c, vec4(light, 1.0));
#endif
}
