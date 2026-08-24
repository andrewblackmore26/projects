using UnityEngine;
using CoreOwner = Gridlock.Core.Owner;

namespace Gridlock.View
{
    /// <summary>
    /// The spec section 8.2 palette. Mirrors the Godot layer's Palette so the
    /// two engines are compared on rendering and feel, not on colour choices.
    ///
    /// Values are written with components ABOVE 1.0 and the bloom pass turns
    /// them into light. Emission multipliers are headroom under the bloom
    /// threshold, not display values, so they are never "corrected" for a
    /// transfer curve.
    /// </summary>
    public static class UPalette
    {
        public static readonly Color Background = Hex("05070D");
        public static readonly Color PlayerBase = Hex("00E5FF");
        public static readonly Color AiBase = Hex("FF8A00");
        public static readonly Color NeutralBase = Hex("5A6070");
        public static readonly Color WireUnpowered = Hex("2A3040");
        public static readonly Color ContestWhite = Color.white;

        public const float OwnerEmission = 3.0f;
        public const float NeutralEmission = 0.8f;
        public const float ContestEmission = 6.0f;

        public static Color Hdr(Color c, float emission) =>
            new Color(c.r * emission, c.g * emission, c.b * emission, 1f);

        public static Color OwnerColor(CoreOwner owner)
        {
            if (owner == CoreOwner.Player) return PlayerBase;
            if (owner == CoreOwner.Ai) return AiBase;
            return NeutralBase;
        }

        public static Color OwnerHdr(CoreOwner owner) =>
            owner == CoreOwner.Neutral
                ? Hdr(NeutralBase, NeutralEmission)
                : Hdr(OwnerColor(owner), OwnerEmission);

        public static Color WireEndColor(CoreOwner owner) =>
            owner == CoreOwner.Neutral ? WireUnpowered : Hdr(OwnerColor(owner), OwnerEmission * 0.55f);

        /// <summary>
        /// Parse without ColorUtility so the value is exact and does not depend
        /// on the project's colour space setting.
        /// </summary>
        private static Color Hex(string rgb)
        {
            int v = System.Convert.ToInt32(rgb, 16);
            return new Color(((v >> 16) & 0xFF) / 255f, ((v >> 8) & 0xFF) / 255f, (v & 0xFF) / 255f, 1f);
        }
    }
}
