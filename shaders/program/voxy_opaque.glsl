#include "/lib/settings.glsl"

layout(location = 0) out vec4 lodAlbedo;
layout(location = 1) out vec4 lodNormal;
layout(location = 2) out vec4 lodMaterial;

vec2 lodEncodeNormal(vec3 n) {
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    vec2 wrapped = (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
    vec2 e = n.z >= 0.0 ? n.xy : wrapped;
    return e * 0.5 + 0.5;
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    vec4 albedo = parameters.sampledColour * parameters.tinting;
    if (albedo.a < 0.1) discard;

    int face = int(parameters.face);
    int axis = face >> 1;
    float s = (face & 1) == 1 ? 1.0 : -1.0;
    vec3 normal = vec3(axis == 2 ? s : 0.0, axis == 0 ? s : 0.0, axis == 1 ? s : 0.0);

    int id = int(parameters.customId);
    int matId = 1;
    float emissive = 0.0;
    if (id == 10002) matId = 2;
    else if (id == 10003 || id == 10006 || id == 10018) { matId = 3; normal = vec3(0.0, 1.0, 0.0); }
    else if (id == 10004 || (id >= 10009 && id <= 10015) || id == 10017) {
        matId = 4;
        emissive = smoothstep(0.55, 0.9, max(albedo.r, max(albedo.g, albedo.b)));
    }
    else if (id == 10005) { matId = 5; emissive = 1.0; }
    else if (id >= 10060 && id <= 10071) matId = 7;
    else if (id == 10019 || id == 10029) matId = 8;

    lodAlbedo = vec4(albedo.rgb, 1.0);
    lodNormal = vec4(lodEncodeNormal(normal), clamp(parameters.lightMap, 0.0, 1.0));
    lodMaterial = vec4(float(matId) / 255.0, 0.0, 0.0, emissive);
}
