using System;

namespace Lightship.Core
{
    public static class Easing
    {
        public static float Clamp01(float t) => t < 0f ? 0f : (t > 1f ? 1f : t);

        /// <summary>Ease in-out, used by the reshape tween and the breathing curve.</summary>
        public static float SmoothStep(float t)
        {
            t = Clamp01(t);
            return t * t * (3f - 2f * t);
        }

        public static float Lerp(float a, float b, float t) => a + (b - a) * t;

        /// <summary>Lerp between angles in degrees along the shortest arc; the endpoints are returned exactly.</summary>
        public static float LerpAngleDeg(float a, float b, float t)
        {
            if (t <= 0f) return a;
            if (t >= 1f) return b;
            float d = ((b - a) % 360f + 540f) % 360f - 180f;
            return a + d * t;
        }

        /// <summary>
        /// Spec 11.6: uniform scale 1.00 -> 1.05 -> 1.00 over the period, ease
        /// in-out (a raised cosine is exactly that), with a per-ship phase.
        /// </summary>
        public static float Breath(float timeSeconds, float period, float amplitude, float phase)
        {
            float c = MathF.Cos(2f * MathF.PI * (timeSeconds + phase) / period);
            return 1f + amplitude * 0.5f * (1f - c);
        }
    }
}
