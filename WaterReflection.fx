//=============================================================================
// WaterReflection.fx
// 显式语义源水面反射 - MonoGame OpenGL / Shader Model 3.0
//=============================================================================

float4x4 MatrixTransform;

float2 WaterWorldOrigin;
float2 WaterWorldSize;
float2 SemanticWorldOrigin;
float2 SemanticWorldSize;
float2 ShoreSourceWorldOrigin;
float2 ShoreSourceWorldSize;
float WaterMaximumDistance;
float ShoreSampleHeight;
float ShoreOpacity;
float ShoreOcclusion;
float WaterReflectionIntensity;

// SpriteBatch 将 Water Mask 绑定到 s0。
sampler2D WaterMaskSampler : register(s0);

texture SemanticTexture;
sampler2D SemanticSampler : register(s1) = sampler_state
{
    Texture = <SemanticTexture>;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
    AddressU = Clamp;
    AddressV = Clamp;
};

texture ShoreSourceTexture;
sampler2D ShoreSourceSampler : register(s2) = sampler_state
{
    Texture = <ShoreSourceTexture>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct VSInput
{
    float4 Position : POSITION0;
    float4 Color : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

struct VSOutput
{
    float4 Position : SV_POSITION;
    float4 Color : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

VSOutput WaterSpriteVS(VSInput input)
{
    VSOutput output;
    output.Position = mul(input.Position, MatrixTransform);
    output.Color = input.Color;
    output.TexCoord = input.TexCoord;
    return output;
}

float4 WaterReflectionBasePS(VSOutput input) : COLOR
{
    float2 uv = input.TexCoord;
    // R=原版可见水面，G=连续水体，B=到水线的归一化距离。
    float4 mask = tex2D(WaterMaskSampler, uv);
    float coverage = mask.r * mask.g;
    clip(coverage - 0.001);

    float2 worldPosition = WaterWorldOrigin + uv * WaterWorldSize;
    float shoreEligible = step(0.75, mask.a);

    float maximumDistance = max(WaterMaximumDistance, 1.0);
    float distanceFromWaterline = mask.b * maximumDistance;
    float found = mask.g * (1.0 - step(0.995, mask.b));
    float edgeWorldY = worldPosition.y - distanceFromWaterline;

    // 普通水岸只允许从精确水线上方一个 Tile 内读取显式岸壁源。
    // 此阶段只生成几何正确的干净倒影；所有水面扰动由 WaterSurface.fx 统一处理。
    float2 reflectedWorld = float2(
        worldPosition.x,
        edgeWorldY - distanceFromWaterline);
    float2 shoreLocal =
        (reflectedWorld - ShoreSourceWorldOrigin)
        / max(ShoreSourceWorldSize, 1.0);
    float shoreInside = step(0.0, shoreLocal.x)
        * step(shoreLocal.x, 1.0)
        * step(0.0, shoreLocal.y)
        * step(shoreLocal.y, 1.0);
    float4 shore = tex2D(ShoreSourceSampler, saturate(shoreLocal)) * shoreInside;
    float shoreDistance = 1.0 - step(
        ShoreSampleHeight + 0.01,
        distanceFromWaterline);
    float shoreCoverage = coverage
        * found
        * shoreEligible
        * shoreDistance
        * saturate(shore.a * 2.0);
    float shoreAlpha = shoreCoverage
        * saturate(WaterReflectionIntensity)
        * saturate(ShoreOpacity);
    float shoreOcclusion = shoreCoverage * saturate(ShoreOcclusion);
    float3 shoreColor = shore.rgb / max(shore.a, 0.003)
        * float3(0.66, 0.76, 0.92);

    // 人物、Object、已标注地图物体与桥柱在 CPU 侧按各自物理高度预镜像。
    float2 semanticWorldPosition = worldPosition;
    float2 semanticUv =
        (semanticWorldPosition - SemanticWorldOrigin)
        / max(SemanticWorldSize, 1.0);
    float semanticInside = step(0.0, semanticUv.x)
        * step(semanticUv.x, 1.0)
        * step(0.0, semanticUv.y)
        * step(semanticUv.y, 1.0);
    float4 semantic =
        tex2D(SemanticSampler, saturate(semanticUv)) * semanticInside;
    float3 semanticColor = semantic.rgb / max(semantic.a, 0.003);
    float semanticAlpha = coverage
        * saturate(WaterReflectionIntensity)
        * 0.58
        * saturate(semantic.a * 2.0);

    // 岸壁的视觉透明度与遮挡强度分离：保留水下的半透明感，
    // 同时不让岸后方的人物和地图物体倒影穿透岸壁。
    float visibleSemanticAlpha =
        semanticAlpha * (1.0 - shoreOcclusion);
    float alpha = shoreAlpha + visibleSemanticAlpha;
    alpha *= input.Color.a;
    float3 premultiplied = shoreColor * shoreAlpha
        + semanticColor * visibleSemanticAlpha;
    premultiplied *= input.Color.a;

    clip(alpha - 0.001);
    return float4(premultiplied, alpha);
}

technique WaterReflectionBase
{
    pass P0
    {
        VertexShader = compile vs_3_0 WaterSpriteVS();
        PixelShader = compile ps_3_0 WaterReflectionBasePS();
    }
}
