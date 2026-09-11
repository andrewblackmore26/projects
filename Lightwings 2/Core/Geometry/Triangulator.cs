using System;
using System.Collections.Generic;

namespace Lightship.Core.Geometry
{
    /// <summary>
    /// Ear clipping for a simple polygon of any orientation. O(n^2), n is at
    /// most 128 here, and it runs at load (and per frame for the one ship
    /// being reshaped), so clarity wins over cleverness. Lives in Core so
    /// tests can check that the fill of every primitive equals its area.
    /// </summary>
    public static class Triangulator
    {
        public static int[] EarClip(Vec2[] p)
        {
            int n = p.Length;
            if (n < 3) return Array.Empty<int>();
            var idx = new List<int>(n);
            for (int i = 0; i < n; i++) idx.Add(i);
            if (Outline.SignedArea(p) < 0f) idx.Reverse();

            var tris = new List<int>(3 * (n - 2));
            int guard = 0;
            while (idx.Count > 3)
            {
                if (++guard > n * n + 16) break;
                int m = idx.Count;
                bool clipped = false;
                for (int i = 0; i < m; i++)
                {
                    int i0 = idx[(i + m - 1) % m], i1 = idx[i], i2 = idx[(i + 1) % m];
                    Vec2 a = p[i0], b = p[i1], c = p[i2];
                    if (Vec2.Cross(b - a, c - b) <= 1e-9f) continue;   // reflex or collinear: not an ear
                    bool blocked = false;
                    for (int j = 0; j < m && !blocked; j++)
                    {
                        int k = idx[j];
                        if (k == i0 || k == i1 || k == i2) continue;
                        if (StrictlyInside(p[k], a, b, c)) blocked = true;
                    }
                    if (blocked) continue;
                    tris.Add(i0); tris.Add(i1); tris.Add(i2);
                    idx.RemoveAt(i);
                    clipped = true;
                    break;
                }
                if (!clipped)
                {
                    // Only collinear or numerically flat vertices remain: drop the flattest and carry on.
                    int flattest = 0;
                    float best = float.MaxValue;
                    for (int i = 0; i < m; i++)
                    {
                        Vec2 a = p[idx[(i + m - 1) % m]], b = p[idx[i]], c = p[idx[(i + 1) % m]];
                        float cr = MathF.Abs(Vec2.Cross(b - a, c - b));
                        if (cr < best) { best = cr; flattest = i; }
                    }
                    idx.RemoveAt(flattest);
                }
            }
            if (idx.Count == 3) { tris.Add(idx[0]); tris.Add(idx[1]); tris.Add(idx[2]); }
            return tris.ToArray();
        }

        private static bool StrictlyInside(Vec2 q, Vec2 a, Vec2 b, Vec2 c)
        {
            const float eps = 1e-7f;
            return Vec2.Cross(b - a, q - a) > eps &&
                   Vec2.Cross(c - b, q - b) > eps &&
                   Vec2.Cross(a - c, q - c) > eps;
        }

        public static float TriangleArea(Vec2 a, Vec2 b, Vec2 c) => MathF.Abs(Vec2.Cross(b - a, c - a)) * 0.5f;
    }
}
