//=============================================================================
// WaterSurface.Neuronal.fxh
// Neuronal Style：连续表面场与独立程序化水光。
//=============================================================================

float NeuronalHighlightWorldScale;
// Fixed spectral iteration counts: shared by Bottom and Composite at compile time.
// PERF: each iteration costs 2x sin/cos + 2x RotateOneRadian per pixel, and scale
// grows by 1.2x per step, so late iterations add exponentially less visible detail
// (each step's contribution shrinks by 1/1.2 relative to the previous one).
// AGGRESSIVE PASS: cut further from 6/18 -> 4/10 (an additional ~35% fewer
// transcendental ops on top of the earlier 8/30 -> 6/18 cut, so ~55-60% total
// reduction vs the original 8/30). All four water effects (reflection, bottom
// refraction, ripple/surface field, and highlight/specular) stay fully enabled;
// only the fine high-frequency detail on top of the ripple shape is reduced.
// Raise back toward 6/18 or 8/30 only if you need this for a "High" quality preset.
static const int NeuronalSurfaceIterationCount = 4;
static const int NeuronalHighlightIterationCount = 10;
float NeuronalSurfaceAmplitude;
float NeuronalOpticalStrength;
float2 NeuronalFlowDirection;
float NeuronalFlowSpeed;
float NeuronalEvolutionSpeed;
float NeuronalHighlightEnabled;
float HighlightThreshold;
float HighlightWidth;
float3 HighlightColor;
float HighlightIntensity;

float2 RotateOneRadian(float2 value)
{
    static const float RotationCos = 0.540302306;
    static const float RotationSin = 0.841470985;
    return float2(
        RotationCos * value.x - RotationSin * value.y,
        RotationSin * value.x + RotationCos * value.y);
}

float2 ComputeNeuronalPosition(float2 worldPosition, float time)
{
    float2 advectedWorldPosition = worldPosition
        + NeuronalFlowDirection * time * NeuronalFlowSpeed;
    return advectedWorldPosition * NeuronalHighlightWorldScale;
}

float ComputeNeuronalSurfaceField(float2 worldPosition, float time)
{
    float2 p = ComputeNeuronalPosition(worldPosition, time);
    float2 neuronal = float2(0.0, 0.0);
    float2 lowFrequencySum = float2(0.0, 0.0);
    float scale = 10.0;
    float evolutionTime = time * NeuronalEvolutionSpeed;

    for (int iteration = 0; iteration < NeuronalSurfaceIterationCount; iteration++)
    {
        p = RotateOneRadian(p);
        neuronal = RotateOneRadian(neuronal);
        float2 q = p * scale + float(iteration) + neuronal + evolutionTime;
        neuronal += sin(q);
        lowFrequencySum += cos(q) / scale;
        scale *= 1.2;
    }

    return (lowFrequencySum.x + lowFrequencySum.y) * NeuronalSurfaceAmplitude;
}

void EvaluateNeuronalFields(
    float2 worldPosition,
    float time,
    out float surfaceField,
    out float rawHighlight,
    out float shapedHighlight)
{
    float2 p = ComputeNeuronalPosition(worldPosition, time);
    float2 neuronal = float2(0.0, 0.0);
    float2 lowFrequencySum = float2(0.0, 0.0);
    float2 fullSum = float2(0.0, 0.0);
    float scale = 10.0;
    float evolutionTime = time * NeuronalEvolutionSpeed;

    for (int iteration = 0; iteration < NeuronalHighlightIterationCount; iteration++)
    {
        p = RotateOneRadian(p);
        neuronal = RotateOneRadian(neuronal);
        float2 q = p * scale + float(iteration) + neuronal + evolutionTime;
        neuronal += sin(q);
        float2 contribution = cos(q) / scale;
        fullSum += contribution;
        // The surface field is the prefix of the same sum, not a second accumulation.
        if (iteration == NeuronalSurfaceIterationCount - 1)
            lowFrequencySum = fullSum;
        scale *= 1.2;
    }

    surfaceField = (lowFrequencySum.x + lowFrequencySum.y)
        * NeuronalSurfaceAmplitude;
    float sumLength = max(length(fullSum), 0.001);
    rawHighlight = max(
        fullSum.x + fullSum.y + 0.4 + 0.005 / sumLength,
        0.0);
    shapedHighlight = pow(max(rawHighlight, 0.0), 2.1);
}
