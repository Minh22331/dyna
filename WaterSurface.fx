//=============================================================================
// WaterSurface.fx
// Dense / Neuronal 水面风格、水底折射与最终水面合成。
// Shader Model 3.0 / OpenGL
//=============================================================================

#include "WaterSurface.Common.fxh"
#include "WaterSurface.Dense.fxh"
#include "WaterSurface.Neuronal.fxh"

void ResolveWaterPixelInputs(
    VSOutput input,
    out float2 surfaceUv,
    out float2 worldPosition,
    out float coverage,
    out float shoreDistance,
    out float2 shoreSegmentNormal,
    out float shoreSegmentSeed)
{
    surfaceUv = input.TexCoord;
    worldPosition = SurfaceWorldOrigin + surfaceUv * SurfaceWorldSize;
    float4 mask = SampleWaterMask(worldPosition);
    coverage = mask.r * mask.g;
    clip(coverage - 0.001);

    shoreDistance = 1.0;
    shoreSegmentNormal = float2(0.0, 0.0);
    shoreSegmentSeed = 0.0;
    if (UseShoreDepthOpacity > 0.5)
    {
        float4 shoreData = SampleWaterShoreData(worldPosition);
        shoreDistance = shoreData.r;
        float2 decodedDirection = shoreData.gb * 2.0 - 1.0;
        float directionLengthSquared = dot(decodedDirection, decodedDirection);
        shoreSegmentNormal = decodedDirection
            * rsqrt(max(directionLengthSquared, 0.0001))
            * step(0.0001, directionLengthSquared);
        shoreSegmentSeed = shoreData.a;
    }
}

float4 ComposeWaterBottom(
    float2 worldPosition,
    float coverage,
    float shoreDistance,
    float2 opticalSlope,
    float lightingFactor)
{
    float2 refractedWorld = worldPosition
        + opticalSlope * BottomRefractionStrength;
    float2 bottomTileUv = frac(
        refractedWorld / max(WaterBottomWorldTileSize, 1.0));
    float2 safeUvSize = max(
        WaterBottomUvSize - WaterBottomTexelSize,
        WaterBottomTexelSize);
    float2 bottomUv = WaterBottomUvOrigin
        + WaterBottomTexelSize * 0.5
        + bottomTileUv * safeUvSize;
    float4 bottom = tex2D(WaterBottomSampler, bottomUv);
    float3 bottomColor = bottom.rgb / max(bottom.a, 0.003);
    float3 waterColor = ResolveSurfaceColor(shoreDistance);
    float opacity = ResolveSurfaceOpacity(shoreDistance);
    float3 refractedWater = lerp(
        bottomColor,
        waterColor,
        saturate(opacity));
    refractedWater *= lightingFactor;
    return float4(refractedWater * coverage, coverage);
}

float4 ComposeWaterSurface(
    VSOutput input,
    float2 surfaceUv,
    float coverage,
    float2 opticalSlope,
    float specularStrength,
    float highlightStrength)
{
    float2 reflectionOffset = opticalSlope * ReflectionDistortionStrength;
    float2 reflectionUv = surfaceUv
        + reflectionOffset / max(SurfaceWorldSize, 1.0);
    float reflectionInside = step(0.0, reflectionUv.x)
        * step(reflectionUv.x, 1.0)
        * step(0.0, reflectionUv.y)
        * step(reflectionUv.y, 1.0);
    float4 reflection = tex2D(ReflectionSampler, saturate(reflectionUv))
        * reflectionInside;

    float3 finalWater = reflection.rgb;
    finalWater += HighlightColor * (highlightStrength + specularStrength);
    finalWater *= input.Color.a;

    float alpha = reflection.a * input.Color.a;
    clip(max(alpha, max(highlightStrength, specularStrength)) - 0.001);
    return float4(finalWater, alpha);
}

float4 WaterBottomRefractionDensePS(VSOutput input) : COLOR
{
    float2 surfaceUv;
    float2 worldPosition;
    float coverage;
    float shoreDistance;
    float2 shoreSegmentNormal;
    float shoreSegmentSeed;
    ResolveWaterPixelInputs(
        input,
        surfaceUv,
        worldPosition,
        coverage,
        shoreDistance,
        shoreSegmentNormal,
        shoreSegmentSeed);

    float2 shadingSlope;
    float2 opticalSlope;
    float3 waterNormal;
    EvaluateDenseNormalField(
        worldPosition,
        WaterTime,
        shoreDistance,
        shoreSegmentNormal,
        shoreSegmentSeed,
        shadingSlope,
        opticalSlope,
        waterNormal);
    return ComposeWaterBottom(
        worldPosition,
        coverage,
        shoreDistance,
        opticalSlope,
        ComputeDenseLighting(waterNormal));
}

float4 WaterBottomRefractionNeuronalPS(VSOutput input) : COLOR
{
    float2 surfaceUv;
    float2 worldPosition;
    float coverage;
    float shoreDistance;
    float2 shoreSegmentNormal;
    float shoreSegmentSeed;
    ResolveWaterPixelInputs(
        input,
        surfaceUv,
        worldPosition,
        coverage,
        shoreDistance,
        shoreSegmentNormal,
        shoreSegmentSeed);

    // MIRROR MODE: bottom sample is no longer warped by the wave field, and
    // lighting is flat (a (0,0,1) normal always makes ComputeLighting return
    // 1.0, so we skip that call too). This removes the ComputeNeuronalSurfaceField
    // call here entirely rather than just running it with fewer iterations —
    // this was a separate instance of the same loop from the one in
    // WaterSurfaceCompositeNeuronalPS, so it needed cutting too.
    float2 opticalSlope = float2(0.0, 0.0);
    return ComposeWaterBottom(
        worldPosition,
        coverage,
        shoreDistance,
        opticalSlope,
        1.0);
}

float4 WaterSurfaceCompositeDensePS(VSOutput input) : COLOR
{
    float2 surfaceUv;
    float2 worldPosition;
    float coverage;
    float shoreDistance;
    float2 shoreSegmentNormal;
    float shoreSegmentSeed;
    ResolveWaterPixelInputs(
        input,
        surfaceUv,
        worldPosition,
        coverage,
        shoreDistance,
        shoreSegmentNormal,
        shoreSegmentSeed);

    float2 shadingSlope;
    float2 opticalSlope;
    float3 waterNormal;
    EvaluateDenseNormalField(
        worldPosition,
        WaterTime,
        shoreDistance,
        shoreSegmentNormal,
        shoreSegmentSeed,
        shadingSlope,
        opticalSlope,
        waterNormal);
    float specular = ComputeSpecular(waterNormal) * coverage;
    return ComposeWaterSurface(
        input,
        surfaceUv,
        coverage,
        opticalSlope,
        specular,
        0.0);
}

float4 WaterSurfaceCompositeNeuronalPS(VSOutput input) : COLOR
{
    float2 surfaceUv;
    float2 worldPosition;
    float coverage;
    float shoreDistance;
    float2 shoreSegmentNormal;
    float shoreSegmentSeed;
    ResolveWaterPixelInputs(
        input,
        surfaceUv,
        worldPosition,
        coverage,
        shoreDistance,
        shoreSegmentNormal,
        shoreSegmentSeed);

    // MIRROR MODE: water surface is a flat, undistorted reflection with no
    // ripple, no specular glint, and no procedural highlight. Both Neuronal
    // loops (the 4-iteration surface field and the 10-iteration highlight
    // field) are skipped entirely, not just run with fewer iterations —
    // opticalSlope=(0,0) means their output would only ever get multiplied
    // away anyway, so there's nothing to compute.
    float2 opticalSlope = float2(0.0, 0.0);
    return ComposeWaterSurface(
        input,
        surfaceUv,
        coverage,
        opticalSlope,
        0.0,
        0.0);
}

technique WaterBottomRefractionDense
{
    pass P0
    {
        VertexShader = compile vs_3_0 WaterSurfaceVS();
        PixelShader = compile ps_3_0 WaterBottomRefractionDensePS();
    }
}

technique WaterBottomRefractionNeuronal
{
    pass P0
    {
        VertexShader = compile vs_3_0 WaterSurfaceVS();
        PixelShader = compile ps_3_0 WaterBottomRefractionNeuronalPS();
    }
}

technique WaterSurfaceCompositeDense
{
    pass P0
    {
        VertexShader = compile vs_3_0 WaterSurfaceVS();
        PixelShader = compile ps_3_0 WaterSurfaceCompositeDensePS();
    }
}

technique WaterSurfaceCompositeNeuronal
{
    pass P0
    {
        VertexShader = compile vs_3_0 WaterSurfaceVS();
        PixelShader = compile ps_3_0 WaterSurfaceCompositeNeuronalPS();
    }
}