#include "../CPUAndGPUCommon.h"
#include "Common.hlsli"

#define GRootSignature \
    "RootFlags(0), " \
    "DescriptorTable(CBV(b0), SRV(t0), SRV(t1), UAV(u0), visibility = SHADER_VISIBILITY_ALL), " \

ConstantBuffer<FSHEReductionConstantData> GSHEReductionCB : register(b0);
Texture2D GSHEMatrixA : register(t0); // float
Texture2D GSHEMatrixb : register(t1); // float3

RWTexture3D<float> GSHEMatrixAT3D : register(u0);

[RootSignature(GRootSignature)]
[numthreads(32, 32, 1)]
void MainCS(
    uint3 ThreadID : SV_DispatchThreadID,
    uint3 GroupThreadID : SV_GroupThreadID,
    uint3 GroupID : SV_GroupID,
    uint GroupIndex : SV_GroupIndex
)
{
    const uint ElementCountPerThread = GSHEReductionCB.ElementCount / GSHEReductionCB.GroupCountZ; // 16384 / 64 = 256
    // compute AtA 
    for(uint Row = ThreadID.x; Row < GSHEReductionCB.SphericalHarmonicCount; Row += 32)
    {
        for(uint Col = ThreadID.y; Col <= Row; Col += 32)
        {
            float Sum = 0; 
            for(uint i = 0; i < ElementCountPerThread; i++)
            {
                uint2 IndexA = uint2(ThreadID.z * GSHEReductionCB.SphericalHarmonicCount + Row, i);
                uint2 IndexAt = uint2(ThreadID.z * GSHEReductionCB.SphericalHarmonicCount + Col, i);
                Sum += GSHEMatrixA[IndexA].r * GSHEMatrixA[IndexAt].r;
            }

            GSHEMatrixAT3D[uint3(Row, Col, ThreadID.z)] = Sum;
        }
    }

    // compute Atb
    for(uint Col = ThreadID.x; Col < GSHEReductionCB.SphericalHarmonicCount; Col += 32)
    {
        float3 Sum = 0.0f;
        for(uint i = 0; i < ElementCountPerThread; i++)
        {
            uint2 IndexAt = uint2(ThreadID.z * GSHEReductionCB.SphericalHarmonicCount + Col, i);
            uint2 IndexB = uint2(ThreadID.z, i);
            float At = GSHEMatrixA[IndexAt].r;
            float3 b = GSHEMatrixb[IndexB].rgb;
            Sum += At * b;
        }

        GSHEMatrixAT3D[uint3(Col, GSHEReductionCB.SphericalHarmonicCount     , ThreadID.z)] = Sum.r;
        GSHEMatrixAT3D[uint3(Col, GSHEReductionCB.SphericalHarmonicCount + 1 , ThreadID.z)] = Sum.g;
        GSHEMatrixAT3D[uint3(Col, GSHEReductionCB.SphericalHarmonicCount + 2 , ThreadID.z)] = Sum.b;
    }

}
