using System;
using Lightship.Core.Ships;

namespace Lightship.Core.Geometry
{
    /// <summary>
    /// One part turned into numbers: its outline in ship-local units, the
    /// perimeter fraction at each point, its fill triangles, and the bounding
    /// circle used for contact tests. Everything a test or a renderer needs.
    /// </summary>
    public sealed class PartGeometry
    {
        public string Id;
        public PartLayer Layer;
        public ColorRole Role;
        public bool IsTether;
        public bool Dashed;
        public int PeriodIndex;
        public int PhaseIndex;
        public string Component;

        /// <summary>Ship-local outline; a closed loop unless IsTether.</summary>
        public Vec2[] Outline;
        /// <summary>Perimeter fraction at each outline point, 0 at the first point.</summary>
        public float[] U;
        public float Perimeter;
        /// <summary>Rings only: the inner loop (same point count as Outline).</summary>
        public Vec2[] InnerOutline;
        public float InnerPerimeter;

        /// <summary>Fill triangles index into FillPoints (Outline for most shapes; outer + inner for rings).</summary>
        public Vec2[] FillPoints = Array.Empty<Vec2>();
        public int[] FillIndices = Array.Empty<int>();

        public Vec2 Centre;
        public float BoundRadius;
        public float Area;
        public Vec2 Min, Max;

        public float Period => LightSchedule.Periods[Math.Clamp(PeriodIndex, 0, 1)];
        public float Phase => LightSchedule.Phases[Math.Clamp(PhaseIndex, 0, 2)];

        public bool ContainsPoint(Vec2 p)
        {
            if (IsTether || Outline == null || Outline.Length < 3) return false;
            if (!Geometry.Outline.Contains(Outline, p)) return false;
            if (InnerOutline != null && Geometry.Outline.Contains(InnerOutline, p)) return false;
            return true;
        }

        /// <summary>Shortest distance from a ship-local point to this part's outline (open for tethers).</summary>
        public float DistanceToOutline(Vec2 p)
        {
            if (Outline == null || Outline.Length == 0) return float.MaxValue;
            int n = Outline.Length;
            int segments = IsTether ? n - 1 : n;
            float best = float.MaxValue;
            for (int i = 0; i < segments; i++)
            {
                Vec2 a = Outline[i], b = Outline[(i + 1) % n];
                Vec2 ab = b - a;
                float len2 = ab.LengthSquared();
                float t = len2 > 1e-12f ? Math.Clamp(Vec2.Dot(p - a, ab) / len2, 0f, 1f) : 0f;
                best = MathF.Min(best, Vec2.Distance(p, a + ab * t));
            }
            return best;
        }

        /// <summary>A circle at p with radius r touches the drawn part (filled shape, not its bounding circle).</summary>
        public bool Touches(Vec2 p, float r)
        {
            if (IsTether || Dashed) return false;
            if (Vec2.Distance(p, Centre) > BoundRadius + r) return false;
            return ContainsPoint(p) || DistanceToOutline(p) <= r;
        }

        /// <summary>Point on the outline at perimeter fraction u (wrapping), ship-local.</summary>
        public Vec2 PointAtU(float u)
        {
            if (Outline == null || Outline.Length == 0) return Centre;
            if (Outline.Length == 1) return Outline[0];
            u = IsTether ? Math.Clamp(u, 0f, 1f) : LightSegment.Frac(u);
            float target = u * Perimeter;
            int n = Outline.Length;
            int segments = IsTether ? n - 1 : n;
            float walked = 0f;
            for (int i = 0; i < segments; i++)
            {
                Vec2 a = Outline[i], b = Outline[(i + 1) % n];
                float len = Vec2.Distance(a, b);
                if (walked + len >= target || i == segments - 1)
                {
                    float t = len > 1e-9f ? Math.Clamp((target - walked) / len, 0f, 1f) : 0f;
                    return Vec2.Lerp(a, b, t);
                }
                walked += len;
            }
            return Outline[0];
        }

        internal void ComputeUAndPerimeter()
        {
            int n = Outline.Length;
            U = new float[n];
            float total = Geometry.Outline.Length(Outline, !IsTether);
            Perimeter = total;
            float walked = 0f;
            for (int i = 0; i < n; i++)
            {
                U[i] = total > 1e-9f ? walked / total : 0f;
                if (i + 1 < n) walked += Vec2.Distance(Outline[i], Outline[i + 1]);
            }
        }

        internal void ComputeBounds()
        {
            float r = 0f;
            Min = new Vec2(float.MaxValue, float.MaxValue);
            Max = new Vec2(float.MinValue, float.MinValue);
            foreach (Vec2 p in Outline)
            {
                r = MathF.Max(r, Vec2.Distance(Centre, p));
                Min = new Vec2(MathF.Min(Min.X, p.X), MathF.Min(Min.Y, p.Y));
                Max = new Vec2(MathF.Max(Max.X, p.X), MathF.Max(Max.Y, p.Y));
            }
            BoundRadius = r;
        }
    }
}
