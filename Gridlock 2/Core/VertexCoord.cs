using System;

namespace Gridlock.Core
{
    /// <summary>
    /// Integer coordinate for a vertex of the hex-cell lattice (the honeycomb of
    /// hex corners). Wires route along lattice EDGES between these vertices
    /// (spec §4.1: wires run along hex cell edges and turn at vertices).
    ///
    /// Scheme: vertex (n, m) sits at pixel (n·√3/2, m/2) in lattice units
    /// (cell circumradius 1). A cell (q, r) has vertex-space centre
    /// (nc, mc) = (2q + r, 3r) and corners (nc±1, mc±1), (nc, mc±2).
    ///
    /// Not every (n, m) is a vertex. Rows m ≡ 0 (mod 3) hold only cell centres.
    /// For m ≡ 1 (mod 3) (floor mod): valid iff n ≡ (m-1)/3 + 1 (mod 2).
    /// For m ≡ 2 (mod 3):             valid iff n ≡ (m-2)/3     (mod 2).
    /// (Derived from the corner formulas; both divisions are exact.)
    ///
    /// Lattice edges are exactly the deltas (0, ±2) and (±1, ±1) between two
    /// VALID vertices — every such edge has pixel length exactly 1 (one lattice
    /// unit), so a wire's length equals its segment count. Each vertex has
    /// exactly 3 incident edges (honeycomb).
    /// </summary>
    public struct VertexCoord : IEquatable<VertexCoord>
    {
        public int N;
        public int M;

        public VertexCoord(int n, int m)
        {
            N = n;
            M = m;
        }

        /// <summary>Pixel position in lattice units (Y-up, matching HexMath.HexToPixel).</summary>
        public Vec2 ToPixel() => new Vec2(N * (HexMath.Sqrt3 * 0.5f), M * 0.5f);

        /// <summary>True if (n, m) names an actual honeycomb vertex (see class remarks).</summary>
        public bool IsValidVertex()
        {
            int mod3 = HexMath.Mod(M, 3);
            if (mod3 == 0) return false;
            if (mod3 == 1)
            {
                int r1 = (M - 1) / 3; // exact: M-1 is a multiple of 3 (floor-mod 1)
                return HexMath.Mod(N, 2) == HexMath.Mod(r1 + 1, 2);
            }
            int r2 = (M - 2) / 3; // exact: M-2 is a multiple of 3 (floor-mod 2)
            return HexMath.Mod(N, 2) == HexMath.Mod(r2, 2);
        }

        /// <summary>The six candidate edge deltas; validity of the far vertex filters them to 3.</summary>
        public static readonly VertexCoord[] EdgeDeltas =
        {
            new VertexCoord(0, 2),
            new VertexCoord(0, -2),
            new VertexCoord(1, 1),
            new VertexCoord(1, -1),
            new VertexCoord(-1, 1),
            new VertexCoord(-1, -1),
        };

        /// <summary>
        /// True if a—b is a lattice edge: both vertices valid and the delta is one
        /// of the edge deltas. (Both-valid + delta-in-set is a complete test: from
        /// any valid vertex, exactly 3 of the 6 deltas land on valid vertices.)
        /// </summary>
        public static bool IsLatticeEdge(VertexCoord a, VertexCoord b)
        {
            if (!a.IsValidVertex() || !b.IsValidVertex()) return false;
            int dn = b.N - a.N;
            int dm = b.M - a.M;
            if (dn == 0) return dm == 2 || dm == -2;
            if (dn == 1 || dn == -1) return dm == 1 || dm == -1;
            return false;
        }

        public bool Equals(VertexCoord other) => N == other.N && M == other.M;
        public override bool Equals(object obj) => obj is VertexCoord v && Equals(v);
        public override int GetHashCode() => N * 397 ^ M;
        public override string ToString() => "(" + N + ", " + M + ")";

        public static bool operator ==(VertexCoord a, VertexCoord b) => a.Equals(b);
        public static bool operator !=(VertexCoord a, VertexCoord b) => !a.Equals(b);
    }

    /// <summary>
    /// Canonical unordered key for a lattice edge, for global edge-uniqueness
    /// checks in the level loader (no two wires may share an edge — which also
    /// enforces one-wire-per-face and degree ≤ 6).
    /// </summary>
    public struct EdgeKey : IEquatable<EdgeKey>
    {
        public readonly int N1, M1, N2, M2;

        public EdgeKey(VertexCoord a, VertexCoord b)
        {
            bool aFirst = a.N < b.N || (a.N == b.N && a.M <= b.M);
            if (aFirst) { N1 = a.N; M1 = a.M; N2 = b.N; M2 = b.M; }
            else { N1 = b.N; M1 = b.M; N2 = a.N; M2 = a.M; }
        }

        public bool Equals(EdgeKey other) =>
            N1 == other.N1 && M1 == other.M1 && N2 == other.N2 && M2 == other.M2;
        public override bool Equals(object obj) => obj is EdgeKey k && Equals(k);
        public override int GetHashCode() =>
            ((N1 * 397 ^ M1) * 397 ^ N2) * 397 ^ M2;
    }
}
