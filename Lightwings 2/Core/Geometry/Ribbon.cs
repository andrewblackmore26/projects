using System;
using System.Collections.Generic;

namespace Lightship.Core.Geometry
{
    /// <summary>
    /// Turns a polyline into a ribbon (two vertices per ring) with exact UVs:
    /// U runs 0..1 along the path and V is -1..1 across it. The running light
    /// lives entirely in the shader, driven by U, so the mesh is only rebuilt
    /// when the geometry itself changes.
    ///
    /// Joints are mitred up to MitreLimit (the mitre length over the
    /// half-width). Past it (interior angles under about 60 degrees: triangle
    /// tips, prongs, chevron points) the joint is BEVELLED: two rings at the
    /// corner, one on each edge's own normal, both carrying the corner's U. A
    /// long mitre there pulls its inner vertex several pixels along the
    /// bisector, which bends the U interpolation so the drawn light runs ahead
    /// of its true position (measured on the Ember's wing tip), and on thin
    /// prongs it would cross the opposite edge.
    /// </summary>
    public static class Ribbon
    {
        public const float MitreLimit = 2.0f;

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

            int rings = 0;
            for (int i = 0; i < ringCount; i++)
            {
                Vec2 p = points[i % n];
                float u = cumulative[i] / total;
                bool hasPrev = closed || i > 0;
                bool hasNext = closed || i < ringCount - 1;
                Vec2 dPrev = hasPrev ? (points[i % n] - points[Mod(i - 1, n)]).Normalized() : Vec2.Zero;
                Vec2 dNext = hasNext ? (points[(i + 1) % n] - points[i % n]).Normalized() : Vec2.Zero;

                if (!hasPrev || !hasNext)
                {
                    Vec2 nEnd = (hasNext ? dNext : dPrev).Perp();
                    AddRing(p, nEnd * halfWidth, u, verts, us, sides);
                    rings++;
                    continue;
                }

                Vec2 nPrev = dPrev.Perp(), nNext = dNext.Perp();
                Vec2 mitre = nPrev + nNext;
                float denom = mitre.LengthSquared() < 1e-8f ? 0f : Vec2.Dot(mitre.Normalized(), nPrev);
                float scale = MathF.Abs(denom) > 1e-6f ? 1f / MathF.Abs(denom) : float.MaxValue;
                if (scale <= MitreLimit)
                {
                    AddRing(p, mitre.Normalized() * (halfWidth * scale), u, verts, us, sides);
                    rings++;
                }
                else
                {
                    // Bevel: end the previous edge square, start the next edge square, same u.
                    AddRing(p, nPrev * halfWidth, u, verts, us, sides);
                    AddRing(p, nNext * halfWidth, u, verts, us, sides);
                    rings += 2;
                }
            }

            for (int r = 0; r + 1 < rings; r++)
            {
                int a = baseVertex + r * 2, b = a + 1, c = a + 2, d = a + 3;
                tris.Add(a); tris.Add(b); tris.Add(c);
                tris.Add(c); tris.Add(b); tris.Add(d);
            }
        }

        private static void AddRing(Vec2 p, Vec2 offset, float u, List<Vec2> verts, List<float> us, List<float> sides)
        {
            verts.Add(p + offset); us.Add(u); sides.Add(1f);
            verts.Add(p - offset); us.Add(u); sides.Add(-1f);
        }

        private static int Mod(int a, int m) => ((a % m) + m) % m;
    }
}
