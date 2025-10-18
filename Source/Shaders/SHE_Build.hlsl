#include "../CPUAndGPUCommon.h"
#include "Common.hlsli"
#include "SHE_Math.hlsli"

#define GRootSignature \
    "RootFlags(0), " \
    "DescriptorTable(CBV(b0), SRV(t0), UAV(u0), UAV(u1), visibility = SHADER_VISIBILITY_ALL), " \
    "StaticSampler(" \
        "s0, " \
        "filter = FILTER_MIN_MAG_LINEAR_MIP_POINT, " \
        "visibility = SHADER_VISIBILITY_ALL, " \
        "addressU = TEXTURE_ADDRESS_BORDER, " \
        "addressV = TEXTURE_ADDRESS_BORDER, " \
        "addressW = TEXTURE_ADDRESS_BORDER)" 

ConstantBuffer<FSHEBuildConstantData> GSHEBuildCB : register(b0);
TextureCube GEnvMap : register(t0);
SamplerState GSampler : register(s0);

RWTexture2D<float> GSHEMatrixA : register(u0);
RWTexture2D<float4> GSHEMatrixb : register(u1);

[RootSignature(GRootSignature)]
[numthreads(8, 8, 1)]
void MainCS(
    uint3 ThreadID : SV_DispatchThreadID,
    uint3 GroupThreadID : SV_GroupThreadID,
    uint3 GroupID : SV_GroupID,
    uint GroupIndex : SV_GroupIndex
)
{
    // get view, normal and roughness indices
    int ViewIndex = ThreadID.x;
    const int NormalIndex = ThreadID.y;
    const int RoughnessIndex = ThreadID.z;
    if (ViewIndex >= GSHEBuildCB.ViewCount || NormalIndex >= GSHEBuildCB.NormalCount || RoughnessIndex >= GSHEBuildCB.RoughnessCount)
    {
        return;
    }

    // get normal ws
    const float2 NormalIndex2D = (float2(NormalIndex % GSHEBuildCB.NormalCountSqrt, NormalIndex / GSHEBuildCB.NormalCountSqrt) + 0.5f) / (GSHEBuildCB.NormalCountSqrt);
    const float3 N = EquiAreaSphericalMapping(NormalIndex2D);

    // get view ws
    const float2 ViewIndex2D = (float2(ViewIndex % GSHEBuildCB.ViewCountSqrt, ViewIndex / GSHEBuildCB.ViewCountSqrt) + 0.5f) / GSHEBuildCB.ViewCountSqrt; // avoid situations where y is 0 or 1
    const float3 V = UniformSampleHemisphere(ViewIndex2D, N);

    // get roughness
    const float RoughnessRatio = GSHEBuildCB.RoughnessCount > 1 ? (float)RoughnessIndex / (GSHEBuildCB.RoughnessCount - 1) : 0.0f;
    const float Roughness = lerp(0.4f, 1.0f, RoughnessRatio);

    // calculate b
    float NoV = saturate(dot(N, V));
    const uint NumSamples = 1024;
    float3 E0 = 0.0f;
    for (uint i = 0; i < NumSamples; i++)
    {
        float2 Xi = Hammersley(i, NumSamples);
        float3 H = ImportanceSampleGGX(Xi, Roughness, N);
        float3 L = normalize(2.0f * dot(V, H) * H - V);

        float NoL = saturate(dot(N, L));
        float NoH = saturate(dot(N, H));
        float VoH = saturate(dot(V, H));

        if (NoL > 0.0f)
        {     
            float G = GeometrySmith(NoL, NoV, Roughness);
            float G_Vis = G * VoH / (NoH * NoV + 1e-5);
            E0 += G_Vis * GEnvMap.SampleLevel(GSampler, L, 0).rgb * NoL;
        }
    }

    E0 /= NumSamples;
	E0 = log(E0);

    // calculate A
    const float3 R = reflect(-V, N);
    const float3 Hr = normalize(N + R);

    FFiveBandSHVector yP = SHBasisFunction5(R);
    FThreeBandSHVector yQ = SHBasisFunction3(Hr);

    float vmf[5];
    for(int j = 0; j < 5; j++)
    {
        vmf[j] = vMF(j, 1.0f / Roughness);
    }

    yP = VMF_SH5(yP, vmf);
    yQ = VMF_SH3(yQ, vmf);

    const int height = NormalIndex + RoughnessIndex * GSHEBuildCB.NormalCount;
    GSHEMatrixb[uint2(ViewIndex, height)] = float4(E0.x, E0.y, E0.z, 1.0f);

    ViewIndex *= GSHEBuildCB.SphericalHarmonicCount;

    GSHEMatrixA[uint2(ViewIndex + 0, height)]  = yP.V0.x;
    GSHEMatrixA[uint2(ViewIndex + 1, height)]  = yP.V0.y;
    GSHEMatrixA[uint2(ViewIndex + 2, height)]  = yP.V0.z;
    GSHEMatrixA[uint2(ViewIndex + 3, height)]  = yP.V0.w;

    GSHEMatrixA[uint2(ViewIndex + 4, height)]  = yP.V1.x;
    GSHEMatrixA[uint2(ViewIndex + 5, height)]  = yP.V1.y;
    GSHEMatrixA[uint2(ViewIndex + 6, height)]  = yP.V1.z;
    GSHEMatrixA[uint2(ViewIndex + 7, height)]  = yP.V1.w;

    GSHEMatrixA[uint2(ViewIndex + 8, height)]  = yP.V2.x;
    GSHEMatrixA[uint2(ViewIndex + 9, height)]  = yP.V2.y;
    GSHEMatrixA[uint2(ViewIndex + 10, height)] = yP.V2.z;
    GSHEMatrixA[uint2(ViewIndex + 11, height)] = yP.V2.w;

    GSHEMatrixA[uint2(ViewIndex + 12, height)] = yP.V3.x;
    GSHEMatrixA[uint2(ViewIndex + 13, height)] = yP.V3.y;
    GSHEMatrixA[uint2(ViewIndex + 14, height)] = yP.V3.z;
    GSHEMatrixA[uint2(ViewIndex + 15, height)] = yP.V3.w;

    GSHEMatrixA[uint2(ViewIndex + 16, height)] = yP.V4.x;
    GSHEMatrixA[uint2(ViewIndex + 17, height)] = yP.V4.y;
    GSHEMatrixA[uint2(ViewIndex + 18, height)] = yP.V4.z;
    GSHEMatrixA[uint2(ViewIndex + 19, height)] = yP.V4.w;

    GSHEMatrixA[uint2(ViewIndex + 20, height)] = yP.V5.x;
    GSHEMatrixA[uint2(ViewIndex + 21, height)] = yP.V5.y;
    GSHEMatrixA[uint2(ViewIndex + 22, height)] = yP.V5.z;
    GSHEMatrixA[uint2(ViewIndex + 23, height)] = yP.V5.w;

    GSHEMatrixA[uint2(ViewIndex + 24, height)] = yP.V6;

    GSHEMatrixA[uint2(ViewIndex + 25, height)] = yQ.V0.y;
    GSHEMatrixA[uint2(ViewIndex + 26, height)] = yQ.V0.z;
    GSHEMatrixA[uint2(ViewIndex + 27, height)] = yQ.V0.w;

    GSHEMatrixA[uint2(ViewIndex + 28, height)] = yQ.V1.x;
    GSHEMatrixA[uint2(ViewIndex + 29, height)] = yQ.V1.y;
    GSHEMatrixA[uint2(ViewIndex + 30, height)] = yQ.V1.z;
    GSHEMatrixA[uint2(ViewIndex + 31, height)] = yQ.V1.w;

    GSHEMatrixA[uint2(ViewIndex + 32, height)] = yQ.V2;
}