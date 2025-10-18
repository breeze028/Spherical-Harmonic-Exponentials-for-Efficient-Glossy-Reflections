#include "../CPUAndGPUCommon.h"
#include "Common.hlsli"

#define GRootSignature \
    "RootFlags(0), " \
    "DescriptorTable(CBV(b0), SRV(t0), UAV(u0), visibility = SHADER_VISIBILITY_ALL), " \

ConstantBuffer<FSHEReductionConstantData> GSHEReductionCB : register(b0);
Texture3D GSHEMatrixAT3D : register(t0);

RWTexture2D<float> GSHEMatrixAT : register(u0);

[RootSignature(GRootSignature)]
[numthreads(32, 32, 1)]
void MainCS(
    uint3 ThreadID : SV_DispatchThreadID,
    uint3 GroupThreadID : SV_GroupThreadID,
    uint3 GroupID : SV_GroupID,
    uint GroupIndex : SV_GroupIndex
)
{
    // compute AtA 
    for(uint Row = ThreadID.x; Row < GSHEReductionCB.SphericalHarmonicCount; Row += 32)
    {
        for(uint Col = ThreadID.y; Col <= Row; Col += 32)
        {
            float Sum = 0;
            for(uint i = 0; i < GSHEReductionCB.GroupCountZ; i++)
            {
                Sum += GSHEMatrixAT3D[uint3(Row, Col, i)];
            }

            GSHEMatrixAT[uint2(Row, Col)] = Sum;
        }
    }

    // compute Atb
    for(uint Row = ThreadID.x; Row < GSHEReductionCB.SphericalHarmonicCount; Row += 32)
    {
        float SumR = 0;
        float SumG = 0;
        float SumB = 0;
        for(uint i = 0; i < GSHEReductionCB.GroupCountZ; i++)
        {
            SumR += GSHEMatrixAT3D[uint3(Row, GSHEReductionCB.SphericalHarmonicCount    , i)];
            SumG += GSHEMatrixAT3D[uint3(Row, GSHEReductionCB.SphericalHarmonicCount + 1, i)];
            SumB += GSHEMatrixAT3D[uint3(Row, GSHEReductionCB.SphericalHarmonicCount + 2, i)];
        }

        GSHEMatrixAT[uint2(Row, GSHEReductionCB.SphericalHarmonicCount    )] = SumR;
        GSHEMatrixAT[uint2(Row, GSHEReductionCB.SphericalHarmonicCount + 1)] = SumG;
        GSHEMatrixAT[uint2(Row, GSHEReductionCB.SphericalHarmonicCount + 2)] = SumB;
    }

}
