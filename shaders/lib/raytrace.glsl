float edgeFade(vec2 uv) {
    vec2 e = min(uv, 1.0 - uv);
    return saturate(min(e.x, e.y) * 10.0);
}

vec3 rayTraceSSR(vec3 viewPos, vec3 dir, float dither, sampler2D depthTex, out bool hit) {
    hit = false;
    float rayLen = far * 1.5;
    if (dir.z > 0.0) rayLen = min(rayLen, (-near * 1.01 - viewPos.z) / dir.z);
    vec3 endV = viewPos + dir * max(rayLen, 0.01);

    vec3 s0 = viewToScreen(viewPos);
    vec3 s1 = viewToScreen(endV);
    vec3 d = s1 - s0;

    float t = 1.0;
    if (abs(d.x) > 1e-6) t = min(t, ((d.x > 0.0 ? 1.0 : 0.0) - s0.x) / d.x);
    if (abs(d.y) > 1e-6) t = min(t, ((d.y > 0.0 ? 1.0 : 0.0) - s0.y) / d.y);
    d *= max(t, 0.0);

    vec3 stepV = d / float(SSR_STEPS);
    vec3 p = s0 + stepV * dither;
    vec3 prev = p;
    for (int i = 0; i < SSR_STEPS; i++) {
        prev = p;
        p += stepV;
        if (outsideScreen(p.xy)) break;
        float sd = texture(depthTex, p.xy).r;
        if (sd < 0.56 || sd >= 1.0) continue;
        if (p.z > sd) {
            float thick = linearizeDepth(p.z) - linearizeDepth(sd);
            float stepThick = abs(linearizeDepth(p.z) - linearizeDepth(prev.z));
            if (thick < max(stepThick * 1.5, 0.6)) {
                vec3 a = prev, b = p;
                for (int j = 0; j < 5; j++) {
                    vec3 m = (a + b) * 0.5;
                    if (m.z > texture(depthTex, m.xy).r) b = m; else a = m;
                }
                hit = true;
                return b;
            }
        }
    }
    return p;
}
