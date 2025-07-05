Shader "Hidden/RadianceCascades"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		// No culling or depth
		Cull Off 
		ZWrite Off 
		ZTest Always

		HLSLINCLUDE

		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
		#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        #pragma vertex Vert

		#define PI 3.14159265
		#define TAU (PI * 2)

		SAMPLER(sampler_BlitTexture);

		TEXTURE2D(_EmissionMap);
		SAMPLER(sampler_EmissionMap);
		float4 _EmissionMap_TexelSize;

		TEXTURE2D(_EmissionSDF);
		SAMPLER(sampler_EmissionSDF);
		float4 _EmissionSDF_TexelSize;

		int _MaxSteps;

		int _BaseRayCount;

		int _CascadeIndex;
		int _CascadeCount;
		ENDHLSL

		Pass
		{
			Name "CalculateCascade"
			HLSLPROGRAM
            
			#pragma fragment Fragment

			float rand(in float2 uv)
			{
				float2 noise = (frac(sin(dot(uv ,float2(12.9898,78.233)*2.0)) * 43758.5453));
				return abs(noise.x + noise.y) * 0.5;
			}

			bool IsOutOfBounds(float2 uv) 
			{
				return uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
			}

			float4 RaymarchGI(float2 uv)
			{
				float2 resolution = _EmissionMap_TexelSize.zw;
				float2 oneOverResolution = _EmissionMap_TexelSize.xy;

				// Distinct random value for every pixel
				float noise = 0.5;//rand(uv);

				
				float sqrtBase = sqrt(float(_BaseRayCount));
				
				int rayCount = pow(_BaseRayCount, _CascadeIndex + 1);

				// Calculate the size of our angle step
				float angleStepSize = TAU / float(rayCount);

				
    			float2 pixel = floor(uv * resolution);

				// The width / space between probes
				float probeGridSize = pow(sqrtBase, _CascadeIndex);
				
				// Calculate the number of probes per x/y dimension
				float2 probePixelSize = floor(resolution / probeGridSize);
				
				// Calculate which probe we're processing this pass
				float2 probeRelativePosition = fmod(pixel, probePixelSize);
				
				// Calculate which group of rays we're processing this pass
				float2 probeGridIndex = floor(pixel / probePixelSize);
				
				// Calculate the index of the set of rays we're processing
				float baseIndex = float(_BaseRayCount) * (probeGridIndex.x + (probeGridSize * probeGridIndex.y));
				
				// Find the center of the probe we're processing
				float2 probeCenter = (probeRelativePosition + 0.5) * probeGridSize;
    			float2 normalizedProbeCenter = probeCenter * oneOverResolution;

				float shortestSide = min(resolution.x, resolution.y);
    			float2 aspectScale = shortestSide * oneOverResolution;

				float intervalStart = _CascadeIndex == 0 ? 0.0 : pow(_BaseRayCount, _CascadeIndex - 1) / shortestSide;
				float intervalEnd = pow(_BaseRayCount, _CascadeIndex) / shortestSide;

				// Stepping less than half a pixel is not usefull
				float minStepDist = min(oneOverResolution.x, oneOverResolution.y) * 0.5;

				// Accumulate radiance over all rays
				float4 radiance = 0;

				[loop]
				for(int i = 0; i < _BaseRayCount; i++) 
				{
					float index = baseIndex + float(i);
					float angle = (index + noise) * angleStepSize;

					float2 rayDirectionUV = float2(cos(angle), sin(angle)) * aspectScale;
					float rayDistance = intervalStart;

					float4 radianceAccum = 0.0;

					[loop]
					for (int step = 0; step < _MaxSteps; step++) 
					{							
						float2 sampleUV = normalizedProbeCenter + rayDirectionUV * rayDistance;

						if (IsOutOfBounds(sampleUV))
							break;	

						float4 sample = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, sampleUV);
						if (sample.a > 0.9)
						{
							radianceAccum += sample;
							break;
						}

						// How far away is the nearest object?
						float dist = SAMPLE_TEXTURE2D(_EmissionSDF, sampler_EmissionSDF, sampleUV).r;
						dist = max(dist, minStepDist);

						//float dist = minStepDist * 2;
						rayDistance += dist;

						// End if we exceeded our max distance or our alpha accumulator is saturated
						if (rayDistance >= intervalEnd)
							break;
					}

					// If nothing was hit, merge with previous layer
					if (radianceAccum.a == 0 && _CascadeIndex < (_CascadeCount - 1))
					{						
						// Grid of probes
						float upperProbeGridSize = pow(sqrtBase, _CascadeIndex + 1);
						float2 upperProbeSize = floor(resolution / upperProbeGridSize);

						// Index of the upper cascade probe to read, based on the index of the ray we are currently processing
						float2 upperProbeIndex = float2(fmod(index, upperProbeGridSize), floor(index / upperProbeGridSize));

						// Center of the upper probe that we'll read
						float2 upperProbePosition = upperProbeIndex * upperProbeSize;

						// Determine the position in the next probe
						float2 offset = (probeRelativePosition + 0.5) / sqrtBase;

						// Clamp between 0.5 and size - 0.5 to prevent 'bleeding' of the neighbour probe
						offset = clamp(offset, float2(0.5, 0.5), upperProbeSize - 0.5);

						float2 upperUV = (upperProbePosition + offset) / resolution;

						radianceAccum += SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, upperUV);
					}

					radiance += radianceAccum;
				}

				return float4(radiance.rgb / _BaseRayCount, 1.0);
			}

			float4 Fragment(Varyings i) : SV_Target
			{
				// float4 sample = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, i.texcoord);
				// sample.rgb = sample.rgb * (1 - sample.a);
				// sample.a = 1.0;
				// return sample;

				float4 color = RaymarchGI(i.texcoord);
				return color;
			}
			ENDHLSL
		}
	}
}
