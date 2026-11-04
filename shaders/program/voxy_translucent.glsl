#include "/lib/settings.glsl"

layout(location = 0) out vec4 lodColor;

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    vec4 c = parameters.sampledColour * parameters.tinting;
    if (c.a < 0.01) discard;
    vec3 sunDir = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    vec3 lightDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    float day = clamp(sunDir.y * 3.0 + 0.3, 0.02, 1.0) * (1.0 - rainStrength * 0.6);
    vec3 sky = pow(skyColor, vec3(2.2));
    vec3 horizon = pow(fogColor, vec3(2.2));
    float skyL = clamp(parameters.lightMap.y, 0.0, 1.0);
    vec3 amb = sky * 0.9 + vec3(0.6) * day;
    bool water = int(parameters.customId) == 10001;
    if (!water) {
        lodColor = vec4(pow(c.rgb, vec3(2.2)) * amb * skyL * skyL, c.a);
        return;
    }

    vec2 ndc = gl_FragCoord.xy / vec2(viewWidth, viewHeight) * 2.0 - 1.0;
    vec4 vv = gbufferProjectionInverse * vec4(ndc, 1.0, 1.0);
    vec3 wdir = normalize(mat3(gbufferModelViewInverse) * (vv.xyz / vv.w));

    int face = int(parameters.face);
    int axis = face >> 1;
    float s = (face & 1) == 1 ? 1.0 : -1.0;
    vec3 n = vec3(axis == 2 ? s : 0.0, axis == 0 ? s : 0.0, axis == 1 ? s : 0.0);
    float NdotV = clamp(-dot(wdir, n), 0.0, 1.0);
    vec3 R = reflect(wdir, n);
    vec3 skyR = mix(horizon, sky, sqrt(clamp(R.y, 0.0, 1.0))) * 1.6 * (0.2 + 0.8 * day);
    float F = 0.02 + 0.98 * pow(1.0 - NdotV, 5.0);
    vec3 body = pow(c.rgb, vec3(2.2)) * amb * 0.3;
    vec3 H = normalize(lightDir - wdir);
    float glint = lightDir.y > 0.0 ? pow(clamp(dot(n, H), 0.0, 1.0), 400.0) * 8.0 * day : 0.0;
    vec3 col = (body * (1.0 - F) + skyR * F) * skyL * skyL + vec3(1.0, 0.95, 0.85) * glint * skyL;
    lodColor = vec4(col, mix(0.8, 1.0, F));
}
