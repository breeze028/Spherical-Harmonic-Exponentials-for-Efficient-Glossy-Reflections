#include "../CPUAndGPUCommon.h"
#include "Common.hlsli"

#define GRootSignature \
    "RootFlags(0), " \
    "DescriptorTable(SRV(t0), UAV(u0), visibility = SHADER_VISIBILITY_ALL), " \

Texture2D GSHEMatrixAT : register(t0); // float

RWStructuredBuffer<float3> GSHEBuffer : register(u0);

[RootSignature(GRootSignature)]
[numthreads(1, 1, 1)]
void MainCS()
{
    float L[33][33];
    float3 y[33];
    float3 x[33];

    // Cholesky decomposition
    for (int i = 0; i < 33; ++i)
    {
        for (int j = 0; j <= i; ++j)
        {
            float Sum = 0.0f;
            for (int k = 0; k < j; ++k)
                Sum += L[i][k] * L[j][k];

            if (i == j)
            {
                float v = GSHEMatrixAT[uint2(i, i)].r - Sum;
                L[i][j] = sqrt(v);
            }
            else
            {
                L[i][j] = (GSHEMatrixAT[uint2(i, j)].r - Sum) / L[j][j];
            }
        }
    }

    // Forward substitution
    for (int i = 0; i < 33; ++i)
    {
        float3 Sum = 0;
        for (int j = 0; j < i; ++j)
            Sum += L[i][j] * y[j];

        float3 ATb_i = float3(
            GSHEMatrixAT[uint2(i, 33)].r,
            GSHEMatrixAT[uint2(i, 34)].r,
            GSHEMatrixAT[uint2(i, 35)].r
        );

        y[i] = (ATb_i - Sum) / L[i][i];
    }

    // Backward substitution
    for (int i = 32; i >= 0; --i)
    {
        float3 Sum = 0;
        for (int j = i + 1; j < 33; ++j)
            Sum += L[j][i] * x[j];

        x[i] = (y[i] - Sum) / L[i][i];
        GSHEBuffer[i] = x[i];
    }
}


