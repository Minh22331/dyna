//=============================================================================
// WaterSurface.Common.fxh
// Water Surface 共享输入、Mask/岸距采样、光照与最终合成辅助。
//=============================================================================

float4x4 MatrixTransform;

float2 SurfaceWorldOrigin;
float2 SurfaceWorldSize;
float2 SurfaceWorldTexelSize;
float2 WaterMaskWorldOrigin;
float2 WaterMaskWorldSize;
float WaterTime;

float SurfaceNormalStrength;
float WaveLightingEnabled;
float WaveLightingStrength;
float ReflectionDistortionStrength;
float BottomRefractionStrength;
float SpecularEnabled;
float SpecularPower;
float SpecularIntensity;

float2 WaterBottomUvOrigin;
float2 WaterBottomUvSize;
float2 WaterBottomTexelSize;
float WaterBottomWorldTileSize;
float3 WaterSurfaceColor;
float WaterSurfaceOpacity;
float UseShoreDepthOpacity;
float3 OceanShallowColor;
float3 OceanDeepColor;
float OceanShallowOpacity;
float OceanDeepOpacity;
float OceanDepthFadeStart;
float OceanDepthFadeEnd;
float OceanColorFadeStart;
float OceanColorFadeEnd;
float OceanFarDarkeningStart;
float OceanFarDarkeningEnd;
float OceanFarDarkeningStrength;

static const float3 WaterLightDirection = float3(-0.4056, -0.3042, 0.8620);
static const float3 WaterHalfDirection = float3(-0.2101, -0.1576, 0.9649);

sampler2D ReflectionSampler : register(s0) = sampler_state
{
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Clamp;
    AddressV = Clamp;
};

texture WaterMaskTexture;
sampler2D WaterMaskSampler : register(s1) = sampler_state
{
    Texture = <WaterMaskTexture>;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
    AddressU = Clamp;
    AddressV = Clamp;
};

texture WaterBottomTexture;
sampler2D WaterBottomSampler : register(s2) = sampler_state
{
    Texture = <WaterBottomTexture>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Clamp;
    AddressV = Clamp;
};

texture WaterShoreDistanceTexture;
sampler2D WaterShoreDistanceSampler : register(s11) = sampler_state
{
    Texture = <WaterShoreDistanceTexture>;
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

VSOutput WaterSurfaceVS(VSInput input)
{
    VSOutput output;
    output.Position = mul(input.Position, MatrixTransform);
    output.Color = input.Color;
    output.TexCoord = input.TexCoord;
    return output;
}

float3 ComputeSurfaceNormal(float2 slope)
{
    return normalize(float3(
        -slope.x * SurfaceNormalStrength,
        -slope.y * SurfaceNormalStrength,
        1.0));
}

float2 ComputeScreenDerivativeSlope(float surfaceField)
{
    return float2(ddx(surfaceField), ddy(surfaceField))
        / max(SurfaceWorldTexelSize, 0.0001);
}

float ComputeLighting(float3 waterNormal, float strength)
{
    float sideLighting = dot(waterNormal.xy, WaterLightDirection.xy);
    return max(
        1.0 + sideLighting * strength * WaveLightingEnabled,
        0.0);
}

float ComputeSpecular(float3 waterNormal)
{
    return pow(
        saturate(dot(waterNormal, WaterHalfDirection)),
        max(SpecularPower, 1.0))
        * SpecularIntensity
        * SpecularEnabled;
}

float4 SampleWaterMask(float2 worldPosition)
{
    float2 maskUv =
        (worldPosition - WaterMaskWorldOrigin)
        / max(WaterMaskWorldSize, 1.0);
    float maskInside = step(0.0, maskUv.x)
        * step(maskUv.x, 1.0)
        * step(0.0, maskUv.y)
        * step(maskUv.y, 1.0);
    return tex2D(WaterMaskSampler, saturate(maskUv)) * maskInside;
}

float4 SampleWaterShoreData(float2 worldPosition)
{
    float2 maskUv =
        (worldPosition - WaterMaskWorldOrigin)
        / max(WaterMaskWorldSize, 1.0);
    return tex2D(WaterShoreDistanceSampler, saturate(maskUv));
}

float ComputeOceanDepthFactor(float shoreDistance)
{
    return smoothstep(
        OceanDepthFadeStart,
        max(OceanDepthFadeEnd, OceanDepthFadeStart + 0.0001),
        shoreDistance);
}

float ComputeOceanFarFactor(float shoreDistance)
{
    return smoothstep(
        OceanFarDarkeningStart,
        max(OceanFarDarkeningEnd, OceanFarDarkeningStart + 0.0001),
        shoreDistance);
}

float ComputeOceanColorFactor(float shoreDistance)
{
    return smoothstep(
        OceanColorFadeStart,
        max(OceanColorFadeEnd, OceanColorFadeStart + 0.0001),
        shoreDistance);
}

float3 ResolveSurfaceColor(float shoreDistance)
{
    if (UseShoreDepthOpacity < 0.5)
        return WaterSurfaceColor;

    float3 waterColor = lerp(
        OceanShallowColor,
        OceanDeepColor,
        ComputeOceanColorFactor(shoreDistance));
    float farBrightness = lerp(
        1.0,
        1.0 - OceanFarDarkeningStrength,
        ComputeOceanFarFactor(shoreDistance));
    return waterColor * farBrightness;
}

float ResolveSurfaceOpacity(float shoreDistance)
{
    if (UseShoreDepthOpacity < 0.5)
        return WaterSurfaceOpacity;

    return lerp(
        OceanShallowOpacity,
        OceanDeepOpacity,
        ComputeOceanDepthFactor(shoreDistance));
}
