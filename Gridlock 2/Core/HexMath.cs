using System;

namespace Gridlock.Core
{
    /// <summary>
    /// All cell-level lattice geometry in one place, shared verbatim by the
    /// simulation, both presentation layers, the level loader, and tooling.
    ///
    /// Board model (continuous-time spec §4): a single axial pointy-top lattice;
    /// HexCoord is a cell. Nodes sit in cells. Wires do NOT run through cell
    /// centres — they run along cell EDGES and turn at VERTICES (see VertexCoord
    /// for the vertex/edge lattice). Cell circumradius is 1 lattice unit, which
    /// makes every lattice edge exactly 1 unit long. Y-up.
    /// </summary>
    public static class HexMath
    {
        public const float Sqrt3 = 1.7320508075688772f;

        /// <summary>
        /// Neighbour offsets by direction (face) index 0..5, matching pixel angles
        /// under HexToPixel: 0=E(0°), 1=NE(60°), 2=NW(120°), 3=W(180°), 4=SW(240°), 5=SE(300°).
        /// A wire occupies one face of each endpoint node; its first path segment IS
        /// that face's edge (see FaceEdge).
        /// </summary>
        public static readonly HexCoord[] CellDirections =
        {
            new HexCoord(1, 0),   // 0 E
            new HexCoord(0, 1),   // 1 NE
            new HexCoord(-1, 1),  // 2 NW
            new HexCoord(-1, 0),  // 3 W
            new HexCoord(0, -1),  // 4 SW
            new HexCoord(1, -1),  // 5 SE
        };

        /// <summary>The adjacent cell in direction 0..5.</summary>
        public static HexCoord Neighbour(HexCoord h, int dir)
        {
            HexCoord d = CellDirections[dir];
            return new HexCoord(h.Q + d.Q, h.R + d.R);
        }

        /// <summary>Direction index 0..5 from one cell to an adjacent cell; -1 if not adjacent.</summary>
        public static int DirectionIndex(HexCoord from, HexCoord to)
        {
            int dq = to.Q - from.Q;
            int dr = to.R - from.R;
            for (int i = 0; i < 6; i++)
            {
                if (CellDirections[i].Q == dq && CellDirections[i].R == dr) return i;
            }
            return -1;
        }

        /// <summary>Hex grid distance between two cells, in steps.</summary>
        public static int CellDistance(HexCoord a, HexCoord b)
        {
            int dq = b.Q - a.Q;
            int dr = b.R - a.R;
            int ds = dq + dr;
            return (Math.Abs(dq) + Math.Abs(dr) + Math.Abs(ds)) / 2;
        }

        /// <summary>Pixel position of a cell centre, in lattice units.</summary>
        public static Vec2 HexToPixel(HexCoord h) =>
            new Vec2(Sqrt3 * (h.Q + h.R * 0.5f), 1.5f * h.R);

        /// <summary>
        /// Pixel position of a cell's corner i (0..5), at angle 30° + 60°·i,
        /// circumradius 1. Prefer CornerVertex + VertexCoord.ToPixel for anything
        /// the simulation touches; this float form is presentation-only.
        /// </summary>
        public static Vec2 CellCorner(HexCoord h, int i)
        {
            Vec2 c = HexToPixel(h);
            float angle = (30f + 60f * i) * (MathF.PI / 180f);
            return new Vec2(c.X + MathF.Cos(angle), c.Y + MathF.Sin(angle));
        }

        /// <summary>Nearest cell to a pixel position (for input picking and the editor).</summary>
        public static HexCoord PixelToHex(Vec2 p)
        {
            // Invert the axial-to-pixel transform, then cube-round.
            float q = p.X / Sqrt3 - p.Y / 3f;
            float r = p.Y / 1.5f;
            return CubeRound(q, r);
        }

        private static HexCoord CubeRound(float q, float r)
        {
            float s = -q - r;
            int rq = (int)MathF.Round(q);
            int rr = (int)MathF.Round(r);
            int rs = (int)MathF.Round(s);
            float dq = MathF.Abs(rq - q);
            float dr = MathF.Abs(rr - r);
            float ds = MathF.Abs(rs - s);
            if (dq > dr && dq > ds) rq = -rr - rs;
            else if (dr > ds) rr = -rq - rs;
            return new HexCoord(rq, rr);
        }

        // ---- Vertex-lattice bridge (see VertexCoord for the (n, m) scheme) ----

        /// <summary>
        /// Integer corner-offset table, corner i at angle 30° + 60°·i around the
        /// cell's vertex-space centre (nc, mc) = (2q + r, 3r).
        /// </summary>
        private static readonly int[,] CornerOffsets =
        {
            { 1, 1 },   // 0:  30°
            { 0, 2 },   // 1:  90°
            { -1, 1 },  // 2: 150°
            { -1, -1 }, // 3: 210°
            { 0, -2 },  // 4: 270°
            { 1, -1 },  // 5: 330°
        };

        /// <summary>Corner i (0..5) of a cell as an exact lattice vertex.</summary>
        public static VertexCoord CornerVertex(HexCoord h, int i)
        {
            int nc = 2 * h.Q + h.R;
            int mc = 3 * h.R;
            return new VertexCoord(nc + CornerOffsets[i, 0], mc + CornerOffsets[i, 1]);
        }

        /// <summary>
        /// The two vertices of face f (0..5, CellDirections order). Face f, at
        /// angle 60°·f, spans corners at 60°·f ∓ 30°, i.e. corners (f+5)%6 and f.
        /// </summary>
        public static void FaceEdge(HexCoord h, int face, out VertexCoord a, out VertexCoord b)
        {
            a = CornerVertex(h, (face + 5) % 6);
            b = CornerVertex(h, face);
        }

        /// <summary>
        /// Face index 0..5 whose edge is the unordered vertex pair {a, b}; -1 if
        /// {a, b} is not a face edge of this cell. Exact integer lookup — no
        /// geometric nearest-face guessing (a radial corner departure would tie).
        /// </summary>
        public static int FaceIndexOfEdge(HexCoord h, VertexCoord a, VertexCoord b)
        {
            for (int f = 0; f < 6; f++)
            {
                FaceEdge(h, f, out VertexCoord fa, out VertexCoord fb);
                if ((fa == a && fb == b) || (fa == b && fb == a)) return f;
            }
            return -1;
        }

        /// <summary>True if v is one of the six corners of cell h.</summary>
        public static bool IsCornerOf(HexCoord h, VertexCoord v)
        {
            int nc = 2 * h.Q + h.R;
            int mc = 3 * h.R;
            int dn = v.N - nc;
            int dm = v.M - mc;
            for (int i = 0; i < 6; i++)
            {
                if (CornerOffsets[i, 0] == dn && CornerOffsets[i, 1] == dm) return true;
            }
            return false;
        }

        public static int Mod(int a, int m)
        {
            int r = a % m;
            return r < 0 ? r + m : r;
        }
    }
}
