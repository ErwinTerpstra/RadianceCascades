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

		int _RayCount;
		int _MaxSteps;

		int _BaseRayCount;
		float _IntervalSplit;
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

				float4 radiance = 0;

				bool isLastLayer = _RayCount == _BaseRayCount;
				float sqrtBase = sqrt(float(_BaseRayCount));
				
    			float2 pixel = floor(uv * resolution);

				// The width / space between probes
				// If our `baseRayCount` is 16, this is 4 on the upper cascade or 1 on the lower.
				float probeGridSize = isLastLayer ? 1.0 : sqrtBase;
				
				// Calculate the number of probes per x/y dimension
				float2 probePixelSize = floor(resolution / probeGridSize);
				
				// Calculate which probe we're processing this pass
				float2 probeRelativePosition = fmod(pixel, probePixelSize);
				
				// Calculate which group of rays we're processing this pass
				float2 probeGridIndex = floor(pixel / probePixelSize);
				
				// Calculate the index of the set of rays we're processing
				float baseIndex = float(_BaseRayCount) * (probeGridIndex.x + (probeGridSize * probeGridIndex.y));
				
				// Calculate the size of our angle step
				float angleStepSize = TAU / float(_RayCount);
				
				// Find the center of the probe we're processing
				float2 probeCenter = (probeRelativePosition + 0.5) * probeGridSize;
    			float2 normalizedProbeCenter = probeCenter * oneOverResolution;

				float scale = isLastLayer ? 1 : 2;
				float oneOverScale = 1.0 / scale;

    			float2 aspectScale = min(resolution.x, resolution.y) * oneOverResolution;

				float intervalStart = isLastLayer ? 0.0 : _IntervalSplit;
				float intervalEnd = isLastLayer ? _IntervalSplit : sqrt(2.0);

				float minStepDist = min(oneOverResolution.x, oneOverResolution.y) * 0.5;

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
					if (radianceAccum.a == 0 && isLastLayer)
					{						
						// Grid of probes
						float upperProbeGridSize = sqrtBase;
						float2 upperProbeSize = floor(resolution / upperProbeGridSize);

						// Index of the upper cascade probe to read, based on the index of the ray we are currently processing
						float2 upperProbeIndex = float2(fmod(index, upperProbeGridSize), floor(index / upperProbeGridSize));

						// Center of the upper probe that we'll read
						float2 upperProbePosition = upperProbeIndex * upperProbeSize;

						float2 offset = (probeRelativePosition + 0.5) / sqrtBase;
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
