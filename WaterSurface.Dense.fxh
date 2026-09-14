//=============================================================================
// WaterSurface.Dense.fxh
// Dense Style：三频段、双 cohort 的世界空间频谱坡度场。
//=============================================================================

float DenseLowStrength;
float DenseMidStrength;
float DenseHighStrength;
float DenseOverallStrength;
float DenseOpticalLowStrength;
float DenseOpticalMidStrength;
float DenseNormalWorldScaleA;
float DenseNormalWorldScaleB;
float DenseOmegaLowA;
float DenseOmegaLowB;
float DenseOmegaMidA;
float DenseOmegaMidB;
float DenseOmegaHighA;
float DenseOmegaHighB;
float DenseSpeedMultiplier;
float DenseLightingStrength;
float2 DenseGlobalWaveDirection;
float DenseShoreMaximumDistancePixels;
float DenseShoreWaveFadeStart;
float DenseShoreWaveFadeEnd;
float DenseShoreWaveFrequency;
float DenseShoreWaveOmega;
float DenseShoreWaveStrength;
float DenseShoreWaveOpticalStrength;
float DenseShoreWavePhaseJitterRadians;

static const float2 DenseCanonicalWaveDirection = float2(0.0, 1.0);

static const float DensePhaseOffsetLowA = 0.31;
static const float DensePhaseOffsetLowB = 2.14;
static const float DensePhaseOffsetMidA = 1.73;
static const float DensePhaseOffsetMidB = 4.08;
static const float DensePhaseOffsetHighA = 3.17;
static const float DensePhaseOffsetHighB = 5.42;

static const float2 DenseUvOffsetLowA = float2(0.071, 0.113);
static const float2 DenseUvOffsetLowB = float2(0.383, 0.619);
static const float2 DenseUvOffsetMidA = float2(0.719, 0.271);
static const float2 DenseUvOffsetMidB = float2(0.157, 0.853);
static const float2 DenseUvOffsetHighA = float2(0.541, 0.437);
static const float2 DenseUvOffsetHighB = float2(0.887, 0.193);

texture DenseNormalTextureLowA;
sampler2D DenseNormalSamplerLowA : register(s3) = sampler_state
{
    Texture = <DenseNormalTextureLowA>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Wrap;
    AddressV = Wrap;
};

texture DenseNormalTextureLowB;
sampler2D DenseNormalSamplerLowB : register(s4) = sampler_state
{
    Texture = <DenseNormalTextureLowB>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Wrap;
    AddressV = Wrap;
};

texture DenseNormalTextureMidA;
sampler2D DenseNormalSamplerMidA : register(s5) = sampler_state
{
    Texture = <DenseNormalTextureMidA>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Wrap;
    AddressV = Wrap;
};

texture DenseNormalTextureMidB;
sampler2D DenseNormalSamplerMidB : register(s6) = sampler_state
{
    Texture = <DenseNormalTextureMidB>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Wrap;
    AddressV = Wrap;
};

texture DenseNormalTextureHighA;
sampler2D DenseNormalSamplerHighA : register(s7) = sampler_state
{
    Texture = <DenseNormalTextureHighA>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Wrap;
    AddressV = Wrap;
};

texture DenseNormalTextureHighB;
sampler2D DenseNormalSamplerHighB : register(s8) = sampler_state
{
    Texture = <DenseNormalTextureHighB>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    AddressU = Wrap;
    AddressV = Wrap;
};

float2 EvaluateDenseCohort(float4 basis, float phase)
{
    basis = basis * 2.0 - 1.0;
    return basis.rg * cos(phase) + basis.ba * sin(phase);
}

float ComputeDenseLighting(float3 waterNormal)
{
    float side = dot(waterNormal.xy, WaterLightDirection.xy);
    return max(
        1.0 + side * DenseLightingStrength * WaveLightingEnabled,
        0.0);
}

float2 RotateDenseWorldToCanonical(
    float2 worldPosition,
    float2 globalDirection)
{
    float rotationCos = dot(
        DenseCanonicalWaveDirection,
        globalDirection);
    float rotationSin = DenseCanonicalWaveDirection.x * globalDirection.y
        - DenseCanonicalWaveDirection.y * globalDirection.x;
    return float2(
        rotationCos * worldPosition.x + rotationSin * worldPosition.y,
        -rotationSin * worldPosition.x + rotationCos * worldPosition.y);
}

float2 RotateDenseCanonicalToWorld(
    float2 gradient,
    float2 globalDirection)
{
    float rotationCos = dot(
        DenseCanonicalWaveDirection,
        globalDirection);
    float rotationSin = DenseCanonicalWaveDirection.x * globalDirection.y
        - DenseCanonicalWaveDirection.y * globalDirection.x;
    return float2(
        rotationCos * gradient.x - rotationSin * gradient.y,
        rotationSin * gradient.x + rotationCos * gradient.y);
}

float ComputeDenseShoreWaveWeight(float shoreDistance)
{
    return 1.0 - smoothstep(
        DenseShoreWaveFadeStart,
        max(DenseShoreWaveFadeEnd, DenseShoreWaveFadeStart + 0.0001),
        shoreDistance);
}

void EvaluateDenseNormalField(
    float2 worldPosition,
    float time,
    float shoreDistance,
    float2 shoreSegmentNormal,
    float shoreSegmentSeed,
    out float2 shadingSlope,
    out float2 opticalSlope,
    out float3 combinedNormal)
{
    float denseTime = time * DenseSpeedMultiplier;
    float2 globalDirection = DenseGlobalWaveDirection;
    float2 directionalWorldPosition = RotateDenseWorldToCanonical(
        worldPosition,
        globalDirection);
    float2 uvCoarse = directionalWorldPosition * DenseNormalWorldScaleA;
    float2 uvFine = directionalWorldPosition * DenseNormalWorldScaleB;

    float2 gradientLow = RotateDenseCanonicalToWorld(EvaluateDenseCohort(
        tex2D(DenseNormalSamplerLowA, uvCoarse + DenseUvOffsetLowA),
        denseTime * DenseOmegaLowA + DensePhaseOffsetLowA)
        + EvaluateDenseCohort(
            tex2D(DenseNormalSamplerLowB, uvCoarse + DenseUvOffsetLowB),
            denseTime * DenseOmegaLowB + DensePhaseOffsetLowB),
        globalDirection);
    float2 gradientMid = RotateDenseCanonicalToWorld(EvaluateDenseCohort(
        tex2D(DenseNormalSamplerMidA, uvCoarse + DenseUvOffsetMidA),
        denseTime * DenseOmegaMidA + DensePhaseOffsetMidA)
        + EvaluateDenseCohort(
            tex2D(DenseNormalSamplerMidB, uvCoarse + DenseUvOffsetMidB),
            denseTime * DenseOmegaMidB + DensePhaseOffsetMidB),
        globalDirection);
    float2 gradientHigh = RotateDenseCanonicalToWorld(EvaluateDenseCohort(
        tex2D(DenseNormalSamplerHighA, uvFine + DenseUvOffsetHighA),
        denseTime * DenseOmegaHighA + DensePhaseOffsetHighA)
        + EvaluateDenseCohort(
            tex2D(DenseNormalSamplerHighB, uvFine + DenseUvOffsetHighB),
            denseTime * DenseOmegaHighB + DensePhaseOffsetHighB),
        globalDirection);

    float shoreValid = step(
        0.5,
        dot(shoreSegmentNormal, shoreSegmentNormal));
    float2 shoreNormal = shoreSegmentNormal;
    float shoreWeight = ComputeDenseShoreWaveWeight(shoreDistance)
        * shoreValid;
    float shoreDistanceWorld = shoreDistance
        * DenseShoreMaximumDistancePixels;
    float phaseOffset = (shoreSegmentSeed * 2.0 - 1.0)
        * DenseShoreWavePhaseJitterRadians;
    float primaryPhase = shoreDistanceWorld * DenseShoreWaveFrequency
        + denseTime * DenseShoreWaveOmega
        + phaseOffset;
    float2 shoreSlope = shoreNormal
        * cos(primaryPhase)
        * DenseShoreWaveStrength
        * shoreWeight;

    shadingSlope = (
        gradientLow * DenseLowStrength
        + gradientMid * DenseMidStrength
        + gradientHigh * DenseHighStrength
        + shoreSlope)
        * DenseOverallStrength;
    opticalSlope = gradientLow * DenseOpticalLowStrength
        + gradientMid * DenseOpticalMidStrength
        + shoreSlope * DenseShoreWaveOpticalStrength;
    combinedNormal = normalize(float3(-shadingSlope, 1.0));
}
