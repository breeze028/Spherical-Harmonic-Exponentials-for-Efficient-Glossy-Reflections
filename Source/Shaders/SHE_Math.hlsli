#pragma once

float vMF(int l, float k)
{
    return exp(-float(l * (l+1)) / (2.0f * k));
}

struct FThreeBandSHVector
{
	half4 V0;
	half4 V1;
	half  V2;
};

struct FThreeBandSHVectorRGB
{
	FThreeBandSHVector R;
	FThreeBandSHVector G;
	FThreeBandSHVector B;
};

FThreeBandSHVector SHBasisFunction3(half3 InputVector)
{
	FThreeBandSHVector Result;
	// These are derived from simplifying SHBasisFunction in C++
	Result.V0.x = 0.282095f; 
	Result.V0.y = -0.488603f * InputVector.y;
	Result.V0.z = 0.488603f * InputVector.z;
	Result.V0.w = -0.488603f * InputVector.x;

	half3 VectorSquared = InputVector * InputVector;
	Result.V1.x = 1.092548f * InputVector.x * InputVector.y;
	Result.V1.y = -1.092548f * InputVector.y * InputVector.z;
	Result.V1.z = 0.315392f * (3.0f * VectorSquared.z - 1.0f);
	Result.V1.w = -1.092548f * InputVector.x * InputVector.z;
	Result.V2 = 0.546274f * (VectorSquared.x - VectorSquared.y);

	return Result;
}

// ==============================================================================================================================
// SH5 -- 25 coefficients
// 1, 3, 5, 7, 9
// 1, 4, 9, 16, 25

struct FFiveBandSHVector
{
    half4 V0;   // 1, 2, 3, 4
    half4 V1;   // 5, 6, 7, 8
    half4 V2;   // 9, 10, 11, 12
    half4 V3;   // 13, 14, 15, 16
    half4 V4;   // 17, 18, 19, 20
    half4 V5;   // 21, 22, 23, 24
    half  V6;   // 25
};

struct FFiveBandSHVectorRGB
{
    FFiveBandSHVector R;
    FFiveBandSHVector G;
    FFiveBandSHVector B;
};

FFiveBandSHVector SHBasisFunction5(half3 InputVector)
{
    FFiveBandSHVector Result = (FFiveBandSHVector)0;

    // ------ l=0 & l=1 ------
    Result.V0.x = 0.282095;                                                                             
    Result.V0.y = -0.488603 * InputVector.y;                                                           
    Result.V0.z = 0.488603 * InputVector.z;                                                            
    Result.V0.w = -0.488603 * InputVector.x;                                                          

    // ------ l=2 ------
    half3 VectorSquared = InputVector * InputVector;
    Result.V1.x = 1.092548 * InputVector.x * InputVector.y;                                            
    Result.V1.y = -1.092548 * InputVector.y * InputVector.z;                                           
    Result.V1.z = 0.315392 * (3.0 * VectorSquared.z - 1.0);                                             
    Result.V1.w = -1.092548 * InputVector.x * InputVector.z;                                           
    Result.V2.x = 0.546274 * (VectorSquared.x - VectorSquared.y);                                       

    // ------ l=3 (9-15) ------
    half xz = InputVector.x * InputVector.z;
    half yz = InputVector.y * InputVector.z;
    half z3 = InputVector.z * VectorSquared.z; 

    Result.V2.y = 0.590044 * InputVector.y * (3.0 * VectorSquared.x - VectorSquared.y);                 
    Result.V2.z = 2.890611 * xz * InputVector.y;                                                        
    Result.V2.w = 0.457046 * InputVector.y * (5.0 * VectorSquared.z - 1.0);                             

    Result.V3.x = 0.373176 * InputVector.z * (5.0 * VectorSquared.z - 3.0);                             
    Result.V3.y = 0.457046 * InputVector.x * (5.0 * VectorSquared.z - 1.0);                             
    Result.V3.z = 1.445306 * z3 * (VectorSquared.x - VectorSquared.y);                                 
    Result.V3.w = 0.590044 * InputVector.x * (VectorSquared.x - 3.0 * VectorSquared.y);                 

    // ------ l=4 (16-24) ------
    half x2y2 = VectorSquared.x - VectorSquared.y;
    half z4 = VectorSquared.z * VectorSquared.z; 

    Result.V4.x = 0.534522 * InputVector.x * InputVector.y * x2y2;                                      
    Result.V4.y = 0.377964 * yz * (3.0 * VectorSquared.x - VectorSquared.y);                            
    Result.V4.z = 0.566947 * InputVector.x * InputVector.y * (7.0 * VectorSquared.z - 1.0);             
    Result.V4.w = 0.377964 * yz * (7.0 * VectorSquared.z - 3.0);                                        

    Result.V5.x = 0.062566 * (35.0 * z4 - 30.0 * VectorSquared.z + 3.0);                                
    Result.V5.y = 0.377964 * InputVector.x * InputVector.z * (7.0 * VectorSquared.z - 3.0);             
    Result.V5.z = 0.496079 * x2y2 * (7.0 * VectorSquared.z - 1.0);                                      
    Result.V5.w = 0.377964 * InputVector.x * InputVector.z * (VectorSquared.x - 3.0 * VectorSquared.y); 

    Result.V6 = 0.314159 * (VectorSquared.x * (VectorSquared.x - 3.0 * VectorSquared.y) - 
                            VectorSquared.y * (3.0 * VectorSquared.x - VectorSquared.y));               

    return Result;
}

FFiveBandSHVector MulSH5(FFiveBandSHVector A, half Scalar)
{
    FFiveBandSHVector Result;
    Result.V0 = A.V0 * Scalar;
    Result.V1 = A.V1 * Scalar;
    Result.V2 = A.V2 * Scalar;
    Result.V3 = A.V3 * Scalar;
    Result.V4 = A.V4 * Scalar;
    Result.V5 = A.V5 * Scalar;
    Result.V6 = A.V6 * Scalar;
    return Result;
}

FThreeBandSHVector VMF_SH3(FThreeBandSHVector A, float vMF[5])
{
    FThreeBandSHVector Result;

    // l = 0
    Result.V0.x = A.V0.x * vMF[0];

    // l = 1
    Result.V0.yzw = A.V0.yzw * vMF[1];

    // l = 2
    Result.V1 = A.V1 * vMF[2];
    Result.V2 = A.V2 * vMF[2];

    return Result;
}

FFiveBandSHVector VMF_SH5(FFiveBandSHVector A, float vMF[5])
{
    FFiveBandSHVector Result;

    // l = 0
    Result.V0.x = A.V0.x * vMF[0];

    // l = 1
    Result.V0.yzw = A.V0.yzw * vMF[1];

    // l = 2
    Result.V1 = A.V1 * vMF[2];
    Result.V2.x = A.V2.x * vMF[2];

    // l = 3
    Result.V2.yzw = A.V2.yzw * vMF[3];
    Result.V3 = A.V3 * vMF[3];

    // l = 4
    Result.V4 = A.V4 * vMF[4];
    Result.V5 = A.V5 * vMF[4];
    Result.V6 = A.V6 * vMF[4];

    return Result;
}

half DotSH5(FFiveBandSHVector A, FFiveBandSHVector B)
{
    half Result = dot(A.V0, B.V0);
    Result += dot(A.V1, B.V1);
    Result += dot(A.V2, B.V2);
    Result += dot(A.V3, B.V3);
    Result += dot(A.V4, B.V4);
    Result += dot(A.V5, B.V5);
    Result += A.V6 * B.V6; 
    return Result;
}

half3 DotSH5(FFiveBandSHVectorRGB A, FFiveBandSHVector B)
{
    half3 Result = 0;
    Result.r = DotSH5(A.R,B);
    Result.g = DotSH5(A.G,B);
    Result.b = DotSH5(A.B,B);
    return Result;
}

half DotSH3(FThreeBandSHVector A,FThreeBandSHVector B)
{
	half Result = dot(A.V0, B.V0);
	Result += dot(A.V1, B.V1);
	Result += A.V2 * B.V2;
	return Result;
}

half3 DotSH3(FThreeBandSHVectorRGB A,FThreeBandSHVector B)
{
	half3 Result = 0;
	Result.r = DotSH3(A.R,B);
	Result.g = DotSH3(A.G,B);
	Result.b = DotSH3(A.B,B);
	return Result;
}