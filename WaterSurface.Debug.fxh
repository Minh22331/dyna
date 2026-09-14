//=============================================================================
// WaterSurface.Debug.fxh
// 长期保留的 Water Surface 诊断视图；不参与 Final Composite 控制流。
//=============================================================================

static const float NeuronalHeightDebugScale = 0.1;
static const float ReflectionDebugScale = 1.0 / 6.0;

float4 RenderWaterSurfaceDebug(
    float2 worldPosition,
    float4 mask,
    float coverage,
    float shoreDistance)
{
    if (DebugViewMode < 1.5)
        return float4(mask.rgb * coverage, coverage);

    if (DebugViewMode < 2.5)
    {
        float seed = 1.0 - step(1.5 / 255.0, shoreDistance);
        return float4(seed.xxx * coverage, coverage);
    }

    if (DebugViewMode < 3.5)
        return float4(shoreDistance.xxx * coverage, coverage);

    if (DebugViewMode < 4.5)
    {
        float2 shadingSlope;
        float2 opticalSlope;
        float3 waterNormal;
        EvaluateWaterSurfaceGeometry(
            worldPosition,
            WaterTime,
            shadingSlope,
            opticalSlope,
            waterNormal);
        float2 scaledOffset = opticalSlope
            * ReflectionDistortionStrength
            * ReflectionDebugScale;
        float2 compressedOffset = scaledOffset
            / (1.0 + abs(scaledOffset));
        float2 value = saturate(0.5 + compressedOffset * 0.5);
        return float4(value.x, value.y, 0.5, 1.0) * coverage;
    }

    if (DebugViewMode < 5.5)
    {
        float2 shadingSlope;
        float2 opticalSlope;
        float3 denseNormal;
        EvaluateDenseNormalField(
            worldPosition,
            WaterTime,
            shadingSlope,
            opticalSlope,
            denseNormal);
        return float4((denseNormal * 0.5 + 0.5) * coverage, coverage);
    }

    if (DebugViewMode < 6.5)
    {
        float surface = ComputeNeuronalSurfaceField(worldPosition, WaterTime);
        float value = saturate(0.5 + surface * NeuronalHeightDebugScale);
        return float4(value.xxx * coverage, coverage);
    }

    float depthFactor = ComputeOceanDepthFactor(shoreDistance);
    return float4(depthFactor.xxx * coverage, coverage);
}
