using System;
using Godot;

namespace Gridlock.View
{
    /// <summary>
    /// Turns a polyline into a ribbon mesh with exact UVs: U runs 0..1 along the
    /// polyline (so it IS the wire parameter t the simulation uses) and V runs
    /// -1..1 across it. Everything animated lives in the shader, so these meshes
    /// are built once at load and never rebuilt.
    ///
    /// Joints are mitred. On a hex lattice the sharpest turn is 60 degrees, so
    /// the mitre length is bounded at 2x the half-width -- no spikes, no gaps.
    /// </summary>
    public static class Ribbon
    {
        public static ArrayMesh Build(Vector2[] points, float halfWidth, bool closed)
        {
            if (points == null || points.Length < 2) return null;

            int n = points.Length;
            int ringCount = closed ? n + 1 : n;

            var verts = new Vector2[ringCount * 2];
            var uvs = new Vector2[ringCount * 2];

            // Cumulative arc length gives U, so a beam at t maps to the same
            // place the simulation puts it.
            var cumulative = new float[ringCount];
            float total = 0f;
            for (int i = 1; i < ringCount; i++)
            {
                Vector2 prev = points[(i - 1) % n];
                Vector2 cur = points[i % n];
                total += prev.DistanceTo(cur);
                cumulative[i] = total;
            }
            if (total <= 0f) return null;

            for (int i = 0; i < ringCount; i++)
            {
                Vector2 p = points[i % n];
                Vector2 normal = NormalAt(points, n, i, ringCount, closed, out float scale);
                Vector2 offset = normal * halfWidth * scale;
                verts[i * 2] = p + offset;
                verts[i * 2 + 1] = p - offset;
                float u = cumulative[i] / total;
                uvs[i * 2] = new Vector2(u, 1f);
                uvs[i * 2 + 1] = new Vector2(u, -1f);
            }

            var indices = new int[(ringCount - 1) * 6];
            int w = 0;
            for (int i = 0; i + 1 < ringCount; i++)
            {
                int a = i * 2, b = i * 2 + 1, c = (i + 1) * 2, d = (i + 1) * 2 + 1;
                indices[w++] = a; indices[w++] = b; indices[w++] = c;
                indices[w++] = c; indices[w++] = b; indices[w++] = d;
            }

            var arrays = new Godot.Collections.Array();
            arrays.Resize((int)Mesh.ArrayType.Max);
            arrays[(int)Mesh.ArrayType.Vertex] = verts;
            arrays[(int)Mesh.ArrayType.TexUV] = uvs;
            arrays[(int)Mesh.ArrayType.Index] = indices;

            var mesh = new ArrayMesh();
            mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays);
            return mesh;
        }

        private static Vector2 NormalAt(Vector2[] points, int n, int i, int ringCount, bool closed, out float scale)
        {
            scale = 1f;
            bool hasPrev = closed || i > 0;
            bool hasNext = closed || i < ringCount - 1;

            Vector2 dPrev = hasPrev ? (points[i % n] - points[Mod(i - 1, n)]).Normalized() : Vector2.Zero;
            Vector2 dNext = hasNext ? (points[(i + 1) % n] - points[i % n]).Normalized() : Vector2.Zero;

            if (!hasPrev) return Perp(dNext);
            if (!hasNext) return Perp(dPrev);

            Vector2 nPrev = Perp(dPrev);
            Vector2 nNext = Perp(dNext);
            Vector2 mitre = (nPrev + nNext);
            if (mitre.LengthSquared() < 1e-8f) return nPrev; // doubled back
            mitre = mitre.Normalized();
            float denom = mitre.Dot(nPrev);
            scale = 1f / Mathf.Max(Mathf.Abs(denom), 0.35f);
            return mitre;
        }

        private static Vector2 Perp(Vector2 d) => new Vector2(-d.Y, d.X);

        private static int Mod(int a, int m) => ((a % m) + m) % m;
    }
}
