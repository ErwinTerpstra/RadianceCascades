Shader "Erwin Terpstra/Sprite (GI)"
{
    Properties
    {
        _MainTex("Diffuse", 2D) = "white" {}
        _MaskTex("Mask", 2D) = "white" {}
        _NormalMap("Normal Map", 2D) = "bump" {}
        _Intensity("Intensity", Range(0.0, 8.0)) = 1.0
        _ZWrite("ZWrite", Float) = 0
        [Toggle] _GI_EMISSION("Emissive", Float) = 0
    }

    SubShader
    {
        Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha
        Cull Off
        ZWrite [_ZWrite]
        ZTest Off

        HLSLINCLUDE
        #pragma multi_compile _ SKINNED_SPRITE
        #pragma shader_feature _GI_EMISSION_ON
        #pragma target 4.0

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/Shaders/2D/Include/Core2D.hlsl"

        struct Attributes
        {
            float3 positionOS   : POSITION;
            float4 color        : COLOR;
            float2 uv           : TEXCOORD0;

            UNITY_SKINNED_VERTEX_INPUTS
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4  positionCS  : SV_POSITION;
            half4   color       : COLOR;
            float2  uv          : TEXCOORD0;
            half2   lightingUV  : TEXCOORD1;

            UNITY_VERTEX_OUTPUT_STEREO
        };

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);

        TEXTURE2D(_MaskTex);
        SAMPLER(sampler_MaskTex);

        Varyings DefaultVertex(Attributes v)
        {
            Varyings o = (Varyings)0;
            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
            UNITY_SKINNED_VERTEX_COMPUTE(v);

            v.positionOS = UnityFlipSprite(v.positionOS, unity_SpriteProps.xy);
            o.positionCS = TransformObjectToHClip(v.positionOS);
            o.uv = v.uv;
            o.lightingUV = half2(ComputeScreenPos(o.positionCS / o.positionCS.w).xy);

            o.color = v.color * unity_SpriteColor;
            return o;
        }

        ENDHLSL 

        Pass
        {
            Name "EmissionMap"
            Tags {"Queue" = "Transparent" "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "LightMode" = "EmissionMap" }

            HLSLPROGRAM

            #pragma vertex DefaultVertex
            #pragma fragment EmissionFragment

            float _Intensity;

            half4 EmissionFragment(Varyings i) : SV_Target
            {
                #ifdef _GI_EMISSION_ON
                    half4 main = i.color * SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                    half4 mask = SAMPLE_TEXTURE2D(_MaskTex, sampler_MaskTex, i.uv);
                    
                    main.rgb *= _Intensity;

                    return main * mask;
                #else
                    return 0;
                #endif
            }
            ENDHLSL
        }

        Pass
        {
            Tags {"Queue" = "Transparent" "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "LightMode" = "Universal2D" }

            HLSLPROGRAM
            #pragma vertex DefaultVertex
            #pragma fragment LitFragment

            TEXTURE2D(_EmissionRC);
            SAMPLER(sampler_EmissionRC);

            half4 LitFragment(Varyings i) : SV_Target
            {
                half3 radiance = SAMPLE_TEXTURE2D(_EmissionRC, sampler_EmissionRC, i.lightingUV);
                
                half4 main = i.color * SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                half4 mask = SAMPLE_TEXTURE2D(_MaskTex, sampler_MaskTex, i.uv);
                
                main.rgb += radiance;

                return main * mask;
            }
            ENDHLSL
        }
    }
}

