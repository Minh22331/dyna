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
    float3 waterNormal,
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

    float specular = ComputeSpecular(waterNormal) * coverage;
    float3 finalWater = reflection.rgb;
    finalWater += HighlightColor * (highlightStrength + specular);
    finalWater *= input.Color.a;

    float alpha = reflection.a * input.Color.a;
    clip(max(alpha, max(highlightStrength, specular)) - 0.001);
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

    float neuronalSurface = ComputeNeuronalSurfaceField(
        worldPosition,
        WaterTime);
    float2 surfaceSlope = ComputeScreenDerivativeSlope(neuronalSurface);
    float2 opticalSlope = surfaceSlope * NeuronalOpticalStrength;
    float3 waterNormal = ComputeSurfaceNormal(surfaceSlope);
    return ComposeWaterBottom(
        worldPosition,
        coverage,
        shoreDistance,
        opticalSlope,
        ComputeLighting(waterNormal, WaveLightingStrength));
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
    return ComposeWaterSurface(
        input,
        surfaceUv,
        coverage,
        opticalSlope,
        waterNormal,
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

    // PERF: only pay for the expensive N-iteration highlight field when the
    // highlight is actually enabled. Previously EvaluateNeuronalFields (18
    // iterations) always ran even when highlightStrength was discarded below;
    // the cheap ComputeNeuronalSurfaceField (6 iterations) is enough on its own.
    float neuronalSurface;
    float2 surfaceSlope;
    float highlightStrength = 0.0;
    if (NeuronalHighlightEnabled > 0.5)
    {
        float rawHighlight;
        float shapedHighlight;
        EvaluateNeuronalFields(
            worldPosition,
            WaterTime,
            neuronalSurface,
            rawHighlight,
            shapedHighlight);
        surfaceSlope = ComputeScreenDerivativeSlope(neuronalSurface);

        float highlightMask = smoothstep(
            HighlightThreshold,
            HighlightThreshold + max(HighlightWidth, 0.001),
            shapedHighlight);
        highlightStrength = highlightMask * coverage * HighlightIntensity;
    }
    else
    {
        neuronalSurface = ComputeNeuronalSurfaceField(worldPosition, WaterTime);
        surfaceSlope = ComputeScreenDerivativeSlope(neuronalSurface);
    }
    float2 opticalSlope = surfaceSlope * NeuronalOpticalStrength;
    float3 waterNormal = ComputeSurfaceNormal(surfaceSlope);
    return ComposeWaterSurface(
        input,
        surfaceUv,
        coverage,
        opticalSlope,
        waterNormal,
        highlightStrength);
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
