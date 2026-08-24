// A node outline is a closed ribbon around the hex: UV.x runs 0..1 around the
// ring, UV.y is across in [-1, 1]. Same HDR rule as the wire shader: a thin
// crisp core in colours above 1.0, and bloom supplies the thickness.
Shader "Gridlock/Node"
{
    Properties
    {
        _RingColor ("Ring Colour", Color) = (0.35, 0.38, 0.44, 1)
        _Intensity ("Intensity", Float) = 1
        _BaseIntensity ("Base Intensity", Float) = 1
        _CoreUv ("Core Half-Width (UV)", Float) = 0.25
        _PulsePhase ("Pulse Phase", Float) = 0
        _PulseAmount ("Pulse Amount", Float) = 0
        _Armed ("Burst Armed", Float) = 0
        _Sweep ("Disabled Sweep", Float) = -1
        _Flash ("Capture Flash", Float) = 0
    }

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

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            float4 _RingColor;
            float _Intensity;
            float _BaseIntensity;
            float _CoreUv;
            float _PulsePhase;
            float _PulseAmount;
            float _Armed;
            float _Sweep;
            float _Flash;

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.uv = input.uv;
                return o;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float around = input.uv.x;
                float across = abs(input.uv.y);

                float core = 1.0 - smoothstep(0.0, _CoreUv, across);
                float body = (1.0 - smoothstep(_CoreUv, 1.0, across)) * 0.25;
                float shape = core + body;

                // Overcharge: brightness ramps with hold progress and the pulse
                // quickens with it. The opponent is meant to see this coming.
                float level = _Intensity;
                level *= 1.0 + _PulseAmount * 0.55 * sin(_PulsePhase);

                // Burst armed: fracture the ring into arc segments.
                float fracture = 1.0 - _Armed * 0.75 * step(0.5, frac(around * 9.0));
                level *= fracture;

                // Disabled: a slow dim sweep travels the ring so it reads as
                // "off" rather than merely dark.
                if (_Sweep >= 0.0)
                {
                    float d = abs(frac(around - _Sweep + 0.5) - 0.5);
                    level *= 0.35 + 0.65 * smoothstep(0.0, 0.22, d);
                }

                float3 rgb = _RingColor.rgb * shape * level;
                rgb += _RingColor.rgb * shape * _Flash * 4.0;
                rgb *= _BaseIntensity;
                return half4(rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
