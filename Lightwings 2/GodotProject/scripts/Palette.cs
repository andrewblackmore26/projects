using Godot;
using Lightship.Core.Ships;

namespace Lightship.View
{
    /// <summary>
    /// Appendix A, verbatim. The look is an HDR pipeline, not painted art:
    /// running lights, cores and bullets are written with components ABOVE 1.0
    /// and the glow pass turns them into light. Emission multipliers are NOT
    /// display values and must never be "corrected" for any transfer curve;
    /// they are the headroom the bloom threshold sits under.
    ///
    /// Every colour here is written raw (no source_color hints, no conversion):
    /// the hdr_2d pipeline treats canvas output as sRGB, and the capture path
    /// re-encodes to sRGB, so a written #050507 measures as #050507.
    /// </summary>
    public static class Palette
    {
        public static readonly Color Playfield = new Color("050507");
        public static readonly Color VoidHull = new Color("000000");

        /// <summary>Base strokes sit just under the glow threshold.</summary>
        public const float StrokeLevel = 0.92f;
        /// <summary>Running lights: pale tint x 1.8, above the threshold.</summary>
        public const float LightEmission = 1.8f;
        public const float CoreEmission = 1.8f;
        public const float BulletEmission = 1.8f;
        public const float PickupStrokeLevel = 0.92f;

        // Indexed by (int)ColorRole. Order must match the enum exactly.
        public static readonly Color[] Stroke =
        {
            new Color("6fd3ff"), // PlayerBlue
            new Color("ff5436"), // FireRed
            new Color("ffd23f"), // LightningYellow
            new Color("45e06a"), // CorruptionGreen
            new Color("a97dff"), // Violet
            new Color("9aa3b3"), // VoidSilver
            new Color("ffd23f"), // VoidGold
            new Color("ffffff"), // White
        };

        public static readonly Color[] Fill =
        {
            new Color("08233a"), // PlayerBlue
            new Color("2a0b08"), // FireRed
            new Color("2a2206"), // LightningYellow
            new Color("062a12"), // CorruptionGreen
            new Color("1d1233"), // Violet
            new Color("000000"), // VoidSilver: the void hull is pure black
            new Color("000000"), // VoidGold (on black)
            new Color("ffffff"), // White
        };

        public static readonly Color[] Light =
        {
            new Color("dcf5ff"), // PlayerBlue
            new Color("ffc6b5"), // FireRed
            new Color("fff3bd"), // LightningYellow
            new Color("caffd5"), // CorruptionGreen
            new Color("e4d6ff"), // Violet
            new Color("ffffff"), // VoidSilver
            new Color("fff3bd"), // VoidGold
            new Color("ffffff"), // White
        };

        public static Color StrokeOf(ColorRole role) => Stroke[(int)role];
        public static Color FillOf(ColorRole role) => Fill[(int)role];
        public static Color LightOf(ColorRole role) => Light[(int)role];

        /// <summary>Scale a colour above 1.0 for the glow pass (alpha stays 1).</summary>
        public static Color Hdr(Color c, float emission) => new Color(c.R * emission, c.G * emission, c.B * emission, 1f);
    }
}
