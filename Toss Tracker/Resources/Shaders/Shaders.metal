//
//  Shaders.metal
//  Toss Tracker
//
//  Created by Arthur Schiller on 14.09.24.
//

#include <metal_stdlib>
using namespace metal;

// Structure for the vertex output
struct VertexOut {
    float4 position [[position]];  // Clip space position for the vertex
    float2 texCoord;               // Texture coordinates to pass to the fragment shader
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    float4 positions[4] = {
        float4(-1.0, -1.0, 0.0, 1.0), // Bottom-left
        float4(1.0, -1.0, 0.0, 1.0),  // Bottom-right
        float4(-1.0, 1.0, 0.0, 1.0),  // Top-left
        float4(1.0, 1.0, 0.0, 1.0)    // Top-right
    };
    
    float2 texCoords[4] = {
        float2(0.0, 1.0),  // Bottom-left
        float2(1.0, 1.0),  // Bottom-right
        float2(0.0, 0.0),  // Top-left
        float2(1.0, 0.0)   // Top-right
    };
    
    VertexOut out;
    out.position = positions[vertexID];  // Set vertex position
    out.texCoord = texCoords[vertexID];  // Pass through texture coordinates
    return out;
}

/* This conversion method is copied from section 7.7.7 of the Metal Language Spec:( https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf ) */
static float srgbToLinear(float c) {
    if (c <= 0.04045)
        return c / 12.92;
    else
        return powr((c + 0.055) / 1.055, 2.4);
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> capturedImageTextureY [[ texture(1) ]],
                              texture2d<float, access::sample> capturedImageTextureCbCr [[ texture(2) ]]) {
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    
    float2 texCoord = in.texCoord;
    
    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate
    float4 ycbcr = float4(capturedImageTextureY.sample(colorSampler, texCoord).r,
                          capturedImageTextureCbCr.sample(colorSampler, texCoord).rg, 1.0);
    
    // Return converted RGB color
    float4 rgbColor = ycbcrToRGBTransform * ycbcr;
    
    rgbColor.r = srgbToLinear(rgbColor.r);
    rgbColor.g = srgbToLinear(rgbColor.g);
    rgbColor.b = srgbToLinear(rgbColor.b);
    
    return rgbColor;
}
