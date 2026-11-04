#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"
#include "/lib/sky.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/foam.glsl"
#include "/lib/flashlight.glsl"
#include "/lib/shadows.glsl"
#include "/lib/raytrace.glsl"
#include "/lib/clouds.glsl"
#include "/lib/materials.glsl"
#if defined USE_MPM && defined FSH
#include "/lib/mpm.glsl"
#endif
#if defined USE_IBL && defined FSH
#include "/lib/envprobe.glsl"
#endif
#if defined USE_PT && defined FSH

#define PT_TRACE
#include "/lib/rt_lights.glsl"
#define RT_REFLECTIONS
#endif

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

VARY vec2 texcoord;
flat VARY vec3 directLight;
flat VARY vec3 ambientLight;

#ifdef VSH
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
    getLightColors(directLight, ambientLight);
}
#endif

#ifdef FSH
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

layout(location = 0) out vec4 out0;

vec3 waterInscatter(float dist, float skyL, vec3 tint, float mu) {

    vec3 sc = mix(vec3(0.008, 0.06, 0.085), tint * 0.12, 0.3);
    float phase = mix(1.0, henyeyGreenstein(mu, 0.55), 0.5);
    vec3 light = ambientLight * (0.25 + 0.75 * skyL) + directLight * 0.09 * skyL * phase;
    return sc * light * (1.0 - exp(-(WATER_ABSORB + 0.03) * dist));
}

vec3 traceReflection(vec3 viewPos, vec3 worldR, float skyL, float dither) {

    #ifdef USE_IBL
    vec3 refl = mix(ambientLight * 0.02, envSpecular(worldR, 0.0), skyL * skyL);
    #else
    vec3 refl = mix(ambientLight * 0.02, getSky(worldR, false), skyL * skyL);
    #endif
    vec3 viewR = normalize(mat3(gbufferModelView) * worldR);

    if (viewR.z < 0.0) {
        vec3 sR = viewToScreen(viewR * 1000.0);
        bool skyHere = !outsideScreen(sR.xy) && texture(depthtex1, sR.xy).r >= 1.0;
        #ifdef DISTANT_HORIZONS
        skyHere = skyHere && texture(dhDepthTex1, sR.xy).r >= 1.0;
        #endif
        if (skyHere)
            refl = mix(refl, texture(colortex0, sR.xy).rgb * skyL * skyL, edgeFade(sR.xy));
    }
    bool hit = false;
    float fade = 0.0;
    #ifdef SSR
    vec3 hp = rayTraceSSR(viewPos, viewR, dither, depthtex1, hit);
    if (hit) {
        fade = edgeFade(hp.xy);
        refl = mix(refl, texture(colortex0, hp.xy).rgb, fade);
    }
    #endif
    #ifdef RT_REFLECTIONS

    if (fade < 0.999) {
        vec4 rt = rtReflect(viewToPlayer(viewPos), worldR, directLight, PI * ambientLight, smoothstep(0.02, 0.35, skyL));
        if (rt.a > 0.0) refl = mix(rt.rgb, refl, fade);
    }
    #endif
    return refl;
}

void main() {
    vec2 uv = texcoord;
    vec3 color = texture(colortex0, uv).rgb;
    float d0 = texture(depthtex0, uv).r;
    float d1 = texture(depthtex1, uv).r;
    vec4 t5 = texture(colortex5, uv);

    vec3 vp0 = screenToView(vec3(uv, d0));
    bool lodPixel = false;
    #ifdef VOXY
    if (d0 >= 1.0) {
        float lodDepth = texture(vxDepthTexOpaque, uv).r;
        if (lodDepth < 1.0) { lodPixel = true; vp0 = lodScreenToView(vec3(uv, lodDepth)); }
    }
    #endif
    #ifdef DISTANT_HORIZONS
    if (d0 >= 1.0 && !lodPixel) {
        float dhDepth = texture(dhDepthTex0, uv).r;
        if (dhDepth < 1.0) { lodPixel = true; vp0 = dhScreenToView(vec3(uv, dhDepth)); }
    }
    #endif
    vec3 pp0 = uncurveWorld(viewToPlayer(vp0));
    vec3 wdir = normalize(pp0);
    vec3 V = -wdir;
    float dither = temporalNoise(gl_FragCoord.xy);
    float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;

    if (t5.z > 0.75 && d0 < 1.0) {

        vec3 n = decodeNormal(t5.xy);
        float skyL = t5.w;
        vec3 tint = toLinear(texture(colortex2, uv).rgb);
        float muL = dot(wdir, getLightDir());
        vec3 wpos = pp0 + cameraPosition;

        if (isEyeInWater == 1) {
            if (n.y > 0.0) n = -n;
            vec3 T = refract(wdir, n, 1.33);
            if (dot(T, T) < 1e-4) {
                color = waterInscatter(16.0, eyeSky, tint, muL) * 1.5;
            } else {
                float F = schlick(dot(V, n), 0.02);
                vec2 ruv = clamp(uv + (T.xz - wdir.xz) * 0.05, 0.0, 1.0);
                color = texture(colortex0, ruv).rgb * (1.0 - F) + waterInscatter(8.0, eyeSky, tint, muL) * F;
            }
        } else {

            bool sideFace = abs(n.y) < 0.5;
            vec2 ruv = uv;
            float pathIn = d1 >= 1.0 ? 64.0 : length(screenToView(vec3(uv, d1)) - vp0);
            float dist = pathIn;
            #ifdef WATER_REFRACTION

            vec3 nr = sideFace ? n : normalize(mix(vec3(0.0, 1.0, 0.0), n, clamp(REFRACTION_STRENGTH, 0.0, 1.25)));
            vec3 T = refract(wdir, nr, 1.0 / 1.33);
            if (dot(T, T) > 1e-4 && d1 < 1.0) {
                vec3 Tv = mat3(gbufferModelView) * T;
                float maxLen = min(pathIn * 3.0 + 2.0, 32.0);
                const int RSTEPS = 20;
                float stepL = maxLen / float(RSTEPS);
                float tPrev = 0.0, t = stepL * (0.5 + 0.5 * dither);
                bool hit = false;
                for (int i = 0; i < RSTEPS; i++) {
                    vec3 sp = viewToScreen(vp0 + Tv * t);
                    if (outsideScreen(sp.xy)) break;
                    if (sp.z >= texture(depthtex1, sp.xy).r) { hit = true; break; }
                    tPrev = t;
                    t += stepL;
                }
                if (hit) {
                    float a = tPrev, b = t;
                    for (int j = 0; j < 6; j++) {
                        float m = (a + b) * 0.5;
                        vec3 sm = viewToScreen(vp0 + Tv * m);
                        if (sm.z >= texture(depthtex1, sm.xy).r) b = m; else a = m;
                    }
                    vec3 sb = viewToScreen(vp0 + Tv * b);

                    if (texture(colortex5, sb.xy).z > 0.75 && texture(depthtex1, sb.xy).r > d0) { ruv = sb.xy; dist = b; }
                }
            }
            #endif
            if (sideFace) {

                float thick = min(pathIn, 1.0);
                #ifdef RT_REFLECTIONS
                vec3 vpW = toVoxelSpace(pp0) - n * 0.02;
                vec3 eW = min(vpW, vec3(voxelSize()) - vpW);
                if (min(eW.x, min(eW.y, eW.z)) > 1.0) {
                    traceVoxels(vpW, wdir, min(pathIn, 16.0), ivec3(-1000), 32, false, true);
                    thick = clamp(rtWaterLen, 0.2, min(pathIn, 16.0));
                }
                #endif
                dist = min(dist, thick);
            }
            vec3 under = texture(colortex0, ruv).rgb;
            under = under * exp(-WATER_ABSORB * dist) + waterInscatter(dist, skyL, tint, muL);

            vec3 R = reflect(wdir, n);

            if (!sideFace) R.y = max(R.y, 0.01);
            R = normalize(R);
            vec3 refl = traceReflection(vp0, R, skyL, dither);

            float F = schlick(dot(n, V), 0.02);
            color = mix(under, refl, F);

            #ifdef WORLD_OVERWORLD

            float crest = sideFace ? 0.0 : saturate(waveHeight(wpos.xz, frameTimeCounter * WAVE_SPEED, 6) * 2.2 - 0.9);
            float through = pow(saturate(muL * 0.6 + 0.4), 4.0);
            color += directLight * vec3(0.06, 0.42, 0.36) * crest * through * skyL * 0.12 * (1.0 - F)
                   * smoothstep(0.0, 0.2, getLightDir().y + 0.05);
            #endif

            float oceanFoam = texture(colortex2, uv).a;
            vec3 foamLit = ambientLight * (0.35 + 0.65 * skyL) + directLight * skyL * 0.55 * saturate(getLightDir().y * 2.0 + 0.15) + MIN_LIGHT;
            if (oceanFoam > 0.002) color = mix(color, vec3(0.76, 0.81, 0.84) * foamLit, oceanFoam);

            #ifdef SURF_FOAM

            vec3 floorPos = d1 >= 1.0 ? pp0 - vec3(0.0, 64.0, 0.0) : uncurveWorld(viewToPlayer(screenToView(vec3(uv, d1))));
            float depthV = max(pp0.y - floorPos.y, 0.0);
            float sea = saturate((t5.z - 0.8) / 0.19);
            float H = sea * (0.05 + 0.1 * WAVE_HEIGHT) + 0.01;
            float tf = frameTimeCounter * WAVE_SPEED;
            float swell = waterSwell(wpos.xz, tf) * 0.5 + 0.5;
            float lagged = waterSwell(wpos.xz - waterWind() * 0.9, tf) * 0.5 + 0.5;
            float breakZone = 1.0 - smoothstep(0.8 * H, 1.6 * H + 0.04, depthV);
            float surf = breakZone * (smoothstep(0.55, 0.85, swell) + 0.5 * smoothstep(0.4, 0.9, lagged));
            float swash = (1.0 - smoothstep(0.0, 0.06 + 0.1 * swell, depthV)) * smoothstep(0.1, 0.5, H * 4.0);
            float shoreAmount = sideFace ? 0.0 : (surf * 0.7 + swash * 0.5) * smoothstep(0.02, 0.15, H) * FOAM_AMOUNT;
            shoreAmount *= 1.0 - smoothstep(24.0, 64.0, length(pp0));
            float shore = foamCover(wpos.xz, shoreAmount, length(fwidth(wpos.xz)), frameTimeCounter, waterWind() * frameTimeCounter * 0.03);
            if (shore > 0.002) color = mix(color, vec3(0.76, 0.81, 0.84) * foamLit, shore);
            oceanFoam = max(oceanFoam, shore);
            #endif

            #ifdef WORLD_OVERWORLD
            vec3 L = getLightDir();
            vec3 sh = vec3(smoothstep(0.85, 0.95, skyL));
            #if defined USE_SHADOWS && defined RT_REFLECTIONS

            float sunCov;
            vec3 s = rtSunShadow(pp0, vec3(0.0, 1.0, 0.0), vec3(0.0, 0.05, 0.0), L, dither, sunCov);
            sh = mix(sh, s, sunCov);
            #endif
            #ifdef USE_CLOUD_SHADOWS
            sh *= cloudShadow(pp0 + cameraPosition);
            #endif

            float glintRough = 0.02 + length(pp0) * 0.0005;
            color += min(ggxSpecular(n, V, L, glintRough, vec3(0.02)) * directLight * sh, vec3(60.0)) * (1.0 - oceanFoam);
            #endif
            #ifdef USE_FLASHLIGHT

            vec3 fL;
            vec3 fE = flashlightLight(pp0, n, fL);
            float fN = saturate(dot(n, fL));
            if (fN > 0.0) {
                color += min(ggxSpecular(n, V, fL, 0.03, vec3(0.02)) * fE / fN, vec3(60.0)) * (1.0 - oceanFoam);
                color += vec3(0.76, 0.81, 0.84) * fE * oceanFoam;
            }
            #endif
        }
    } else if (t5.z > 0.25 && d0 < 1.0) {

        vec3 n = decodeNormal(t5.xy);
        vec3 R = reflect(wdir, n);
        float F = schlick(dot(n, V), 0.04);
        color = mix(color, traceReflection(vp0, R, t5.w, dither), F * 0.9);
    } else if (d0 < 1.0) {

        vec4 m = texture(colortex2, uv);
        int mat = int(m.r * 255.0 + 0.5);
        float s = m.g;
        bool metal = m.b >= 229.5 / 255.0;
        if (s > 0.4 && mat != 254 && mat != 250 && mat != 0) {
            vec4 c1 = texture(colortex1, uv);
            vec3 n = decodeNormal(c1.xy);

            float a = (1.0 - s) * (1.0 - s);
            vec2 xi = vec2(fract(dither + float(frameCounter & 15) * 0.618034), fract(dither * 7.31 + 0.37));
            float cosT = sqrt((1.0 - xi.x) / (1.0 + (a * a - 1.0) * xi.x));
            float sinT = sqrt(max(1.0 - cosT * cosT, 0.0));
            vec3 t1 = normalize(cross(n, abs(n.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
            vec3 t2 = cross(n, t1);
            vec3 Hm = normalize(t1 * (sinT * cos(TAU * xi.y)) + t2 * (sinT * sin(TAU * xi.y)) + n * cosT);
            vec3 R = reflect(wdir, Hm);
            if (dot(R, n) <= 0.0) R = reflect(wdir, n);
            vec3 refl = traceReflection(vp0, R, c1.w, dither);
            float w = smoothstep(0.4, 0.85, s);
            float NdotV = saturate(dot(n, V));

            vec3 tint = metal ? color / max(max(color.r, color.g), max(color.b, 1e-4)) : vec3(1.0);
            bool known = metal && m.b * 255.0 < 237.5;
            vec3 f0 = metal ? (known ? labMetalF0(m.b * 255.0, vec3(0.0)) : tint * 0.9) : vec3(max(m.b, 0.04));
            vec3 F = f0 + (1.0 - f0) * pow(1.0 - NdotV, 5.0) * s;
            if (metal) tint = vec3(1.0);
            color = mix(color, refl * tint, F * w);
        }
    }

    #ifdef USE_MPM

    if (mpmActive() && mpmCount.y > 0 && isEyeInWater == 0) {
        vec3 bmin = mpmOrigin() - cameraPosition, bmax = bmin + mpmSize();
        vec3 inv = 1.0 / mix(wdir, vec3(1e-6), lessThan(abs(wdir), vec3(1e-6)));
        vec3 ta = (bmin) * inv, tb = (bmax) * inv;
        vec3 tn = min(ta, tb), tf = max(ta, tb);
        float t0 = max(max(max(tn.x, tn.y), tn.z), 0.05), t1 = min(min(tf.x, tf.y), tf.z);
        float tEnd = min(t1, d0 >= 1.0 ? 1e4 : length(pp0));
        if (t0 < tEnd) {
            const float stepL = MPM_DX * 0.35;
            float t = t0 + stepL * dither;
            vec3 Ls = getLightDir();
            float mu = dot(wdir, Ls);

            float skyS = eyeSky;
            float sunS = smoothstep(0.85, 0.95, skyS) * smoothstep(-0.05, 0.1, Ls.y);
            #ifdef USE_CLOUD_SHADOWS
            sunS *= cloudShadow(cameraPosition);
            #endif
            vec3 waterTint = t5.z > 0.75 ? toLinear(texture(colortex2, uv).rgb) : vec3(0.05, 0.18, 0.78);
            vec3 foamLit = ambientLight * (0.35 + 0.65 * skyS) + directLight * sunS * 0.55 + MIN_LIGHT;
            float trans = 1.0;
            vec3 spray = vec3(0.0);
            for (int i = 0; i < 180 && t < tEnd; i++) {
                vec3 wp = cameraPosition + wdir * t;
                if (wp.y > mpmColumns(wp.xz).y) {

                    if (wdir.y > 0.0) break;
                    t += stepL;
                    continue;
                }
                float dens = mpmSprayDensity(wp);
                if (dens > 0.15) {

                    vec3 e = vec3(MPM_DX * 0.5, 0.0, 0.0);
                    vec3 grad = vec3(mpmSprayDensity(wp + e.xyy) - mpmSprayDensity(wp - e.xyy), mpmSprayDensity(wp + e.yxy) - mpmSprayDensity(wp - e.yxy),
                                     mpmSprayDensity(wp + e.yyx) - mpmSprayDensity(wp - e.yyx));
                    vec3 nS = length(grad) > 1e-5 ? -normalize(grad) : -wdir;
                    if (dot(nS, wdir) > 0.0) nS = -nS;

                    float thick = 0.0, tt = t;
                    for (int j = 0; j < 28; j++) {
                        tt += stepL;
                        if (tt > tEnd) break;
                        float dj = mpmSprayDensity(cameraPosition + wdir * tt);
                        if (dj < 0.08) break;
                        thick += stepL * min(dj, 1.0);
                    }
                    thick = max(thick, MPM_DX * 0.3);
                    vec3 vpS = (gbufferModelView * vec4(wdir * t, 1.0)).xyz;
                    float F = schlick(saturate(dot(nS, V)), 0.02);

                    vec3 reflS = traceReflection(vpS, reflect(wdir, nS), skyS, dither);

                    vec2 ruvS = uv;
                    vec3 Ts = refract(wdir, nS, 1.0 / 1.33);
                    if (dot(Ts, Ts) > 1e-4) {
                        float behindL = d0 >= 1.0 ? 4.0 : clamp(length(pp0) - t, 0.2, 4.0);
                        vec3 sBent = viewToScreen(vpS + mat3(gbufferModelView) * Ts * behindL);
                        vec3 sStraight = viewToScreen(vpS + mat3(gbufferModelView) * wdir * behindL);
                        ruvS = clamp(uv + (sBent.xy - sStraight.xy) * clamp(REFRACTION_STRENGTH, 0.0, 1.5), 0.0, 1.0);
                    }
                    vec3 under = texture(colortex0, ruvS).rgb * exp(-WATER_ABSORB * thick) + waterInscatter(thick, skyS, waterTint, mu);
                    vec3 sheet = mix(under, reflS, F);
                    #ifdef WORLD_OVERWORLD
                    sheet += min(ggxSpecular(nS, V, Ls, 0.03, vec3(0.02)) * directLight * sunS, vec3(60.0));
                    #endif

                    sheet = mix(sheet, vec3(0.76, 0.81, 0.84) * foamLit, 0.02 + 0.12 * (1.0 - smoothstep(0.15, 0.5, dens)));
                    spray += trans * sheet;
                    trans = 0.0;
                    break;
                }
                if (dens > 0.004) {

                    float a = 1.0 - exp(-dens * 9.0 * stepL);
                    ivec3 cell = ivec3(floor((wp - mpmOrigin()) / MPM_DX));
                    uvec3 hv = uvec3(cell + 4096) * uvec3(1664525u, 1013904223u, 2654435761u) + uvec3(uint(frameCounter >> 2));
                    hv.x += hv.y * hv.z; hv.y += hv.z * hv.x; hv.z += hv.x * hv.y;
                    hv ^= hv >> 16u;
                    vec3 nr = normalize(vec3(hv & 1023u) / 511.5 - 1.0);
                    float glint = pow(saturate(dot(reflect(wdir, nr), Ls)), 600.0) * 60.0;
                    vec3 drop = (ambientLight * 0.35 + MIN_LIGHT) * (0.6 + 0.4 * skyS)
                              + directLight * sunS * (0.08 + 0.6 * pow(saturate(mu), 12.0) + glint);
                    spray += trans * a * drop;
                    trans *= 1.0 - a * 0.4;
                    if (trans < 0.02) break;
                }
                t += stepL;
            }
            color = color * trans + spray;
        }
    }
    #endif

    float dist = length(pp0);
    if (isEyeInWater == 1) {
        float fd = d0 >= 1.0 ? 48.0 : dist;
        color = color * exp(-WATER_ABSORB * fd) + waterInscatter(fd, eyeSky, vec3(0.05, 0.18, 0.78), dot(wdir, getLightDir()));
    } else if (isEyeInWater == 2) {
        color = mix(color, vec3(1.0, 0.3, 0.05) * 2.0, 1.0 - exp(-dist * 1.5));
    } else if (isEyeInWater == 3) {
        color = mix(color, vec3(0.6, 0.7, 0.8) * (ambientLight + 0.05), 1.0 - exp(-dist * 1.2));
    } else if (d0 < 1.0 || lodPixel) {

        float border = smoothstep(far * 0.7, far, length(pp0.xz));
        #if defined VOXY || defined DISTANT_HORIZONS
        border = 0.0;
        #endif
        #if defined WORLD_OVERWORLD
        float sunY = getSunDir().y;
        float lowSun = saturate(1.0 - abs(sunY) * 4.0);
        float heightF = exp(-max(pp0.y + cameraPosition.y - 70.0, 0.0) / 60.0);
        float density = FOG_DENSITY * 0.0012 * (1.0 + rainStrength * 6.0 + lowSun * 1.5) * heightF;
        #ifdef BIOME_FOG

        density *= 1.0 + saturate(biomeHumidity) * saturate(biomeHeat) * 1.3;
        #endif
        float fogAmt = max(1.0 - exp(-dist * density), border);
        vec3 fogCol = getSky(normalize(vec3(wdir.x, max(wdir.y, 0.02), wdir.z)), false);
        fogCol *= mix(0.15, 1.0, eyeSky * eyeSky);
        #ifdef BIOME_FOG

        float dusty = saturate((biomeHeat - 1.2) * 2.0) * (1.0 - saturate(biomeHumidity * 3.0));
        fogCol = mix(fogCol, vec3(1.0, 0.8, 0.58) * luminance(fogCol) * 1.1, dusty * 0.45);
        fogCol = mix(fogCol, vec3(0.92, 0.95, 1.0) * luminance(fogCol) * 1.1, snowyBiome * 0.3);
        #endif
        color = mix(color, fogCol, fogAmt);
        #elif defined WORLD_NETHER
        float fogAmt = max(1.0 - exp(-dist * 0.02 * FOG_DENSITY), border);
        color = mix(color, toLinear(fogColor) * 0.35, fogAmt);
        #else
        float fogAmt = max(1.0 - exp(-dist * 0.006 * FOG_DENSITY), border);
        color = mix(color, getSky(wdir, false), fogAmt);
        #endif
    }
    #ifdef USE_FLASHLIGHT

    {
        float scatter = isEyeInWater == 1 ? 0.12 : (isEyeInWater == 0 ? 0.003 + rainStrength * 0.03 + 0.002 * FOG_DENSITY : 0.0);
        vec3 rayEnd = d0 >= 1.0 && !lodPixel ? wdir * 48.0 : pp0;
        color += flashlightBeamInAir(rayEnd, scatter);
    }
    #endif
    color *= mix(1.0, exp(-dist * 0.5), blindness);

    out0 = vec4(sanitize(color), 1.0);
}
#endif
