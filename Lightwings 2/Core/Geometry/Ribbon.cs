using System;
using System.Collections.Generic;

namespace Lightship.Core.Geometry
{
    /// <summary>
    /// Turns a polyline into a ribbon (two vertices per point) with exact UVs:
    /// U runs 0..1 along the path and V is -1..1 across it. The running light
    /// lives entirely in the shader, driven by U, so the mesh is only rebuilt
    /// when the geometry itself changes.
    ///
    /// Joints are mitred with the mitre length clamped, so a prong tip gets a
    /// short spike rather than a mile-long one, and no gaps open at corners.
    /// </summary>
    public static class Ribbon
    {
        public const float MitreClamp = 0.35f;

        /// <summary>
        /// Appends ring vertices (position, u, side) and quad triangles. The
        /// closing ring of a closed loop repeats point 0 at u = 1.
        /// </summary>
        public static void Extrude(Vec2[] points, bool closed, float halfWidth,
            List<Vec2> verts, List<float> us, List<float> sides, List<int> tris)
        {
            int n = points.Length;
            if (n < 2) return;
            int ringCount = closed ? n + 1 : n;
            int baseVertex = verts.Count;

            var cumulative = new float[ringCount];
            float total = 0f;
            for (int i = 1; i < ringCount; i++)
            {
                total += Vec2.Distance(points[(i - 1) % n], points[i % n]);
                cumulative[i] = total;
            }
            if (total <= 1e-9f) return;

            for (int i = 0; i < ringCount; i++)
            {
                Vec2 p = points[i % n];
                Vec2 normal = NormalAt(points, n, i, ringCount, closed, out float scale);
                Vec2 offset = normal * (halfWidth * scale);
                float u = cumulative[i] / total;
                verts.Add(p + offset); us.Add(u); sides.Add(1f);
                verts.Add(p - offset); us.Add(u); sides.Add(-1f);
            }

            for (int i = 0; i + 1 < ringCount; i++)
            {
                int a = baseVertex + i * 2, b = a + 1, c = a + 2, d = a + 3;
                tris.Add(a); tris.Add(b); tris.Add(c);
                tris.Add(c); tris.Add(b); tris.Add(d);
            }
        }

        private static Vec2 NormalAt(Vec2[] points, int n, int i, int ringCount, bool closed, out float scale)
        {
            scale = 1f;
            bool hasPrev = closed || i > 0;
            bool hasNext = closed || i < ringCount - 1;

            Vec2 dPrev = hasPrev ? (points[i % n] - points[Mod(i - 1, n)]).Normalized() : Vec2.Zero;
            Vec2 dNext = hasNext ? (points[(i + 1) % n] - points[i % n]).Normalized() : Vec2.Zero;

            if (!hasPrev) return dNext.Perp();
            if (!hasNext) return dPrev.Perp();

            Vec2 nPrev = dPrev.Perp();
            Vec2 nNext = dNext.Perp();
            Vec2 mitre = nPrev + nNext;
            if (mitre.LengthSquared() < 1e-8f) return nPrev;   // doubled back
            mitre = mitre.Normalized();
            float denom = Vec2.Dot(mitre, nPrev);
            scale = 1f / MathF.Max(MathF.Abs(denom), MitreClamp);
            return mitre;
        }

        private static int Mod(int a, int m) => ((a % m) + m) % m;
    }
}
