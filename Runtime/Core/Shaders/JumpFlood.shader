Shader "Hidden/JumpFlood"
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

		SAMPLER(sampler_BlitTexture);
		ENDHLSL

		Pass
		{
			Name "Seed"
			HLSLPROGRAM
            #pragma fragment FragmentSeed

			float _Offset;

			float4 FragmentSeed(Varyings i) : SV_Target
			{
				float4 sampleValue = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, i.texcoord);
				return float4(i.texcoord, 0, 1) * (sampleValue.a > 0.9 ? 1 : 0);
			}
			ENDHLSL
		}

		Pass
		{
			Name "Filter"
			HLSLPROGRAM
            #pragma fragment FragmentFilter

			float _Offset;

			float4 FragmentFilter(Varyings i) : SV_Target
			{
				bool foundSeed = false;
				
				float2 nearestSeed = 0;
				float nearestDist = 999999;

				for (int y = -1; y <= 1; y += 1)
				{
					for (int x = -1; x <= 1; x += 1) 
					{
						float2 sampleUV = i.texcoord + (float2(x, y) * _Offset) * _BlitTexture_TexelSize.xy;
						if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0)
							continue;

						float4 sampleValue = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, sampleUV);
						float2 sampleSeed = sampleValue.xy;

						if (sampleValue.a > 0.0)
						{
							float2 diff = sampleSeed - i.texcoord;
							float dist = dot(diff, diff);
							
							if (dist < nearestDist) 
							{
								nearestDist = dist;
								nearestSeed = sampleSeed;
							}

							foundSeed = true;
						}

					}
				}

				if (!foundSeed)
					return 0;
				
				return float4(nearestSeed.x, nearestSeed.y, 0, 1.0);
			}
			ENDHLSL
		}
		
		Pass
		{
			Name "ConvertToSDF"
			HLSLPROGRAM
            #pragma fragment FragmentSDF

			float4 FragmentSDF(Varyings i) : SV_Target
			{
				float2 nearestSeed = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, i.texcoord).xy;

				// Clamp by the size of our texture (1.0 in uv space).
				float distance = saturate(length(i.texcoord - nearestSeed));

				// Normalize and visualize the distance
				return distance;
			}
			ENDHLSL
		}
	}
}
