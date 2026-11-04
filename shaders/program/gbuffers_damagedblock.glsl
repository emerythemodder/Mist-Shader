#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/common.glsl"

#ifdef VSH
    #define VARY out
#else
    #define VARY in
#endif

VARY vec2 texcoord;
VARY vec4 glcolor;

#ifdef VSH
void main() {
    gl_Position = taaClipPosition((gbufferModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz);
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
}
#endif

#ifdef FSH
uniform sampler2D gtexture;
layout(location = 0) out vec4 out0;

void main() {
    vec4 c = texture(gtexture, texcoord) * glcolor;
    if (c.a < 0.1) discard;
    out0 = vec4(c.rgb, 1.0);
}
#endif
