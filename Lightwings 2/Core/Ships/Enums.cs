namespace Lightship.Core.Ships
{
    /// <summary>Light types / rival AI code dialects (spec 6). None = the tier-1 seed before a root is chosen.</summary>
    public enum Element
    {
        None = 0,
        Fire = 1,
        Lightning = 2,
        Void = 3,
        Corruption = 4,
    }

    /// <summary>
    /// Colour roles from Appendix A. The order is the palette index used by the
    /// renderer and packed into vertex data, so it must never be reordered.
    /// </summary>
    public enum ColorRole
    {
        PlayerBlue = 0,
        FireRed = 1,
        LightningYellow = 2,
        CorruptionGreen = 3,
        Violet = 4,
        VoidSilver = 5,
        VoidGold = 6,
        White = 7,
    }

    /// <summary>Primitives a lightship is built from (spec 11.1).</summary>
    public enum Shape
    {
        Circle,
        Ellipse,
        Triangle,
        Prong,
        Diamond,
        Chevron,
        Hexagon,
        Crescent,
        Arc,
        Ring,
        Tether,
    }

    /// <summary>Draw order (spec 11.2): reference rings, tethers, outer parts, body, components, core.</summary>
    public enum PartLayer
    {
        Ring = 0,
        Tether = 1,
        Outer = 2,
        Body = 3,
        Component = 4,
    }
}
