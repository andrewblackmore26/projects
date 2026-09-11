using System;

namespace Lightship.Core.Geometry
{
    /// <summary>
    /// The running light (spec 11.5, Appendix B): one bright segment covering
    /// a fraction of the perimeter, travelling one full lap per period. The
    /// shader implements exactly these formulas on UV.x; the sheet measurement
    /// uses them to know where the bright pixel must be.
    /// </summary>
    public static class LightSegment
    {
        public const float DefaultFraction = 0.13f;

        /// <summary>Where the lit segment starts (u in 0..1) at simulation time t.</summary>
        public static float Offset(float period, float phase, float t) => Frac((t + phase) / period);

        /// <summary>Whether perimeter fraction u is inside the lit segment that starts at offset.</summary>
        public static bool IsLit(float u, float offset, float fraction = DefaultFraction) =>
            Frac(u - offset) < fraction;

        /// <summary>The middle of the lit segment: where the light is brightest and least ambiguous.</summary>
        public static float LitCentreU(float offset, float fraction = DefaultFraction) =>
            Frac(offset + fraction * 0.5f);

        /// <summary>A point half a lap away from the lit centre, guaranteed dark.</summary>
        public static float DarkU(float offset, float fraction = DefaultFraction) =>
            Frac(LitCentreU(offset, fraction) + 0.5f);

        public static float Frac(float x) => x - MathF.Floor(x);
    }
}
