#ifndef MATERIALS_GLSL
#define MATERIALS_GLSL

struct Material {
    vec3 normalTS;
    float ao;
    float smoothness;
    float f0;
    float porosity;
    float sss;
    float emissive;
    bool hasSpecular;
};

Material decodeMaterial(vec4 nm, vec4 sp) {
    Material m;
    vec2 nxy = nm.xy * 2.0 - 1.0;
    float z = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
    m.normalTS = vec3(nxy, z);
    m.ao = 1.0;
    m.hasSpecular = dot(sp, sp) > 1e-6;
    #if PBR_FORMAT == 1

    m.normalTS = normalize(nm.xyz * 2.0 - 1.0);
    m.smoothness = sp.r;
    m.f0 = sp.g > 0.5 ? 238.0 / 255.0 : 0.04;
    m.porosity = 0.0;
    m.sss = 0.0;
    m.emissive = sp.b;
    #else

    if (abs(nm.b - (z * 0.5 + 0.5)) > 0.02 || nm.b > 0.995) m.ao = nm.b;
    m.smoothness = sp.r;
    m.f0 = sp.g;
    float b = sp.b * 255.0;
    m.porosity = b <= 64.5 ? b / 64.0 : 0.0;
    m.sss = b > 64.5 ? (b - 65.0) / 190.0 : 0.0;
    m.emissive = sp.a < 0.999 ? sp.a : 0.0;
    #endif
    return m;
}

vec3 labMetalF0(float g255, vec3 albedo) {
    int id = int(g255 + 0.5);
    if (id == 230) return vec3(0.531, 0.512, 0.496);
    if (id == 231) return vec3(1.000, 0.782, 0.344);
    if (id == 232) return vec3(0.913, 0.922, 0.924);
    if (id == 233) return vec3(0.549, 0.556, 0.554);
    if (id == 234) return vec3(0.955, 0.638, 0.538);
    if (id == 235) return vec3(0.632, 0.626, 0.641);
    if (id == 236) return vec3(0.673, 0.637, 0.585);
    if (id == 237) return vec3(0.972, 0.960, 0.915);
    return albedo;
}

vec3 rgbToHsv(vec3 c) {
    float mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b));
    float d = mx - mn;
    float h = 0.0;
    if (d > 1e-5) {
        if (mx == c.r) h = mod((c.g - c.b) / d, 6.0);
        else if (mx == c.g) h = (c.b - c.r) / d + 2.0;
        else h = (c.r - c.g) / d + 4.0;
        h /= 6.0;
    }
    return vec3(h, mx > 1e-5 ? d / mx : 0.0, mx);
}
float hueNear(float h, float centre, float width) {
    float d = abs(fract(h - centre + 0.5) - 0.5);
    return 1.0 - smoothstep(width * 0.6, width, d);
}

float oreFleck(int type, vec3 albedo, out float f0, out float gloss) {
    vec3 hsv = rgbToHsv(albedo);
    float fleck = 0.0;
    f0 = 0.04; gloss = 0.3;
    if (type == 0) {
        fleck = 1.0 - smoothstep(0.16, 0.26, hsv.z);
        f0 = 0.045; gloss = 0.62;
    } else if (type == 1) {
        fleck = smoothstep(0.12, 0.28, hsv.y) * hueNear(hsv.x, 0.07, 0.08);
        f0 = 0.06; gloss = 0.45;
    } else if (type == 2) {
        float metal = smoothstep(0.25, 0.45, hsv.y) * hueNear(hsv.x, 0.06, 0.07);
        float green = smoothstep(0.2, 0.4, hsv.y) * hueNear(hsv.x, 0.38, 0.1);
        fleck = max(metal, green);
        f0 = metal > green ? 234.0 / 255.0 : 0.05;
        gloss = metal > green ? 0.6 : 0.45;
    } else if (type == 3 || type == 8) {
        fleck = smoothstep(0.3, 0.5, hsv.y) * hueNear(hsv.x, 0.13, 0.07) * smoothstep(0.35, 0.55, hsv.z);
        f0 = 231.0 / 255.0; gloss = type == 3 ? 0.78 : 0.7;
    } else if (type == 4) {
        fleck = smoothstep(0.35, 0.55, hsv.y) * hueNear(hsv.x, 0.0, 0.06);
        f0 = 0.05; gloss = 0.62;
    } else if (type == 5) {
        fleck = smoothstep(0.3, 0.5, hsv.y) * hueNear(hsv.x, 0.62, 0.07);
        f0 = 0.045; gloss = 0.5;
    } else if (type == 6) {
        fleck = smoothstep(0.2, 0.4, hsv.y) * hueNear(hsv.x, 0.5, 0.08);
        f0 = 0.17; gloss = 0.95;
    } else if (type == 7) {
        fleck = smoothstep(0.3, 0.5, hsv.y) * hueNear(hsv.x, 0.38, 0.08);
        f0 = 0.05; gloss = 0.92;
    } else if (type == 9) {
        fleck = smoothstep(0.55, 0.75, hsv.z) * (1.0 - smoothstep(0.2, 0.4, hsv.y));
        f0 = 0.045; gloss = 0.88;
    } else if (type == 10) {
        fleck = smoothstep(0.35, 0.55, hsv.z);
        f0 = 0.05; gloss = 0.42;
    } else if (type == 11) {
        fleck = 1.0;
        f0 = 0.045; gloss = 0.8;
    }
    return saturate(fleck);
}

void oreHost(int type, vec3 albedo, out float f0, out float gloss) {
    vec3 hsv = rgbToHsv(albedo);
    f0 = 0.04;
    if (type == 8 || type == 9) gloss = 0.18;
    else if (type == 10) gloss = 0.3;
    else if (hsv.z < 0.35) gloss = 0.32;
    else gloss = 0.24;
}

bool integratedMaterial(int id, vec3 albedo, inout Material m) {
    if (id >= 10060 && id <= 10071) {
        float fF0, fSm, hF0, hSm;
        float fl = oreFleck(id - 10060, albedo, fF0, fSm);
        oreHost(id - 10060, albedo, hF0, hSm);
        m.smoothness = mix(hSm, fSm, fl);

        m.f0 = fF0 >= 229.5 / 255.0 ? (fl > 0.5 ? fF0 : hF0) : mix(hF0, fF0, fl);
        return true;
    }
    if (id == 10072) { m.f0 = 230.0 / 255.0; m.smoothness = 0.62; return true; }
    if (id == 10073) { m.f0 = 231.0 / 255.0; m.smoothness = 0.82; return true; }
    if (id == 10074) {
        float patina = smoothstep(0.15, 0.35, rgbToHsv(albedo).y) * hueNear(rgbToHsv(albedo).x, 0.45, 0.12);
        m.f0 = patina > 0.5 ? 0.04 : 234.0 / 255.0;
        m.smoothness = mix(0.7, 0.3, patina);
        return true;
    }
    if (id == 10075) { m.f0 = 238.0 / 255.0; m.smoothness = 0.55; return true; }
    if (id == 10076) { m.f0 = 0.17; m.smoothness = 0.9; return true; }
    if (id == 10077) { m.f0 = 0.05; m.smoothness = 0.88; return true; }
    if (id == 10078) { m.f0 = 0.045; m.smoothness = 0.7; return true; }
    if (id == 10079) { m.f0 = 0.018; m.smoothness = 0.92; return true; }
    return false;
}

#ifdef FSH
int pomSource = 0;
float pomAvgLum = 0.5;
float pomContrast = 3.0;
float pomDepthScale = 1.0;

vec2 pomWrap(vec2 local, vec4 rect) { return rect.xy + fract(local) * rect.zw; }

float pomHeight(sampler2D albedoTex, sampler2D heightTex, vec2 uv, vec2 dx, vec2 dy) {
    if (pomSource == 1) return textureGrad(heightTex, uv, dx, dy).a;

    float l = dot(textureGrad(albedoTex, uv, dx, dy).rgb, vec3(0.2126, 0.7152, 0.0722));
    return saturate(1.0 + min((l - pomAvgLum) * pomContrast, 0.0));
}

vec2 parallaxUv(vec2 uv, vec4 rect, vec3 viewTS, vec3 lightTS, float fade, sampler2D albedoTex, sampler2D heightTex,
                out float shadow, out float depth) {
    shadow = 1.0;
    depth = 0.0;
    vec2 dx = dFdx(uv), dy = dFdy(uv);
    if (pomSource == 0 || fade <= 0.0 || viewTS.z <= 0.02 || rect.z <= 0.0) return uv;
    vec2 local = (uv - rect.xy) / rect.zw;
    float steps = mix(float(POM_STEPS), float(POM_STEPS) * 0.25, viewTS.z) * fade;
    float stepH = 1.0 / max(steps, 4.0);

    vec2 shift = -viewTS.xy / viewTS.z * POM_DEPTH * pomDepthScale * fade;
    vec2 stepUv = shift * stepH;
    float h = 1.0;
    float th = pomHeight(albedoTex, heightTex, uv, dx, dy);
    vec2 p = local;
    float prevH = h;
    for (int i = 0; i < POM_STEPS; i++) {
        if (h <= th) break;
        prevH = h;
        p += stepUv;
        h -= stepH;
        th = pomHeight(albedoTex, heightTex, pomWrap(p, rect), dx, dy);
    }

    vec2 pa = p - stepUv;
    float ha = prevH, hb = h;
    for (int i = 0; i < 6; i++) {
        vec2 pm = (pa + p) * 0.5;
        float hm = (ha + hb) * 0.5;
        if (hm <= pomHeight(albedoTex, heightTex, pomWrap(pm, rect), dx, dy)) { p = pm; hb = hm; }
        else { pa = pm; ha = hm; }
    }
    h = hb;
    depth = (1.0 - h) * POM_DEPTH * pomDepthScale;

    if (lightTS.z > 0.02) {
        vec2 lStep = lightTS.xy / lightTS.z * POM_DEPTH * pomDepthScale * stepH * 1.5;
        float lh = h;
        vec2 q = p;
        for (int i = 0; i < 16; i++) {
            q += lStep;
            lh += stepH * 1.5;
            if (lh >= 1.0) break;
            float sh = pomHeight(albedoTex, heightTex, pomWrap(q, rect), dx, dy);
            shadow = min(shadow, saturate(1.0 - (sh - lh) * 12.0));
        }
    }
    return pomWrap(p, rect);
}

vec3 pomNormal(sampler2D albedoTex, sampler2D heightTex, vec2 uv, vec4 rect, vec2 texels) {
    vec2 local = (uv - rect.xy) / rect.zw;
    vec2 d = 1.0 / max(texels, vec2(1.0));
    vec2 z = vec2(0.0);
    float hx1 = pomHeight(albedoTex, heightTex, pomWrap(local + vec2(d.x, 0.0), rect), z, z);
    float hx0 = pomHeight(albedoTex, heightTex, pomWrap(local - vec2(d.x, 0.0), rect), z, z);
    float hy1 = pomHeight(albedoTex, heightTex, pomWrap(local + vec2(0.0, d.y), rect), z, z);
    float hy0 = pomHeight(albedoTex, heightTex, pomWrap(local - vec2(0.0, d.y), rect), z, z);

    vec2 slope = vec2(hx1 - hx0, hy1 - hy0) * POM_DEPTH * pomDepthScale / (2.0 * d);
    slope = clamp(slope, -1.5, 1.5);
    return normalize(vec3(-slope, 1.0));
}
#endif
#endif
