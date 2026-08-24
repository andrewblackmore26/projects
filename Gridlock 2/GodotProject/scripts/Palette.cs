using Godot;
using Gridlock.Core;

namespace Gridlock.View
{
    /// <summary>
    /// The spec section 8.2 palette, in one place.
    ///
    /// The look is an HDR pipeline, not painted art: colours are written with
    /// components ABOVE 1.0 and the glow pass turns them into light. Emission
    /// multipliers are therefore NOT display values and must never be "corrected"
    /// for any transfer curve -- they are the headroom the bloom threshold sits
    /// under. Only values that must MEASURE correctly on screen (the background)
    /// go through Screen().
    /// </summary>
    public static class Palette
    {
        public static readonly Color Background = new Color("05070D");
        public static readonly Color PlayerBase = new Color("00E5FF");
        public static readonly Color AiBase = new Color("FF8A00");
        public static readonly Color NeutralBase = new Color("5A6070");
        public static readonly Color WireUnpowered = new Color("2A3040");
        public static readonly Color ContestWhite = new Color("FFFFFF");

        public const float OwnerEmission = 3.0f;
        public const float NeutralEmission = 0.8f;
        public const float ContestEmission = 6.0f;

        /// <summary>
        /// Identity transfer. The tonemapper is set to Linear and the glow pass
        /// is additive above threshold, so a written value at or below 1.0 lands
        /// unchanged on screen -- verified by measuring a captured frame
        /// (Tools/measure_frame.py). If a future post-processing change breaks
        /// that, invert it HERE rather than fudging individual colours.
        /// </summary>
        public static Color Screen(Color c) => c;

        public static Color Hdr(Color c, float emission) =>
            new Color(c.R * emission, c.G * emission, c.B * emission, 1f);

        public static Color OwnerColor(Owner owner)
        {
            switch (owner)
            {
                case Owner.Player: return PlayerBase;
                case Owner.Ai: return AiBase;
                default: return NeutralBase;
            }
        }

        /// <summary>Full-strength HDR colour for an owner (nodes, beams, wire halves).</summary>
        public static Color OwnerHdr(Owner owner) =>
            owner == Owner.Neutral
                ? Hdr(NeutralBase, NeutralEmission)
                : Hdr(OwnerColor(owner), OwnerEmission);

        /// <summary>Wire colour for the half nearest a node: dim grey while nobody holds it.</summary>
        public static Color WireEndColor(Owner owner) =>
            owner == Owner.Neutral ? WireUnpowered : Hdr(OwnerColor(owner), OwnerEmission * 0.55f);
    }
}
