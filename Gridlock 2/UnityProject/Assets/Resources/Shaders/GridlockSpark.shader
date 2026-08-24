// Contest sparks and the targeting line: additive, vertex-coloured, no texture.
// The particle system feeds HDR start colours (above 1.0) so the debris blooms
// with everything else.
Shader "Gridlock/Spark"
{
    Properties { _Tint ("Tint", Color) = (1, 1, 1, 1) }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" }
        Blend One One
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            float4 _Tint;

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.uv = input.uv;
                o.color = input.color;
                return o;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // Round, soft-edged point: a billboard quad shaped by its UVs, so
                // no texture asset is needed.
                float2 d = input.uv * 2.0 - 1.0;
                float falloff = saturate(1.0 - dot(d, d));
                float3 rgb = input.color.rgb * _Tint.rgb * falloff * falloff;
                return half4(rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
