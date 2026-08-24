// A wire is a thin ribbon mesh: UV.x is the wire parameter t (0 at node A, 1 at
// node B), UV.y is the across-coordinate in [-1, 1]. Everything that moves --
// beams, the contest front -- arrives as a MaterialPropertyBlock value, never as
// a moved transform (spec 8.4), so the whole board is a handful of draw calls
// and the motion is exact at any framerate.
//
// Colours are written with components ABOVE 1.0 on purpose: the crisp core is
// what the camera's HDR buffer hands to URP's bloom. Never widen the core to
// fake a glow.
Shader "Gridlock/Wire"
{
    Properties
    {
        _OwnerColorA ("Owner Colour A", Color) = (0.35, 0.38, 0.44, 1)
        _OwnerColorB ("Owner Colour B", Color) = (0.35, 0.38, 0.44, 1)
        _BoundaryT ("Boundary T", Float) = 0.5
        _BaseIntensity ("Base Intensity", Float) = 1
        _CoreUv ("Core Half-Width (UV)", Float) = 0.22
        _ContestActive ("Contest Active", Float) = 0
        _ContestColor ("Contest Colour", Color) = (6, 6, 6, 1)
        _ContestHeat ("Contest Heat", Float) = 1
        _PulseCount ("Pulse Count", Integer) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" }
        Blend One One          // additive: neon on a dark ground, no black quad edges
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #define MAX_PULSES 8

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            // Deliberately outside a CBUFFER: these are per-renderer values set
            // through MaterialPropertyBlock, which opts out of SRP batching anyway.
            float4 _OwnerColorA;
            float4 _OwnerColorB;
            float _BoundaryT;
            float _BaseIntensity;
            float _CoreUv;
            float _ContestActive;
            float4 _ContestColor;
            float _ContestHeat;
            int _PulseCount;
            float _PulsePos[MAX_PULSES];
            float _PulseSize[MAX_PULSES];
            float4 _PulseColor[MAX_PULSES];

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.uv = input.uv;
                return o;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float t = input.uv.x;
                float across = abs(input.uv.y);

                // Crisp core plus a soft body. The body reads as a wire at rest;
                // the core is what the bloom threshold catches.
                float core = 1.0 - smoothstep(0.0, _CoreUv, across);
                float body = (1.0 - smoothstep(_CoreUv, 1.0, across)) * 0.22;

                float3 base = lerp(_OwnerColorA.rgb, _OwnerColorB.rgb, step(_BoundaryT, t));
                float3 rgb = base * (core + body);

                // Travelling charge: a bright bead, brightest at its centre.
                [unroll]
                for (int i = 0; i < MAX_PULSES; i++)
                {
                    if (i < _PulseCount)
                    {
                        float d = abs(t - _PulsePos[i]);
                        float sigma = max(_PulseSize[i] * _PulseSize[i], 1e-6);
                        float falloff = exp(-(d * d) / sigma);
                        rgb += _PulseColor[i].rgb * falloff * (core + body * 2.0);
                    }
                }

                // The contact point: the brightest thing on the board, with
                // sparks added on top by UContestView (spec 8.5).
                float dc = abs(t - _BoundaryT);
                float hot = exp(-(dc * dc) / max(0.0006 * _ContestHeat, 1e-6));
                rgb += _ContestColor.rgb * hot * _ContestActive * (core + body * 3.0);

                rgb *= _BaseIntensity;
                return half4(rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
