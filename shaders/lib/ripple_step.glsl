#define RIPPLE_DX (1.0 / RIPPLE_CELLS)
#define RIPPLE_G 9.81

float rippleHat(float r2, float sigma2) {
    float q = r2 / sigma2;
    return (1.0 - q) * exp(-q);
}

float rippleNoise(vec2 p, float t) {
    return mix(valueNoise(p + vec2(t * 0.71, -t * 0.37)), valueNoise(p * 1.7 - vec2(t * 0.53, t * 0.91) + 17.0), 0.5) * 2.0 - 1.0;
}

struct RippleBody {
    vec2 a, b;
    vec2 aPrev, bPrev;
    vec2 halfSize;
    vec2 dir;
    vec2 vel;
    float amount;
    float speed;
    float swim;
    float dt;
};

RippleBody rippleBody(vec3 eye, vec3 prevEye, float level, float time, float dt) {
    RippleBody b;
    b.dt = max(dt, 1e-3);
    b.vel = (eye.xz - prevEye.xz) / b.dt;
    b.speed = min(length(b.vel), 12.0);
    b.dir = b.speed > 0.05 ? b.vel / length(b.vel) : vec2(1.0, 0.0);
    float feet = eye.y - 1.62;
    float w = level - feet;
    b.amount = smoothstep(0.0, 0.12, w) * (1.0 - smoothstep(1.85, 2.2, w));
    b.swim = smoothstep(1.3, 1.6, w);
    float legs = 1.0 - smoothstep(0.75, 0.95, w);
    vec2 across = vec2(-b.dir.y, b.dir.x);

    float stride = 0.24 * saturate(b.speed / 1.5) * legs;
    float cadence = 3.14159 * clamp(b.speed, 0.6, 4.0) / 0.6;
    float s = sin(time * cadence), sPrev = sin((time - dt) * cadence);
    float sep = 0.11 * legs;
    b.a = eye.xz + across * sep + b.dir * stride * s;
    b.b = eye.xz - across * sep - b.dir * stride * s;
    b.aPrev = prevEye.xz + across * sep + b.dir * stride * sPrev;
    b.bPrev = prevEye.xz - across * sep - b.dir * stride * sPrev;
    b.halfSize = mix(mix(vec2(0.13, 0.19), vec2(0.55, 0.24), b.swim), vec2(0.09), legs);
    return b;
}

float rippleEllipse(vec2 p, vec2 c, vec2 dir, vec2 halfSize) {
    vec2 d = p - c;
    vec2 q = vec2(dot(d, dir), dot(d, vec2(-dir.y, dir.x))) / halfSize;
    return (length(q) - 1.0) * min(halfSize.x, halfSize.y);
}
float rippleBodyDist(RippleBody b, vec2 p, bool prev) {
    return min(rippleEllipse(p, prev ? b.aPrev : b.a, b.dir, b.halfSize),
               rippleEllipse(p, prev ? b.bPrev : b.b, b.dir, b.halfSize));
}

float entrainment(float speed) {
    float x = max(speed - 1.9, 0.0);
    return x * x;
}

vec2 rippleRingPos(RippleBody b, float k) {
    vec2 across = vec2(-b.dir.y, b.dir.x);
    bool side = mod(k, 2.0) > 0.5;
    vec2 p = (side ? b.a : b.b) + across * (side ? 1.0 : -1.0) * (b.halfSize.y + 0.04) - b.dir * 0.04;
    if (b.swim > 0.5) p = (b.a + b.b) * 0.5 + b.dir * 0.25 + across * (side ? 0.32 : -0.32);
    vec2 j = vec2(hash12(vec2(mod(k, 4096.0), 1.7)), hash12(vec2(mod(k, 4096.0), 8.3))) - 0.5;
    return p + j * 0.2;
}

vec4 rippleStep(vec2 pos, ivec2 cell, float dt, float time, RippleBody body, float occ, float displaced, vec4 splash, vec3 ring) {
    vec4 s = rsState(ivec2(0));
    float h = s.x, v = s.y, foam = s.z, occPrev = s.w;

    float push = RIPPLE_STRENGTH;

    float vd = rsVertical() / RIPPLE_DX;
    vec4 sn = rsState(ivec2(0, 1)), ss = rsState(ivec2(0, -1)), se = rsState(ivec2(1, 0)), sw = rsState(ivec2(-1, 0));

    float bih = 20.0 * v - 8.0 * (sn.y + ss.y + se.y + sw.y)
              + 2.0 * (rsState(ivec2(1, 1)).y + rsState(ivec2(-1, 1)).y + rsState(ivec2(1, -1)).y + rsState(ivec2(-1, -1)).y)
              + rsState(ivec2(0, 2)).y + rsState(ivec2(0, -2)).y + rsState(ivec2(2, 0)).y + rsState(ivec2(-2, 0)).y;

    float a = -RIPPLE_G * vd - 2.0 * h;
    v = (v + a * dt) * exp(-dt * 0.06) - 0.25 * bih * min(dt, 1.0 / 30.0);
    h = (h + v * dt) * exp(-dt * 0.02);

    float slope = length(vec2(se.x - sw.x, sn.x - ss.x)) / (2.0 * RIPPLE_DX) * 0.01;
    float newFoam = 0.0;

    newFoam += max(slope - 0.6, 0.0) * step(v, 0.0) * 1.2 * dt;

    vec2 drift = vec2(0.0);

    if (body.amount > 0.0) {
        float dNow = rippleBodyDist(body, pos, false), dPrev = rippleBodyDist(body, pos, true);

        float mNow = 1.0 - smoothstep(-0.05, 0.10, dNow), mPrev = 1.0 - smoothstep(-0.05, 0.10, dPrev);
        float depth = mix(1.0, 1.5, body.swim);
        h += (mNow - mPrev) * 4.0 * depth * push * body.amount;

        float vA = length(body.a - body.aPrev) / body.dt, vB = length(body.b - body.bPrev) / body.dt;
        vec2 rel = pos - (body.a + body.b) * 0.5;
        float front = smoothstep(-0.05, 0.08, dot(rel, body.dir));
        float rim = 1.0 - smoothstep(0.0, 0.07, abs(dNow));
        float cut = max(entrainment(vA) * (1.0 - smoothstep(0.0, 0.08, abs(rippleEllipse(pos, body.a, body.dir, body.halfSize)))),
                        entrainment(vB) * (1.0 - smoothstep(0.0, 0.08, abs(rippleEllipse(pos, body.b, body.dir, body.halfSize)))));

        newFoam += cut * (0.35 + 0.65 * front) * 0.12 * body.amount * dt;

        float behind = (1.0 - smoothstep(0.0, 0.22, dNow)) * (1.0 - front);
        if (behind > 0.0) {
            float eddy = rippleNoise(pos * 14.0, time * 9.0);
            v += eddy * behind * 18.0 * min(body.speed * body.speed, 9.0) * push * body.amount * dt;
        }

        drift = body.vel * 0.35 * (1.0 - smoothstep(0.05, 0.6, dNow)) * (1.0 - front * 0.7) * body.amount;

        if (body.swim > 0.0 && body.speed > 0.3) {
            vec2 across = vec2(-body.dir.y, body.dir.x);
            float ph = time * 6.0;
            for (int i = 0; i < 2; i++) {
                float gate = smoothstep(0.92, 1.0, sin(ph + 3.14159 * float(i)));
                vec2 c = (body.a + body.b) * 0.5 + body.dir * 0.5 + across * (i == 0 ? 0.38 : -0.38);
                vec2 dc = pos - c;
                v -= gate * rippleHat(dot(dc, dc), 0.006) * 260.0 * push * body.swim * dt;
                newFoam += gate * exp(-dot(dc, dc) / 0.006) * entrainment(body.speed + 1.0) * 0.12 * body.swim * dt;
            }
        }

        if (ring.z > 0.0) {
            vec2 dr = pos - ring.xy;

            v -= rippleHat(dot(dr, dr), 0.012) * 70.0 * ring.z * push;
        }

        if (rim > 0.0) v += rippleNoise(body.a * 3.0, time * 1.3) * rim * 6.0 * push * body.amount * dt;

        float inside = 1.0 - smoothstep(-0.04, -0.01, dNow);
        h *= 1.0 - inside * body.amount;
        v *= 1.0 - inside * body.amount;
    }

    float dOcc = occ - occPrev;
    h += displaced * push;
    newFoam += abs(dOcc) * step(0.15, abs(dOcc)) * 0.04;

    if (splash.z > 0.0) {
        float r = length(pos - splash.xy);
        if (splash.w < dt * 0.5) {

            h -= splash.z * 12.0 * push * rippleHat(r * r, 0.10);

            newFoam += splash.z * 0.9 * exp(-r * r / 0.2) * (0.75 + 0.5 * valueNoise(pos * 5.0));
        } else if (splash.w < 1.0) {

            float ring = exp(-pow((r - 0.5 - splash.w * 0.8) / 0.5, 2.0));
            float p = splash.z * ring * 2.0 * dt, fr = floor(time * 60.0);
            float drop = 0.0;
            if (ring > 0.01) {
                drop = hash13(vec3(vec2(cell), fr)) < p ? 1.0 : 0.0;
                float around = 0.0;
                for (int k = 0; k < 4; k++) {
                    ivec2 o = ivec2(k == 0 ? 1 : (k == 1 ? -1 : 0), k == 2 ? 1 : (k == 3 ? -1 : 0));
                    around += hash13(vec3(vec2(cell + o), fr)) < p ? 1.0 : 0.0;
                }
                v += (around * 0.25 - drop) * 70.0 * push;
            }
            newFoam += drop * 0.05;
        }
    }

    if (dot(drift, drift) > 1e-6) {

        vec2 back = -drift * dt / RIPPLE_DX;
        ivec2 o = ivec2(floor(back));
        vec2 f = back - vec2(o);
        o = clamp(o, ivec2(-5), ivec2(4));
        foam = mix(mix(rsState(o).z, rsState(o + ivec2(1, 0)).z, f.x),
                   mix(rsState(o + ivec2(0, 1)).z, rsState(o + ivec2(1, 1)).z, f.x), f.y);
    }
    float foamAvg = (sn.z + ss.z + se.z + sw.z) * 0.25;
    foam = mix(foam, foamAvg, 1.0 - exp(-dt * 0.6));
    foam += newFoam;

    float life = mix(0.5, 1.7, hash13(vec3(vec2(cell >> 2) * 0.37, 3.7)));
    foam *= exp(-dt / life);
    foam = max(foam - dt * 0.04, 0.0);

    float water = rsWater(ivec2(0)) * (1.0 - rsBlocked(ivec2(0)));
    h *= water;
    v *= water;
    foam *= water;

    return vec4(clamp(h, -40.0, 40.0), clamp(v, -800.0, 800.0), clamp(foam, 0.0, 1.5), occ);
}
