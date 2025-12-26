#include <metal_stdlib>

using namespace metal;

#define PI 3.141592653589323

struct GlassLozengeVertexIn {
    vector_float4 position;
    vector_float2 textureCoordinate;
};

struct GlassLozengeVertexOut {
    vector_float4 position [[ position ]];
    vector_float2 textureCoordinate;
};

vertex GlassLozengeVertexOut glassVertex(const device GlassLozengeVertexIn * vertices [[ buffer(0) ]],
                                         uint vid [[ vertex_id ]])
{
    GlassLozengeVertexOut outVertex;
    GlassLozengeVertexIn inVertex = vertices[vid];
    outVertex.position = inVertex.position;
    outVertex.textureCoordinate = inVertex.textureCoordinate;
    return outVertex;
}

struct Shared {
    /** Epsilon value in UV units */
    float EPS;

    /** Current point (centered UV coord) */
    float2 p;
    /** Current point (UV coord) */
    float2 UV;

    /** SDF with gradients */
    float3 f;
    /** SDF value at current point */
    float d;
    /** Unnormalized normal */
    float2 norm;

    // Refraction area size
    float refractionDim;

    // Refraction vector magnitude (base)
    float refractionMag;
};

float lerp(float minV, float maxV, float v) {
    return clamp((v - minV) / (maxV - minV), 0., 1.);
}

float3 blendScreen(float3 a, float3 b) {
    return 1. - (1. - a) * (1. - b);
}

float3 blendLighten(float3 a, float3 b) {
    return max(a, b);
}

float2 screenToUV(float2 screen, float2 res) {
    return (screen.xy - .5 * res.xy) / res.y;
}

float3 sdgBox( float2 p, float2 b, float4 ra ) {
    ra.xy   = (p.x>0.0)?ra.xy : ra.zw;
    float r = (p.y>0.0)?ra.x  : ra.y;

    float2 w = abs(p)-(b-r);
    float2 s = float2(p.x<0.0?-1:1,p.y<0.0?-1:1);

    float  g = max(w.x,w.y);
    float2 q = max(w,0.0);
    float  l = length(q);

    return float3(   (g>0.0)?l-r: g-r,
                s*((g>0.0)?q/l : ((w.x>w.y)?float2(1,0):float2(0,1))));
}

// https://www.shadertoy.com/view/wlcXD2
float3 sdgBox( float2 p, float2 b, float r ) {
    return sdgBox(p, b, float4(r));
}

/**
 * Loads post-refraction pixels from the source texture.
 */
float3 refractionLayer(float3 col, Shared s, texture2d<float, access::sample> texture, sampler samp) {
    const float REFR_DIM = s.refractionDim; // Refraction area size
    const float REFR_MAG = s.refractionMag; // Refraction vector magnitude (base)
    const float REFR_ABERRATION = 5.; // Refraction aberration coeff. (0 = none, 10 = unrealistic)
    const float3 REFR_IOR = float3(1.51, 1.52, 1.53);        // IOR values for red, green, blue

    // boundary = 0 means no refraction. boundary 1 = max refraction. [linear]
    // we dont want refraction in the center.
    float boundary = lerp(-REFR_DIM, s.EPS, s.d);
    boundary = mix(boundary, 0., smoothstep(0.,s.EPS,s.d));

    float cosBoundary = 1.0 - cos(boundary * PI / 2.0);

    float3 ior = mix(
        float3(REFR_IOR.g),
        REFR_IOR,
        REFR_ABERRATION
    );

    float2 offset = -s.norm * REFR_MAG;

    float3 ratios = pow(float3(cosBoundary), ior);
    float2 offsetR = offset * ratios.r;
    float2 offsetG = offset * ratios.g;
    float2 offsetB = offset * ratios.b;

    float3 baseColor = texture.sample(samp, s.UV).rgb;

    float r = texture.sample(samp, s.UV + offsetR).r;
    float g = texture.sample(samp, s.UV + offsetG).g;
    float b = texture.sample(samp, s.UV + offsetB).b;
    float3 blurWarped = float3(r,g,b);

    return mix(baseColor, blurWarped, smoothstep(s.EPS, 0., s.d));
}

/**
 * Tint layer
 * Adds a background to glass content for legibility.
 * Adds edge lighting to improve separation.
 * Adds reflections from nearby.
 */
float3 tintLayer(float3 col, float4 tintColor, Shared s, texture2d<float, access::sample> texture, sampler samp) {
    const float EDGE_DIM = .003;     // Edge area size
    const float REFL_OFFSET_MIN = 0.035;
    const float REFL_OFFSET_MAG = 0.005;
    const float2 RIM_LIGHT_VEC = normalize(float2(-1., 1.)); // Rim light angle
    const float4 RIM_LIGHT_COLOR = float4(float3(1.), .15);  // Rim light color

    // Apply tint to interior. Linear color mix.
    float interior = smoothstep(s.EPS, 0., s.d);
    col = mix(col, tintColor.rgb, tintColor.a * interior);

    float a = smoothstep(s.EPS, 0., s.d);
    float b = lerp(-EDGE_DIM, 0., s.d);
    float edge = min(a, b);

    // Non-linear to bias towards edges.
    float cosEdge = 1. - cos(edge * PI / 2.);

    // modified diffuse lighting eqn.
    // abs to mirror on both sides.
    float rimLightIntensity = abs(dot(normalize(s.norm), RIM_LIGHT_VEC));
    float3 rimLight = RIM_LIGHT_COLOR.rgb * RIM_LIGHT_COLOR.a * rimLightIntensity;

    // Sample a reflection based on closeness to edge.
    float2 reflectionOffset = (REFL_OFFSET_MIN + REFL_OFFSET_MAG * cosEdge) * s.norm;

    float3 reflectionColor = clamp(texture.sample(samp, s.UV + reflectionOffset).rgb, 0., 1.);
    reflectionColor = mix(reflectionColor, tintColor.rgb, tintColor.a);

    float3 mergedEdgeColor = blendScreen(rimLight, reflectionColor);

    float3 edgeColor = blendLighten(col, mergedEdgeColor);
    return mix(col, edgeColor, cosEdge);
}

fragment float4 glassFragment(GlassLozengeVertexOut vertexIn [[stage_in]],
                              texture2d<float, access::sample> sourceTexture [[texture(0)]],
                              sampler sourceSampler [[sampler(0)]],
                              constant float & cornerRadius [[buffer(0)]],
                              constant float4 & tintColor [[buffer(1)]],
                              constant float & refractionDim [[buffer(2)]],
                              constant float & refractionMag [[buffer(3)]])
{
    const float EPS_PIX = 2.;

    float2 uv = vertexIn.textureCoordinate;
    float2 textureSize = float2(sourceTexture.get_width(), sourceTexture.get_height());

    float EPS = EPS_PIX / textureSize.y;
    float aspect = textureSize.x / textureSize.y;

    float2 p = screenToUV(uv * textureSize, textureSize);
    float3 f = sdgBox(p, float2(aspect * 0.5, 0.5), cornerRadius / textureSize.y);

    Shared shared = Shared { EPS, p, uv, f, f.x, f.yz, refractionDim, refractionMag };

    float3 col = float3(0.0);

    // draw rect and tint
    col = refractionLayer(col, shared, sourceTexture, sourceSampler);
    col = tintLayer(col, tintColor, shared, sourceTexture, sourceSampler);

    return float4(col, 1.0);
}
