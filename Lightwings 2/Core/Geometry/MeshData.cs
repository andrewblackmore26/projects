using System.Collections.Generic;

namespace Lightship.Core.Geometry
{
    /// <summary>Index range of one part inside a MeshData, for editor selection and tests.</summary>
    public struct MeshSpan
    {
        public string PartId;
        public int FirstIndex;
        public int IndexCount;

        public MeshSpan(string partId, int firstIndex, int indexCount)
        {
            PartId = partId; FirstIndex = firstIndex; IndexCount = indexCount;
        }
    }

    /// <summary>
    /// Engine-free vertex buffers: position, UV, an RGBA8 data channel and
    /// indices. Godot converts these to its arrays; nothing here knows how it
    /// will be drawn. Lists so a per-frame rebuild reuses capacity.
    /// </summary>
    public sealed class MeshData
    {
        public readonly List<float> Xy = new List<float>();
        public readonly List<float> Uv = new List<float>();
        public readonly List<byte> Rgba = new List<byte>();
        public readonly List<int> Indices = new List<int>();
        public readonly List<MeshSpan> Spans = new List<MeshSpan>();

        public int VertexCount => Xy.Count / 2;
        public int IndexCount => Indices.Count;

        public void Clear()
        {
            Xy.Clear(); Uv.Clear(); Rgba.Clear(); Indices.Clear(); Spans.Clear();
        }

        public int AddVertex(float x, float y, float u, float v, byte r, byte g, byte b, byte a)
        {
            int i = VertexCount;
            Xy.Add(x); Xy.Add(y);
            Uv.Add(u); Uv.Add(v);
            Rgba.Add(r); Rgba.Add(g); Rgba.Add(b); Rgba.Add(a);
            return i;
        }

        public void AddTriangle(int a, int b, int c)
        {
            Indices.Add(a); Indices.Add(b); Indices.Add(c);
        }

        public Vec2 Position(int vertex) => new Vec2(Xy[vertex * 2], Xy[vertex * 2 + 1]);
        public byte Role(int vertex) => Rgba[vertex * 4];
        public byte Flags(int vertex) => Rgba[vertex * 4 + 1];
        public int PerimeterPx(int vertex) => Rgba[vertex * 4 + 2] * 256 + Rgba[vertex * 4 + 3];
    }
}
