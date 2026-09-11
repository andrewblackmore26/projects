using System;
using System.Collections.Generic;

namespace Lightship.Core.Geometry
{
    /// <summary>
    /// Closed outlines for every primitive (spec 11.1), in part-local units,
    /// centred on the position of the part, unrotated. Forward is -Y. Angles
    /// in degrees are measured from forward, clockwise on screen.
    /// </summary>
    public static class Outline
    {
        public const int MinPoints = 16;
        public const int MaxPoints = 64;
        private const float TwoPi = 2f * MathF.PI;

        /// <summary>About one point per 3 units of perimeter, clamped so small circles still look round.</summary>
        public static int PointsFor(float perimeter) =>
            Math.Clamp((int)MathF.Round(perimeter / 3f), MinPoints, MaxPoints);

        public static Vec2[] Circle(float r) => Ellipse(r, r);

        public static Vec2[] Ellipse(float rx, float ry)
        {
            // The Ramanujan approximation is plenty for choosing a point count.
            float h = (rx - ry) * (rx - ry) / MathF.Max((rx + ry) * (rx + ry), 1e-6f);
            float perimeter = MathF.PI * (rx + ry) * (1f + 3f * h / (10f + MathF.Sqrt(4f - 3f * h)));
            int n = PointsFor(perimeter);
            var pts = new Vec2[n];
            for (int k = 0; k < n; k++)
            {
                float a = -MathF.PI / 2f + TwoPi * k / n;   // start at the front, go clockwise on screen
                pts[k] = new Vec2(rx * MathF.Cos(a), ry * MathF.Sin(a));
            }
            return pts;
        }

        public static Vec2[] Triangle(float b, float h) =>
            new[] { new Vec2(0f, -h / 2f), new Vec2(b / 2f, h / 2f), new Vec2(-b / 2f, h / 2f) };

        /// <summary>Thin triangle; the loader warns when length is under 4x base (spec 11.1).</summary>
        public static Vec2[] Prong(float b, float length) => Triangle(b, length);

        public static Vec2[] Diamond(float w, float h) =>
            new[] { new Vec2(0f, -h / 2f), new Vec2(w / 2f, 0f), new Vec2(0f, h / 2f), new Vec2(-w / 2f, 0f) };

        /// <summary>Four-point kite: tip forward, two swept wings, a notch at the rear (notch 0..1 of height).</summary>
        public static Vec2[] Chevron(float w, float h, float notch) =>
            new[] { new Vec2(0f, -h / 2f), new Vec2(w / 2f, h / 2f), new Vec2(0f, h / 2f - notch * h), new Vec2(-w / 2f, h / 2f) };

        public static Vec2[] Hexagon(float r)
        {
            var pts = new Vec2[6];
            for (int k = 0; k < 6; k++)
            {
                float a = -MathF.PI / 2f + k * MathF.PI / 3f;   // pointy-forward
                pts[k] = new Vec2(r * MathF.Cos(a), r * MathF.Sin(a));
            }
            return pts;
        }

        /// <summary>
        /// Circle A (radius r at the origin) minus circle B (radius rc at the
        /// offset): the outer arc of A outside B, then the inner arc of B inside
        /// A. One simple closed loop. Throws when the circles do not intersect,
        /// because then there is no crescent to draw.
        /// </summary>
        public static Vec2[] Crescent(float r, float rc, float dx, float dy)
        {
            var off = new Vec2(dx, dy);
            float d = off.Length();
            if (d <= 1e-6f || d >= r + rc || d <= MathF.Abs(r - rc))
                throw new ArgumentException("crescent circles must intersect: radius " + r + ", cut_radius " + rc + ", offset " + d);

            float a = (d * d + r * r - rc * rc) / (2f * d);
            float h = MathF.Sqrt(MathF.Max(0f, r * r - a * a));
            Vec2 dir = off / d;
            Vec2 p = dir * a;
            Vec2 perp = dir.Perp();
            Vec2 i1 = p + perp * h, i2 = p - perp * h;
            float phi = dir.Angle();
            float away = phi + MathF.PI;

            // Outer arc on A from i1 to i2, through the direction away from B.
            float a1 = i1.Angle(), a2 = i2.Angle();
            float sweepA = SweepThrough(a1, a2, away);
            int nA = Math.Max(8, (int)MathF.Round(MathF.Abs(sweepA) * r / 3f));
            // Inner arc on B from i2 to i1, through the direction facing A (from B, that is also phi + pi).
            float b2 = (i2 - off).Angle(), b1 = (i1 - off).Angle();
            float sweepB = SweepThrough(b2, b1, away);
            int nB = Math.Max(8, (int)MathF.Round(MathF.Abs(sweepB) * rc / 3f));

            var pts = new List<Vec2>(nA + nB);
            for (int k = 0; k < nA; k++) pts.Add(Vec2.FromAngle(a1 + sweepA * k / nA) * r);
            for (int k = 0; k < nB; k++) pts.Add(off + Vec2.FromAngle(b2 + sweepB * k / nB) * rc);
            return pts.ToArray();
        }

        /// <summary>A closed band: outer arc, then the inner arc back. start_deg from forward, clockwise.</summary>
        public static Vec2[] Arc(float r, float thickness, float startDeg, float sweepDeg)
        {
            float t = MathF.Max(thickness, 0.5f);
            float ro = r + t / 2f, ri = MathF.Max(r - t / 2f, 0.1f);
            float a0 = Rad(startDeg - 90f), sw = Rad(sweepDeg);
            int n = Math.Max(4, (int)MathF.Round(MathF.Abs(sw) * ro / 3f)) + 1;
            var pts = new Vec2[2 * n];
            for (int k = 0; k < n; k++)
            {
                float a = a0 + sw * k / (n - 1);
                pts[k] = Vec2.FromAngle(a) * ro;
                pts[2 * n - 1 - k] = Vec2.FromAngle(a) * ri;
            }
            return pts;
        }

        /// <summary>Two concentric loops with the same point count, so the fill can be a strip.</summary>
        public static void Ring(float r, float thickness, out Vec2[] outer, out Vec2[] inner)
        {
            float t = MathF.Max(thickness, 0.5f);
            float ro = r + t / 2f, ri = MathF.Max(r - t / 2f, 0.1f);
            int n = PointsFor(TwoPi * ro);
            outer = new Vec2[n];
            inner = new Vec2[n];
            for (int k = 0; k < n; k++)
            {
                float a = -MathF.PI / 2f + TwoPi * k / n;
                Vec2 d = Vec2.FromAngle(a);
                outer[k] = d * ro;
                inner[k] = d * ri;
            }
        }

        /// <summary>Signed sweep from one angle to another that passes through a third.</summary>
        private static float SweepThrough(float from, float to, float through)
        {
            float cw = Norm(to - from);
            if (cw < 1e-6f) cw = TwoPi;
            float thr = Norm(through - from);
            return thr <= cw ? cw : cw - TwoPi;
        }

        private static float Norm(float x)
        {
            x %= TwoPi;
            if (x < 0f) x += TwoPi;
            return x;
        }

        public static float Rad(float deg) => deg * MathF.PI / 180f;

        /// <summary>Length of a polyline, closing it when asked.</summary>
        public static float Length(Vec2[] pts, bool closed)
        {
            float total = 0f;
            for (int i = 1; i < pts.Length; i++) total += Vec2.Distance(pts[i - 1], pts[i]);
            if (closed && pts.Length > 1) total += Vec2.Distance(pts[pts.Length - 1], pts[0]);
            return total;
        }

        /// <summary>Shoelace area; positive for a clockwise-on-screen loop (+Y down).</summary>
        public static float SignedArea(Vec2[] pts)
        {
            float a = 0f;
            for (int i = 0; i < pts.Length; i++)
            {
                Vec2 p = pts[i], q = pts[(i + 1) % pts.Length];
                a += p.X * q.Y - q.X * p.Y;
            }
            return 0.5f * a;
        }

        public static Vec2 Centroid(Vec2[] pts)
        {
            float a = 0f, cx = 0f, cy = 0f;
            for (int i = 0; i < pts.Length; i++)
            {
                Vec2 p = pts[i], q = pts[(i + 1) % pts.Length];
                float c = p.X * q.Y - q.X * p.Y;
                a += c; cx += (p.X + q.X) * c; cy += (p.Y + q.Y) * c;
            }
            if (MathF.Abs(a) < 1e-9f) return pts.Length > 0 ? pts[0] : Vec2.Zero;
            return new Vec2(cx / (3f * a), cy / (3f * a));
        }

        /// <summary>Ray-casting point-in-polygon.</summary>
        public static bool Contains(Vec2[] pts, Vec2 p)
        {
            bool inside = false;
            for (int i = 0, j = pts.Length - 1; i < pts.Length; j = i++)
            {
                Vec2 a = pts[i], b = pts[j];
                if ((a.Y > p.Y) != (b.Y > p.Y))
                {
                    float x = (b.X - a.X) * (p.Y - a.Y) / (b.Y - a.Y) + a.X;
                    if (p.X < x) inside = !inside;
                }
            }
            return inside;
        }

        /// <summary>True when no two non-adjacent edges cross (a self-intersecting outline is a data bug).</summary>
        public static bool IsSimple(Vec2[] pts)
        {
            int n = pts.Length;
            for (int i = 0; i < n; i++)
            {
                Vec2 a = pts[i], b = pts[(i + 1) % n];
                for (int j = i + 2; j < n; j++)
                {
                    if (i == 0 && j == n - 1) continue;   // adjacent through the closing edge
                    Vec2 c = pts[j], d = pts[(j + 1) % n];
                    if (SegmentsCross(a, b, c, d)) return false;
                }
            }
            return true;
        }

        private static bool SegmentsCross(Vec2 a, Vec2 b, Vec2 c, Vec2 d)
        {
            float d1 = Vec2.Cross(b - a, c - a), d2 = Vec2.Cross(b - a, d - a);
            float d3 = Vec2.Cross(d - c, a - c), d4 = Vec2.Cross(d - c, b - c);
            return ((d1 > 0f) != (d2 > 0f)) && ((d3 > 0f) != (d4 > 0f)) &&
                   d1 != 0f && d2 != 0f && d3 != 0f && d4 != 0f;
        }
    }
}
