using System;

namespace Gridlock.Core
{
    /// <summary>
    /// Axial coordinate for a pointy-top hex cell. See HexMath for the geometry.
    /// </summary>
    public struct HexCoord : IEquatable<HexCoord>
    {
        public int Q;
        public int R;

        public HexCoord(int q, int r)
        {
            Q = q;
            R = r;
        }

        public bool Equals(HexCoord other) => Q == other.Q && R == other.R;
        public override bool Equals(object obj) => obj is HexCoord h && Equals(h);
        public override int GetHashCode() => Q * 397 ^ R;
        public override string ToString() => "(" + Q + ", " + R + ")";

        public static bool operator ==(HexCoord a, HexCoord b) => a.Equals(b);
        public static bool operator !=(HexCoord a, HexCoord b) => !a.Equals(b);
    }
}
