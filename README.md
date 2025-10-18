# Spherical Harmonic Exponentials for Efficient Glossy Reflections

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Paper](https://img.shields.io/badge/Paper-DOI%2010.1111%2Fcgf.70219-brightgreen)](https://doi.org/10.1111/cgf.70219)

This repository contains an unofficial implementation of the **Spherical Harmonic Exponentials (SHE)** method for real-time glossy reflections, as presented in the High-Performance Graphics 2025 paper:

> **"Spherical Harmonic Exponentials for Efficient Glossy Reflections"**  
> A. Silvennoinen, P.-P. Sloan, M. Iwanicki, D. Nowrouzezahrai  
> *Computer Graphics Forum, Volume 44 (2025), Number 8*

![image](/SHE.png)

## Key Features

- **200× less memory** than traditional split-sum methods
- **Alias-free reconstruction** over continuous roughness and angular domains
- **View-dependent reflections** with higher accuracy
- **Efficient runtime evaluation** (~0.1ms overhead)
- Support for **continuously-varying material roughness**

## Build Instructions

### Compilation
- Use **Visual Studio 2022** to compile the project
- Ensure all dependencies are properly configured
- Build in **Release** mode for optimal performance

### Execution
- **Do not run the executable directly from the IDE**
- After compilation, navigate to the working directory
- Run the `.exe` file directly from the working folder
- This ensures proper resource loading and path resolution

## Implementation Overview

Our implementation consists of four main compute shaders:

### 1. `SHE_Build.hlsl`
- Constructs the linear system (matrix A and vector b)
- Samples environment maps and computes base reflectance E₀
- Applies reflection-half-reflection parameterization
- Uses von Mises-Fisher distribution for roughness encoding

### 2. `SHE_Reduction.hlsl`
- Performs parallel reduction to compute AᵀA and Aᵀb
- Divides work across multiple thread groups for scalability
- Handles large matrices efficiently

### 3. `SHE_Reduction_Merge.hlsl`
- Merges partial reduction results from multiple groups
- Finalizes the AᵀA and Aᵀb matrices
- Prepares data for linear system solving

### 4. `SHE_Solve.hlsl`
- Solves the linear system using Cholesky decomposition
- Performs forward and backward substitution
- Outputs the final spherical harmonic coefficients

## Implementation Notes & Caveats

### Technical Implementation Differences

1. **Solving Method Differences**
   - Original paper uses CUDA for stochastic linear least-squares fitting
   - This implementation uses Compute Shader for linear system construction and solving
   - Current matrix solving approach has room for optimization

2. **Performance Considerations**
   - Using StructuredBuffer to store 33 spherical harmonic coefficients (float3 RGB)
   - Reconstruction requires 33 buffer samples, which is computationally expensive
   - Using Constant Buffer instead would provide better performance

3. **Precomputation Limitations**
   - Precomputation is computationally heavy and impractical for real-time environment map updates
   - Important insight: Matrix A in the original paper is environment-independent
   - Only vector b needs to be updated when environment maps change

### Quality and Practicality Concerns

4. **Visual Quality Limitations**
   - Spherical harmonics suffer from severe band-limiting, especially at low roughness
   - Current implementation only supports roughness range: 0.4 - 1.0
   - Original paper notes poor performance below 0.25 roughness, but their roughness mapping may differ
   - At low roughness, reflections should be sharper, but even reference images in the paper appear blurry
   - At high roughness, SH lacks high-frequency reflections that Split-Sum preserves
   - Questionable whether this approach serves the primary use cases of specular reflections

5. **Brightness Loss Issue**
   - Significant brightness loss observed when reconstructing with fitted SH coefficients
   - Same issue found in other reimplementation attempts
   - Theoretical explanation: Fitting in log-space creates bias due to Jensen's inequality
   - Mathematical formulation: `𝔼[e^x] ≥ e^{𝔼[x]}` where expectation is taken in log-space

### Final Disclaimer

**This reimplementation has significant limitations and is not suitable for production use in games.** The visual quality struggles to match, let alone surpass, the established Split-Sum approximation in practical scenarios. Several technical challenges remain unresolved, particularly regarding performance, brightness accuracy, and low-roughness representation.

If you identify any implementation errors or have suggestions for improvement, please feel free to contact me or open an issue. This work represents an experimental exploration rather than a production-ready solution.
