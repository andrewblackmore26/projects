using System;
using System.Collections.Generic;
using Lightship.Core.Ships;

namespace Lightship.Core.Geometry
{
    /// <summary>
    /// Turns ship geometry into one mesh in painter's order: for each part its
    /// dark fill then its stroke ribbon, and the core last. Per-vertex data is
    /// packed into the attributes every canvas mesh carries:
    ///   UV.x  perimeter fraction (or screen-px arc length for dashed rings), 0 for fills
    ///   UV.y  across the ribbon, -1..1, 0 for fills
    ///   COLOR r = role index, g = flags (kind | period shifted 3 | phase shifted 4), b/a = perimeter px hi/lo
    /// Stroke widths are constant in SCREEN space (spec 11.13): the ribbons are
    /// extruded at px / zoom, so the mesh is rebuilt when the zoom steps.
    /// </summary>
    public static class ShipMeshBuilder
    {
        public const float StrokeHalfPx = 1.3f;    // 2.6 px ribbon; the 1.5 px base stroke is its centre
        public const float TetherHalfPx = 1.3f;    // 2.6 px ribbon; the 2.0 px tether is its centre
        public const float DashedHalfPx = 0.5f;    // 1 px reference ring
        public const int CoreSegments = 20;

        public const int KindFill = 0;
        public const int KindStroke = 1;
        public const int KindDashed = 2;
        public const int KindTether = 3;
        public const int KindCore = 4;
        public const int KindStrokeNoLight = 5;

        public static byte PackFlags(int kind, int periodIndex, int phaseIndex) =>
            (byte)((kind & 7) | ((periodIndex & 1) << 3) | ((phaseIndex & 3) << 4));

        public static void UnpackFlags(byte flags, out int kind, out int periodIndex, out int phaseIndex)
        {
            kind = flags & 7;
            periodIndex = (flags >> 3) & 1;
            phaseIndex = (flags >> 4) & 3;
        }

        public static int PerimeterPx(float perimeter, float zoom) =>
            Math.Clamp((int)MathF.Round(perimeter * zoom), 0, 65535);

        // Scratch buffers for the ribbon so a per-frame rebuild does not allocate.
        private static readonly List<Vec2> ScratchVerts = new List<Vec2>();
        private static readonly List<float> ScratchU = new List<float>();
        private static readonly List<float> ScratchSide = new List<float>();
        private static readonly List<int> ScratchTris = new List<int>();

        public static void Build(ShipGeometry g, float zoom, MeshData m)
        {
            m.Clear();
            float strokeHw = StrokeHalfPx / zoom;
            float tetherHw = TetherHalfPx / zoom;
            float dashedHw = DashedHalfPx / zoom;

            foreach (PartGeometry p in g.Parts)
            {
                int first = m.IndexCount;
                byte role = (byte)p.Role;
                if (p.IsTether)
                {
                    AddRibbon(m, p.Outline, false, tetherHw, role,
                        PackFlags(KindTether, p.PeriodIndex, p.PhaseIndex), PerimeterPx(p.Perimeter, zoom), 1f);
                }
                else if (p.Dashed)
                {
                    int px = PerimeterPx(p.Perimeter, zoom);
                    AddRibbon(m, p.Outline, true, dashedHw, role, PackFlags(KindDashed, 0, 0), px, px);
                    if (p.InnerOutline != null)
                    {
                        int ipx = PerimeterPx(p.InnerPerimeter, zoom);
                        AddRibbon(m, p.InnerOutline, true, dashedHw, role, PackFlags(KindDashed, 0, 0), ipx, ipx);
                    }
                }
                else
                {
                    if (p.FillIndices.Length > 0)
                    {
                        int b = m.VertexCount;
                        byte flags = PackFlags(KindFill, 0, 0);
                        foreach (Vec2 v in p.FillPoints) m.AddVertex(v.X, v.Y, 0f, 0f, role, flags, 0, 0);
                        for (int i = 0; i + 2 < p.FillIndices.Length; i += 3)
                            m.AddTriangle(b + p.FillIndices[i], b + p.FillIndices[i + 1], b + p.FillIndices[i + 2]);
                    }
                    AddRibbon(m, p.Outline, true, strokeHw, role,
                        PackFlags(KindStroke, p.PeriodIndex, p.PhaseIndex), PerimeterPx(p.Perimeter, zoom), 1f);
                    if (p.InnerOutline != null)
                        AddRibbon(m, p.InnerOutline, true, strokeHw, role,
                            PackFlags(KindStrokeNoLight, 0, 0), PerimeterPx(p.InnerPerimeter, zoom), 1f);
                }
                m.Spans.Add(new MeshSpan(p.Id, first, m.IndexCount - first));
            }

            // The core: a filled disc, drawn last, radius constant in screen space.
            {
                int first = m.IndexCount;
                float r = g.CoreRadius / zoom;
                byte role = (byte)g.CoreRole;
                byte flags = PackFlags(KindCore, 0, 0);
                int centre = m.AddVertex(0f, 0f, 0f, 0f, role, flags, 0, 0);
                int ring0 = m.VertexCount;
                for (int k = 0; k < CoreSegments; k++)
                {
                    float a = 2f * MathF.PI * k / CoreSegments;
                    m.AddVertex(r * MathF.Cos(a), r * MathF.Sin(a), 0f, 0f, role, flags, 0, 0);
                }
                for (int k = 0; k < CoreSegments; k++)
                    m.AddTriangle(centre, ring0 + k, ring0 + (k + 1) % CoreSegments);
                m.Spans.Add(new MeshSpan("core", first, m.IndexCount - first));
            }
        }

        private static void AddRibbon(MeshData m, Vec2[] points, bool closed, float halfWidth,
            byte role, byte flags, int perimeterPx, float uScale)
        {
            ScratchVerts.Clear(); ScratchU.Clear(); ScratchSide.Clear(); ScratchTris.Clear();
            Ribbon.Extrude(points, closed, halfWidth, ScratchVerts, ScratchU, ScratchSide, ScratchTris);
            int b = m.VertexCount;
            byte hi = (byte)(perimeterPx >> 8), lo = (byte)(perimeterPx & 255);
            for (int i = 0; i < ScratchVerts.Count; i++)
            {
                Vec2 v = ScratchVerts[i];
                m.AddVertex(v.X, v.Y, ScratchU[i] * uScale, ScratchSide[i], role, flags, hi, lo);
            }
            for (int i = 0; i + 2 < ScratchTris.Count; i += 3)
                m.AddTriangle(b + ScratchTris[i], b + ScratchTris[i + 1], b + ScratchTris[i + 2]);
        }
    }
}
