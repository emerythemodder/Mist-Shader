#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif
VARY vec2 texcoord;

#ifdef VSH
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
#endif

#ifdef FSH
uniform sampler2D colortex0;
layout(location = 0) out vec4 fragColor;

vec3 fxaa(vec2 uv, vec2 inv) {
    const vec3 lw = vec3(0.299, 0.587, 0.114);
    vec3 rgbNW = texture(colortex0, uv + vec2(-1.0, -1.0) * inv).rgb;
    vec3 rgbNE = texture(colortex0, uv + vec2( 1.0, -1.0) * inv).rgb;
    vec3 rgbSW = texture(colortex0, uv + vec2(-1.0,  1.0) * inv).rgb;
    vec3 rgbSE = texture(colortex0, uv + vec2( 1.0,  1.0) * inv).rgb;
    vec3 rgbM  = texture(colortex0, uv).rgb;
    float lNW = dot(rgbNW, lw), lNE = dot(rgbNE, lw), lSW = dot(rgbSW, lw), lSE = dot(rgbSE, lw), lM = dot(rgbM, lw);
    float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
    float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));
    vec2 dir = vec2(-((lNW + lNE) - (lSW + lSE)), (lNW + lSW) - (lNE + lSE));
    float dirReduce = max((lNW + lNE + lSW + lSE) * 0.03125, 1.0 / 128.0);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpDirMin, vec2(-8.0), vec2(8.0)) * inv;
    vec3 rgbA = 0.5 * (texture(colortex0, uv + dir * (1.0 / 3.0 - 0.5)).rgb + texture(colortex0, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (texture(colortex0, uv - dir * 0.5).rgb + texture(colortex0, uv + dir * 0.5).rgb);
    float lB = dot(rgbB, lw);
    return (lB < lMin || lB > lMax) ? rgbA : rgbB;
}

#if defined LENS_RAIN || defined WET_LENS

vec2 lensRain(vec2 uv) {
    float amount = 0.0;
    #ifdef LENS_RAIN
    float outside = pow(float(eyeBrightnessSmooth.y) / 240.0, 2.0);
    amount = rainStrength * outside * float(isEyeInWater == 0) * (1.0 - snowyBiome);
    #endif
    #ifdef WET_LENS
    amount = max(amount, wetLens * float(isEyeInWater == 0) * 1.3);
    #endif
    if (amount <= 0.01) return vec2(0.0);
    float aspect = viewWidth / viewHeight;
    vec2 p = uv * vec2(aspect, 1.0) * 7.0;
    vec2 offset = vec2(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 cell = floor(p) + vec2(float(x), float(y));
            float h = hash12(cell);
            if (h > amount * 0.7) continue;
            float life = fract(frameTimeCounter * (0.08 + 0.1 * hash12(cell + 3.1)) + h * 7.0);
            vec2 c = cell + hash22(cell) - vec2(0.0, life * life * 1.5);
            float r = mix(0.08, 0.2, hash12(cell + 9.7)) * (1.0 - life * 0.4);
            vec2 v = p - c;
            float dd = dot(v, v) / (r * r);
            if (dd < 1.0) offset += -v / r * (1.0 - dd) * 0.035 * (1.0 - smoothstep(0.85, 1.0, life));
        }
    }
    return offset / vec2(aspect, 1.0);
}
#endif

void main() {
    vec2 inv = 1.0 / vec2(viewWidth, viewHeight);
    vec2 uv0 = texcoord;
    vec2 rainOffset = vec2(0.0);
    #if defined LENS_RAIN || defined WET_LENS
    rainOffset = lensRain(texcoord);
    #endif
    #ifdef USE_FXAA
    vec3 color = dot(rainOffset, rainOffset) > 0.0 ? texture(colortex0, uv0 + rainOffset).rgb : fxaa(uv0, inv);
    #else
    vec3 color = texture(colortex0, uv0 + rainOffset).rgb;
    #endif

    {
        vec3 a = texture(colortex0, uv0 + vec2(0.0,  inv.y)).rgb, b = texture(colortex0, uv0 + vec2(0.0, -inv.y)).rgb;
        vec3 c = texture(colortex0, uv0 + vec2( inv.x, 0.0)).rgb, d = texture(colortex0, uv0 + vec2(-inv.x, 0.0)).rgb;
        vec3 mn = min(min(min(a, b), min(c, d)), color), mx = max(max(max(a, b), max(c, d)), color);
        vec3 room = min(mn, 1.0 - mx) / max(mx, 1e-3);
        vec3 amt = sqrt(saturate(room)) * SHARPENING * 0.6;
        color = saturate(color + (color - (a + b + c + d) * 0.25) * amt);
    }

    #ifdef COLD_BREATH
    {

        float cold = snowyBiome * pow(float(eyeBrightnessSmooth.y) / 240.0, 1.5) * float(isEyeInWater == 0);
        float cycle = fract(frameTimeCounter / 3.6);
        float life = cycle / 0.45;
        if (cold > 0.01 && life < 1.0) {
            vec2 p = (texcoord - vec2(0.5, 0.06 + life * 0.14)) * vec2(viewWidth / viewHeight, 1.0);
            float r = 0.07 + life * 0.15;
            float n = valueNoise(p * 12.0 + vec2(0.0, -frameTimeCounter * 1.5)) * 0.6 + 0.4;
            float puff = exp(-dot(p, p) / (r * r)) * n * sin(life * PI) * cold;
            color = mix(color, vec3(0.92, 0.95, 1.0), saturate(puff * 0.25));
        }
    }
    #endif
    #ifdef FILM_GRAIN

    {
        float fr = float(frameCounter % 256) * 13.7;
        float g = (hash12(gl_FragCoord.xy + fr) + hash12(gl_FragCoord.xy * 1.37 + fr + 5.1) - 1.0);
        float lumG = luminance(color);
        color = saturate(color + g * 0.035 * 4.0 * lumG * (1.0 - lumG));
    }
    #endif
    color += (ign(gl_FragCoord.xy) - 0.5) / 255.0;
    fragColor = vec4(color, 1.0);
}
#endif
