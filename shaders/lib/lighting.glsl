vec3 blockLightColor(float lm) {
    return vec3(1.0, 0.58, 0.28) * BLOCKLIGHT_STRENGTH * (pow(lm, 4.5) * 1.6 + lm * lm * 0.03);
}

#define MIN_LIGHT (vec3(0.0012, 0.0014, 0.0020) * (1.0 + 4.0 * screenBrightness))

void getLightColors(out vec3 direct, out vec3 ambient) {
#if defined WORLD_OVERWORLD
    vec3 sd = getSunDir();
    vec3 tauT = TAU_R + vec3(TAU_M) + TAU_O;
    vec3 sunL  = SUN_E * sunVisibility() * exp(-tauT * airmass(sd.y)) * smoothstep(-0.03, 0.08, sd.y);
    vec3 moonL = MOON_E * moonBrightness() * moonTint() * exp(-tauT * airmass(-sd.y)) * smoothstep(-0.03, 0.08, -sd.y);
    direct = (sunL + moonL) * (1.0 - rainStrength * 0.9);

    ambient  = getSky(vec3(0.0, 1.0, 0.0), false) * 0.4;
    ambient += getSky(normalize(vec3( 1.0, 0.25,  0.0)), false) * 0.15;
    ambient += getSky(normalize(vec3(-1.0, 0.25,  0.0)), false) * 0.15;
    ambient += getSky(normalize(vec3( 0.0, 0.25,  1.0)), false) * 0.15;
    ambient += getSky(normalize(vec3( 0.0, 0.25, -1.0)), false) * 0.15;
    ambient += vec3(0.5, 0.55, 0.8) * lightningFlash() * 0.35;
    ambient *= AMBIENT_STRENGTH;
#elif defined WORLD_NETHER
    direct = vec3(0.0);
    ambient = (toLinear(fogColor) * 0.6 + vec3(0.03, 0.02, 0.015)) * AMBIENT_STRENGTH;
#else
    direct = vec3(0.0);
    ambient = vec3(0.05, 0.035, 0.08) * AMBIENT_STRENGTH;
#endif
}

vec3 ggxSpecular(vec3 n, vec3 v, vec3 l, float alpha, vec3 f0) {
    vec3 h = normalize(l + v + vec3(0.0, 1e-5, 0.0));
    float NdotL = saturate(dot(n, l));
    float NdotV = max(dot(n, v), 1e-3);
    float NdotH = saturate(dot(n, h));
    float VdotH = saturate(dot(v, h));
    float a2 = alpha * alpha;
    float dd = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * dd * dd);
    float vis = 0.5 / (NdotL * sqrt(NdotV * NdotV * (1.0 - a2) + a2) + NdotV * sqrt(NdotL * NdotL * (1.0 - a2) + a2) + 1e-5);
    vec3 F = f0 + (1.0 - f0) * pow(1.0 - VdotH, 5.0);
    return D * vis * F * NdotL * PI;
}

float schlick(float cosT, float f0) { return f0 + (1.0 - f0) * pow(1.0 - saturate(cosT), 5.0); }
