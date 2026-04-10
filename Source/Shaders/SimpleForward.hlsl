#include "../CPUAndGPUCommon.h"
#include "Common.hlsli"
#include "SHE_Math.hlsli"

#define GRootSignature                                                                                                       \
	"RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT), "                                                                        \
	"CBV(b0), "                                                                                                              \
	"DescriptorTable(CBV(b1), SRV(t0), SRV(t1), SRV(t2), SRV(t3), SRV(t4), SRV(t5), visibility = SHADER_VISIBILITY_PIXEL), " \
	"StaticSampler("                                                                                                         \
	"s0, "                                                                                                                   \
	"filter = FILTER_MIN_MAG_MIP_LINEAR, "                                                                                   \
	"visibility = SHADER_VISIBILITY_PIXEL, "                                                                                 \
	"addressU = TEXTURE_ADDRESS_BORDER, "                                                                                    \
	"addressV = TEXTURE_ADDRESS_BORDER, "                                                                                    \
	"addressW = TEXTURE_ADDRESS_BORDER)"

ConstantBuffer<FPerDrawConstantData> GPerDrawCB : register(b0);
ConstantBuffer<FPerFrameConstantData> GPerFrameCB : register(b1);
TextureCube GIrradianceMap : register(t0);
TextureCube GPrefilteredEnvMap : register(t1);
TextureCube GEnvMap : register(t2);
Texture2D GBRDFIntegrationMap : register(t3);
Texture2D GAccumulationBuffer : register(t4);
StructuredBuffer<float3> GSHESHCoeff : register(t5);
SamplerState GSampler : register(s0);

float3 FresnelSchlick(float CosTheta, float3 F0)
{
	return F0 + (1.0f - F0) * pow(1.0f - CosTheta, 5.0f);
}

float3 FresnelSchlickRoughness(float CosTheta, float3 F0, float Roughness)
{
	return F0 + (max(1.0f - Roughness, F0) - F0) * pow(1.0f - CosTheta, 5.0f);
}

[RootSignature(GRootSignature)] void MainVS(
	in float3 InPosition : _Position,
	in float3 InNormal : _Normal,
	out float4 OutPosition : SV_Position,
	out float3 OutPositionWS : _Position,
	out float3 OutNormalWS : _Normal)
{
	OutPosition = mul(float4(InPosition, 1.0f), GPerDrawCB.ObjectToClip);
	OutPositionWS = mul(float4(InPosition, 1.0f), GPerDrawCB.ObjectToWorld);
	OutNormalWS = mul(InNormal, (float3x3)GPerDrawCB.ObjectToWorld);
}

	[RootSignature(GRootSignature)] void MainPS(
		in float4 InPosition : SV_Position,
		in float3 InPositionWS : _Position,
		in float3 InNormalWS : _Normal,
		out float4 OutColor : SV_Target0)
{
	float3 V = normalize(GPerFrameCB.ViewerPosition.xyz - InPositionWS);
	float3 N = normalize(InNormalWS);
	float NoV = saturate(dot(N, V));

	float3 Albedo = GPerDrawCB.Albedo;
	float Roughness = GPerDrawCB.Roughness;
	float Metallic = GPerDrawCB.Metallic;
	float AO = GPerDrawCB.AO;

	float3 F0 = float3(0.04f, 0.04f, 0.04f);
	F0 = lerp(F0, Albedo, Metallic);

	float3 Lo = 0.0f;
	// We manually disable point lights, only use image based lighting.
	for (int LightIdx = 0; LightIdx < 0; ++LightIdx)
	{
		float3 LightVector = GPerFrameCB.LightPositions[LightIdx].xyz - InPositionWS;

		float3 L = normalize(LightVector);
		float3 H = normalize(L + V);
		float NoL = saturate(dot(N, L));
		float HoV = saturate(dot(H, V));

		float Attenuation = 1.0f / dot(LightVector, LightVector);
		float3 Radiance = GPerFrameCB.LightColors[LightIdx].rgb * Attenuation;

		float3 F = FresnelSchlick(HoV, F0);

		float NDF = DistributionGGX(N, H, Roughness);
		float G = GeometrySmith(NoL, NoV, (Roughness + 1.0f) * 0.5f);

		float3 Specular = (NDF * G * F) / max(4.0f * NoV * NoL, 0.001f);

		float3 KS = F;
		float3 KD = 1.0f - KS;
		KD *= 1.0f - Metallic;

		Lo += (KD * (Albedo / PI) + Specular) * Radiance * NoL;
	}

	float3 R = reflect(-V, N);

	float3 F = FresnelSchlickRoughness(NoV, F0, Roughness);

	float3 KD = 1.0f - F;
	KD *= 1.0f - Metallic;

	float3 Diffuse = 0.0f;
	float3 Specular = 0.0f;
	if (GPerFrameCB.IBLMode == IBL_MODE_SPLIT_SUM_APPROXIMATION)
	{
		float3 Irradiance = GIrradianceMap.SampleLevel(GSampler, N, 0.0f).rgb;
		Diffuse = Irradiance * Albedo;

		float3 PrefilteredColor = GPrefilteredEnvMap.SampleLevel(GSampler, R, Roughness * 5.0f).rgb;
		float2 EnvBRDF = GBRDFIntegrationMap.SampleLevel(GSampler, float2(min(NoV, 0.999f), min(Roughness, 0.999f)), 0.0f).rg;
		Specular = PrefilteredColor * (F0 * EnvBRDF.x + EnvBRDF.y);
	}
	else if (GPerFrameCB.IBLMode == IBL_MODE_SPHERICAL_HARMONICS_EXPONENTIAL)
	{
		float3 Hr = normalize(N + R);

		FFiveBandSHVector yP = SHBasisFunction5(R);
		FThreeBandSHVector yQ = SHBasisFunction3(Hr);

		float vmf[5];
		for (int l = 0; l < 5; ++l)
		{
			vmf[l] = vMF(l, 1.0f / Roughness);
		}
		yP = VMF_SH5(yP, vmf);
		yQ = VMF_SH3(yQ, vmf);

		FFiveBandSHVectorRGB P;
		FThreeBandSHVectorRGB Q;

		half3 coeffs[33];
		for (int i = 0; i < 33; i++)
		{
			coeffs[i] = GSHESHCoeff[i];
		}

		P.R.V0 = half4(coeffs[0].r, coeffs[1].r, coeffs[2].r, coeffs[3].r);
		P.R.V1 = half4(coeffs[4].r, coeffs[5].r, coeffs[6].r, coeffs[7].r);
		P.R.V2 = half4(coeffs[8].r, coeffs[9].r, coeffs[10].r, coeffs[11].r);
		P.R.V3 = half4(coeffs[12].r, coeffs[13].r, coeffs[14].r, coeffs[15].r);
		P.R.V4 = half4(coeffs[16].r, coeffs[17].r, coeffs[18].r, coeffs[19].r);
		P.R.V5 = half4(coeffs[20].r, coeffs[21].r, coeffs[22].r, coeffs[23].r);
		P.R.V6 = half(coeffs[24].r);

		P.G.V0 = half4(coeffs[0].g, coeffs[1].g, coeffs[2].g, coeffs[3].g);
		P.G.V1 = half4(coeffs[4].g, coeffs[5].g, coeffs[6].g, coeffs[7].g);
		P.G.V2 = half4(coeffs[8].g, coeffs[9].g, coeffs[10].g, coeffs[11].g);
		P.G.V3 = half4(coeffs[12].g, coeffs[13].g, coeffs[14].g, coeffs[15].g);
		P.G.V4 = half4(coeffs[16].g, coeffs[17].g, coeffs[18].g, coeffs[19].g);
		P.G.V5 = half4(coeffs[20].g, coeffs[21].g, coeffs[22].g, coeffs[23].g);
		P.G.V6 = half(coeffs[24].g);

		P.B.V0 = half4(coeffs[0].b, coeffs[1].b, coeffs[2].b, coeffs[3].b);
		P.B.V1 = half4(coeffs[4].b, coeffs[5].b, coeffs[6].b, coeffs[7].b);
		P.B.V2 = half4(coeffs[8].b, coeffs[9].b, coeffs[10].b, coeffs[11].b);
		P.B.V3 = half4(coeffs[12].b, coeffs[13].b, coeffs[14].b, coeffs[15].b);
		P.B.V4 = half4(coeffs[16].b, coeffs[17].b, coeffs[18].b, coeffs[19].b);
		P.B.V5 = half4(coeffs[20].b, coeffs[21].b, coeffs[22].b, coeffs[23].b);
		P.B.V6 = half(coeffs[24].b);

		Q.R.V0 = half4(coeffs[0].r, coeffs[25].r, coeffs[26].r, coeffs[27].r);
		Q.R.V1 = half4(coeffs[28].r, coeffs[29].r, coeffs[30].r, coeffs[31].r);
		Q.R.V2 = half(coeffs[32].r);

		Q.G.V0 = half4(coeffs[0].g, coeffs[25].g, coeffs[26].g, coeffs[27].g);
		Q.G.V1 = half4(coeffs[28].g, coeffs[29].g, coeffs[30].g, coeffs[31].g);
		Q.G.V2 = half(coeffs[32].g);

		Q.B.V0 = half4(coeffs[0].b, coeffs[25].b, coeffs[26].b, coeffs[27].b);
		Q.B.V1 = half4(coeffs[28].b, coeffs[29].b, coeffs[30].b, coeffs[31].b);
		Q.B.V2 = half(coeffs[32].b);

		half3 bias = GPerFrameCB.SHEBias;

		half3 logP = DotSH5(P, yP);
		half3 logQ = DotSH3(Q, yQ);
		half3 E0 = exp(logP + logQ + bias);

		half3 E1 = E0 * GBRDFIntegrationMap.SampleLevel(GSampler, float2(min(NoV, 0.999f), min(Roughness, 0.999f)), 0.0f).g;
		Specular = F0 * E0 + (1.0f - F0) * E1;
	}
	else if (GPerFrameCB.IBLMode == IBL_MODE_REFERENCE)
	{
		uint NumSamples = 64;
		float3 Irradiance = 0.0f;

		for (uint DiffuseSampleIdx = 0; DiffuseSampleIdx < NumSamples; ++DiffuseSampleIdx)
		{
			uint finalSeed = HashPixelAndSample(uint2(InPosition.xy),
												DiffuseSampleIdx + GPerFrameCB.NumFrames * NumSamples);
			float2 Xi = HaltonSequence2D(finalSeed);
			float3 L = CosineSampleHemisphere(Xi, N);

			float NoL = saturate(dot(N, L));
			if (NoL > 0.0f)
			{
				// Standard way of cosine importance sampling, no need to multiply by NoL.
				Irradiance += GEnvMap.SampleLevel(GSampler, L, log2(256 * Roughness)).rgb;
			}
		}

		for (uint SpecularSampleIdx = 0; SpecularSampleIdx < NumSamples; ++SpecularSampleIdx)
		{
			uint finalSeed = HashPixelAndSample(uint2(InPosition.xy),
												SpecularSampleIdx + GPerFrameCB.NumFrames * NumSamples);
			float2 Xi = HaltonSequence2D(finalSeed);
			float3 H = ImportanceSampleGGX(Xi, Roughness, N);
			float3 L = normalize(2.0f * dot(V, H) * H - V);

			float NoL = saturate(dot(N, L));
			float NoH = saturate(dot(N, H));
			float VoH = saturate(dot(V, H));

			if (NoL > 0.0f)
			{
				float3 Li = GEnvMap.SampleLevel(GSampler, L, log2(256 * Roughness)).rgb;
				float G = GeometrySmith(NoL, NoV, Roughness);
				float G_Vis = G * VoH / (NoH * NoV);
				Specular += Li * F * G_Vis * NoL;
			}
		}

		Diffuse = (Irradiance * Albedo) * (1.0f / NumSamples);
		Specular *= (1.0f / NumSamples);
	}

	float3 Ambient = 0.0f;
	if (GPerFrameCB.MaterialMode == MATERIAL_MODE_DIFFUSE_AND_SPECULAR)
	{
		Ambient = KD * Diffuse + Specular;
	}
	else if (GPerFrameCB.MaterialMode == MATERIAL_MODE_DIFFUSE_ONLY)
	{
		Ambient = KD * Diffuse;
	}
	else if (GPerFrameCB.MaterialMode == MATERIAL_MODE_SPECULAR_ONLY)
	{
		Ambient = Specular;
	}
	Ambient *= AO;

	float3 Color = Ambient + Lo;

	if (GPerFrameCB.IBLMode == IBL_MODE_REFERENCE && GPerFrameCB.NumFrames > 0)
	{
		// Progressive rendering for reference mode
		uint2 Dimensions;
		GAccumulationBuffer.GetDimensions(Dimensions.x, Dimensions.y);
		float3 AccumulatedColor = GAccumulationBuffer.SampleLevel(GSampler, InPosition.xy / Dimensions, 0).rgb;
		float3 AccumulatedLinearColor = pow(AccumulatedColor, 2.2f);
		float3 AccumulatedHDRColor = AccumulatedLinearColor / (1.0f - AccumulatedLinearColor);
		Color = (AccumulatedHDRColor * (GPerFrameCB.NumFrames - 1) + Color) / GPerFrameCB.NumFrames;
	}

	Color = Color / (Color + 1.0f);
	Color = pow(Color, 1.0f / 2.2f);
	OutColor = float4(Color, 1.0f);
}