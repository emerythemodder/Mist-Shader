ivec2 rtHalfOffset() {
    const ivec2 o[4] = ivec2[4](ivec2(0, 0), ivec2(1, 1), ivec2(1, 0), ivec2(0, 1));
    return o[frameCounter & 3];
}
ivec2 rtHalfSource(ivec2 h) { return min(h * 2 + rtHalfOffset(), ivec2(viewWidth, viewHeight) - 1); }
