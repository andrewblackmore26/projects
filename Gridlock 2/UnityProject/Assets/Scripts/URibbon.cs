using System.Collections.Generic;
using UnityEngine;

namespace Gridlock.View
{
    /// <summary>
    /// Polyline to ribbon mesh, with U running 0..1 along the path (so it IS the
    /// wire parameter t the simulation uses) and V running -1..1 across it.
    ///
    /// A generated mesh rather than a LineRenderer per wire, per spec section 11:
    /// LineRenderers do not batch, and the whole point of driving beams through
    /// shader uniforms is that a busy board stays a handful of draw calls.
    /// Joints are mitred; on a hex lattice the sharpest turn is 60 degrees, so
    /// mitre length is bounded and there are no spikes or gaps.
    /// </summary>
    public static class URibbon
    {
        public static Mesh Build(IList<Vector2> points, float halfWidth, bool closed)
        {
            if (points == null || points.Count < 2) return null;

            int n = points.Count;
            int ringCount = closed ? n + 1 : n;

            var verts = new Vector3[ringCount * 2];
            var uvs = new Vector2[ringCount * 2];

            var cumulative = new float[ringCount];
            float total = 0f;
            for (int i = 1; i < ringCount; i++)
            {
                total += Vector2.Distance(points[(i - 1) % n], points[i % n]);
                cumulative[i] = total;
            }
            if (total <= 0f) return null;

            for (int i = 0; i < ringCount; i++)
            {
                Vector2 p = points[i % n];
                Vector2 normal = NormalAt(points, n, i, ringCount, closed, out float scale);
                Vector2 offset = normal * (halfWidth * scale);
                verts[i * 2] = new Vector3(p.x + offset.x, p.y + offset.y, 0f);
                verts[i * 2 + 1] = new Vector3(p.x - offset.x, p.y - offset.y, 0f);
                float u = cumulative[i] / total;
                uvs[i * 2] = new Vector2(u, 1f);
                uvs[i * 2 + 1] = new Vector2(u, -1f);
            }

            var tris = new int[(ringCount - 1) * 6];
            int w = 0;
            for (int i = 0; i + 1 < ringCount; i++)
            {
                int a = i * 2, b = i * 2 + 1, c = (i + 1) * 2, d = (i + 1) * 2 + 1;
                tris[w++] = a; tris[w++] = b; tris[w++] = c;
                tris[w++] = c; tris[w++] = b; tris[w++] = d;
            }

            var mesh = new Mesh { name = "GridlockRibbon" };
            mesh.vertices = verts;
            mesh.uv = uvs;
            mesh.triangles = tris;
            mesh.RecalculateBounds();
            return mesh;
        }

        private static Vector2 NormalAt(IList<Vector2> points, int n, int i, int ringCount, bool closed, out float scale)
        {
            scale = 1f;
            bool hasPrev = closed || i > 0;
            bool hasNext = closed || i < ringCount - 1;

            Vector2 dPrev = hasPrev ? (points[i % n] - points[Mod(i - 1, n)]).normalized : Vector2.zero;
            Vector2 dNext = hasNext ? (points[(i + 1) % n] - points[i % n]).normalized : Vector2.zero;

            if (!hasPrev) return Perp(dNext);
            if (!hasNext) return Perp(dPrev);

            Vector2 nPrev = Perp(dPrev);
            Vector2 nNext = Perp(dNext);
            Vector2 mitre = nPrev + nNext;
            if (mitre.sqrMagnitude < 1e-8f) return nPrev;
            mitre = mitre.normalized;
            float denom = Vector2.Dot(mitre, nPrev);
            scale = 1f / Mathf.Max(Mathf.Abs(denom), 0.35f);
            return mitre;
        }

        private static Vector2 Perp(Vector2 d) => new Vector2(-d.y, d.x);

        private static int Mod(int a, int m) => ((a % m) + m) % m;
    }
}
