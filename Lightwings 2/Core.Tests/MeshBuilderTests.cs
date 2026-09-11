using System;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
using Xunit;

namespace Lightship.Core.Tests
{
    public class MeshBuilderTests
    {
        private static MeshData Build(ShipDefinition ship, float zoom)
        {
            var m = new MeshData();
            ShipMeshBuilder.Build(ShipGeometry.Build(ResolvedShip.From(ship)), zoom, m);
            return m;
        }

        private static MeshSpan SpanOf(MeshData m, string id)
        {
            foreach (MeshSpan s in m.Spans) if (s.PartId == id) return s;
            throw new Exception("no span for " + id);
        }

        /// <summary>The first ribbon ring pair (vertices a, b of the first quad) of the given kind within a span.</summary>
        private static (int a, int b) FirstRingPair(MeshData m, MeshSpan span, int kind)
        {
            for (int i = span.FirstIndex; i < span.FirstIndex + span.IndexCount; i += 3)
            {
                int v = m.Indices[i];
                ShipMeshBuilder.UnpackFlags(m.Flags(v), out int k, out _, out _);
                if (k == kind) return (m.Indices[i], m.Indices[i + 1]);
            }
            throw new Exception("no vertices of kind " + kind + " in " + span.PartId);
        }

        [Fact]
        public void PackingRoundTrip()
        {
            for (int kind = 0; kind <= 5; kind++)
                for (int period = 0; period <= 1; period++)
                    for (int phase = 0; phase <= 2; phase++)
                    {
                        byte f = ShipMeshBuilder.PackFlags(kind, period, phase);
                        ShipMeshBuilder.UnpackFlags(f, out int k, out int pe, out int ph);
                        Assert.Equal((kind, period, phase), (k, pe, ph));
                    }
            for (int p = 1; p <= 3000; p++)
            {
                int px = ShipMeshBuilder.PerimeterPx(p, 1f);
                byte hi = (byte)(px >> 8), lo = (byte)(px & 255);
                Assert.Equal(px, hi * 256 + lo);
            }
            Assert.Equal(65535, ShipMeshBuilder.PerimeterPx(100000f, 1f));
            Assert.Equal(73, ShipMeshBuilder.PerimeterPx(100f, 0.729f));
        }

        [Theory]
        [InlineData(1f)]
        [InlineData(0.729f)]
        public void StrokeWidthScalesWithZoom(float zoom)
        {
            var a = GeometryTests.Part("a", Shape.Circle, ColorRole.CorruptionGreen, 0f, 0f, 0f, ("radius", 5f));
            var b = GeometryTests.Part("b", Shape.Circle, ColorRole.CorruptionGreen, 40f, 0f, 0f, ("radius", 5f));
            var t = new PartDefinition { Id = "tether_b", Shape = Shape.Tether, From = "a", To = "b", Color = ColorRole.CorruptionGreen };
            var hex = GeometryTests.Part("hex", Shape.Hexagon, ColorRole.CorruptionGreen, 0f, 60f, 0f, ("radius", 13f));
            MeshData m = Build(GeometryTests.Ship(a, b, t, hex), zoom);

            // A straight tether has no mitre: the ribbon is exactly 2 x 1.3 px / zoom wide.
            var (ta, tb) = FirstRingPair(m, SpanOf(m, "tether_b"), ShipMeshBuilder.KindTether);
            float tetherWidth = Vec2.Distance(m.Position(ta), m.Position(tb));
            Assert.InRange(tetherWidth, 2f * 1.3f / zoom - 1e-3f, 2f * 1.3f / zoom + 1e-3f);

            // A hexagon corner turns 60 degrees: the mitre is 1 / cos(30) longer than the flat width.
            var (ha, hb) = FirstRingPair(m, SpanOf(m, "hex"), ShipMeshBuilder.KindStroke);
            float hexWidth = Vec2.Distance(m.Position(ha), m.Position(hb));
            float expected = 2f * 1.3f / zoom / MathF.Cos(MathF.PI / 6f);
            Assert.InRange(hexWidth / expected, 0.99f, 1.01f);
        }

        [Fact]
        public void EveryPartEmitsASpanAndDashedPartsHaveNoFill()
        {
            var body = GeometryTests.Part("body", Shape.Ellipse, ColorRole.CorruptionGreen, 0f, 0f, 0f, ("rx", 9f), ("ry", 7f));
            var reach = GeometryTests.Part("reach", Shape.Circle, ColorRole.VoidSilver, 0f, 0f, 0f, ("radius", 30f));
            reach.Dashed = true;
            var spore = GeometryTests.Part("spore", Shape.Circle, ColorRole.LightningYellow, 0f, -10f, 0f, ("radius", 2.6f));
            spore.Component = "infect";
            MeshData m = Build(GeometryTests.Ship(body, reach, spore), 1f);

            foreach (string id in new[] { "reach", "body", "spore", "core" })
                Assert.True(SpanOf(m, id).IndexCount > 0, id);

            MeshSpan r = SpanOf(m, "reach");
            for (int i = r.FirstIndex; i < r.FirstIndex + r.IndexCount; i++)
            {
                ShipMeshBuilder.UnpackFlags(m.Flags(m.Indices[i]), out int kind, out _, out _);
                Assert.Equal(ShipMeshBuilder.KindDashed, kind);
            }
            // Dashed ring UV.x is arc length in screen px, so the dash pattern is constant on screen.
            var (ra, _) = FirstRingPair(m, r, ShipMeshBuilder.KindDashed);
            int perimPx = m.PerimeterPx(ra);
            Assert.InRange(perimPx, 187, 189);   // 2 * pi * 30 = 188.5

            MeshSpan b = SpanOf(m, "body");
            bool sawFill = false, sawStroke = false;
            for (int i = b.FirstIndex; i < b.FirstIndex + b.IndexCount; i++)
            {
                ShipMeshBuilder.UnpackFlags(m.Flags(m.Indices[i]), out int kind, out _, out _);
                if (kind == ShipMeshBuilder.KindFill) sawFill = true;
                if (kind == ShipMeshBuilder.KindStroke) sawStroke = true;
            }
            Assert.True(sawFill && sawStroke);
        }

        [Fact]
        public void CoreIsDrawnLastAtScreenRadius()
        {
            var body = GeometryTests.Part("body", Shape.Circle, ColorRole.FireRed, 0f, 0f, 0f, ("radius", 10f));
            ShipDefinition ship = GeometryTests.Ship(body);
            ship.CoreRadius = 3f;
            ship.CoreColor = ColorRole.White;
            MeshData m = Build(ship, 0.5f);
            MeshSpan last = m.Spans[m.Spans.Count - 1];
            Assert.Equal("core", last.PartId);
            for (int i = last.FirstIndex; i < last.FirstIndex + last.IndexCount; i++)
            {
                int v = m.Indices[i];
                ShipMeshBuilder.UnpackFlags(m.Flags(v), out int kind, out _, out _);
                Assert.Equal(ShipMeshBuilder.KindCore, kind);
                Assert.Equal((byte)ColorRole.White, m.Role(v));
                float r = m.Position(v).Length();
                Assert.True(r < 1e-4f || MathF.Abs(r - 6f) < 1e-3f, "core vertex radius " + r);
            }
        }

        [Fact]
        public void StrokeVerticesCarryScheduleAndFillsDoNot()
        {
            var body = GeometryTests.Part("body", Shape.Circle, ColorRole.FireRed, 0f, 0f, 0f, ("radius", 10f));
            body.PeriodIndex = 1;
            body.PhaseIndex = 2;
            MeshData m = Build(GeometryTests.Ship(body), 1f);
            MeshSpan s = SpanOf(m, "body");
            float lastU = -1f;
            int strokes = 0;
            for (int i = s.FirstIndex; i < s.FirstIndex + s.IndexCount; i++)
            {
                int v = m.Indices[i];
                ShipMeshBuilder.UnpackFlags(m.Flags(v), out int kind, out int period, out int phase);
                float u = m.Uv[v * 2], side = m.Uv[v * 2 + 1];
                if (kind == ShipMeshBuilder.KindFill)
                {
                    Assert.Equal(0, period); Assert.Equal(0, phase); Assert.Equal(0f, u); Assert.Equal(0f, side);
                }
                else
                {
                    Assert.Equal(ShipMeshBuilder.KindStroke, kind);
                    Assert.Equal(1, period); Assert.Equal(2, phase);
                    Assert.InRange(u, 0f, 1f);
                    Assert.True(side == 1f || side == -1f);
                    lastU = MathF.Max(lastU, u);
                    strokes++;
                }
            }
            Assert.True(strokes > 0);
            Assert.InRange(lastU, 0.999f, 1f);
            // Ribbon vertices are emitted in perimeter order: u never decreases from one ring pair to the next.
            float prev = -1f;
            for (int v = 0; v < m.VertexCount; v++)
            {
                ShipMeshBuilder.UnpackFlags(m.Flags(v), out int kind, out _, out _);
                if (kind != ShipMeshBuilder.KindStroke) continue;
                float u = m.Uv[v * 2];
                Assert.True(u >= prev - 1e-6f, "u decreased at vertex " + v);
                prev = u;
            }
        }
    }
}
