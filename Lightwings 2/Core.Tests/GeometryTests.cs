using System;
using System.Collections.Generic;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
using Xunit;

namespace Lightship.Core.Tests
{
    public class GeometryTests
    {
        // ---- helpers shared with the other geometry-level tests ----

        internal static PartDefinition Part(string id, Shape shape, ColorRole role, float x, float y, float rot,
            params (string key, float value)[] ps)
        {
            var p = new PartDefinition { Id = id, Shape = shape, Color = role, Pos = new Vec2(x, y), RotDeg = rot };
            foreach (var (key, value) in ps) p.Params[key] = value;
            return p;
        }

        internal static PartDefinition Part(string id, Shape shape, params (string key, float value)[] ps) =>
            Part(id, shape, ColorRole.FireRed, 0f, 0f, 0f, ps);

        internal static ShipDefinition Ship(params PartDefinition[] parts)
        {
            var s = new ShipDefinition { Id = "test", Name = "Test", Element = Element.Fire, Tier = 1, ChassisColor = ColorRole.FireRed };
            s.Parts.AddRange(parts);
            return s;
        }

        internal static ShipGeometry Geom(params PartDefinition[] parts) => ShipGeometry.Build(ResolvedShip.From(Ship(parts)));

        public static IEnumerable<object[]> SampleShapes()
        {
            yield return new object[] { Part("circle", Shape.Circle, ("radius", 13f)) };
            yield return new object[] { Part("ellipse", Shape.Ellipse, ("rx", 9f), ("ry", 7f)) };
            yield return new object[] { Part("triangle", Shape.Triangle, ("base", 14f), ("height", 22f)) };
            yield return new object[] { Part("prong", Shape.Prong, ("base", 3f), ("length", 14f)) };
            yield return new object[] { Part("diamond", Shape.Diamond, ("width", 12f), ("height", 20f)) };
            yield return new object[] { Part("chevron", Shape.Chevron, ("width", 12f), ("height", 10f), ("notch", 0.5f)) };
            yield return new object[] { Part("hexagon", Shape.Hexagon, ("radius", 13f)) };
            yield return new object[] { Part("crescent", Shape.Crescent, ("radius", 12f), ("cut_radius", 10f), ("cut_dx", 0f), ("cut_dy", -6f)) };
            yield return new object[] { Part("arc", Shape.Arc, ("radius", 20f), ("thickness", 3f), ("start_deg", -40f), ("sweep_deg", 80f)) };
            yield return new object[] { Part("ring", Shape.Ring, ("radius", 15f), ("thickness", 2f)) };
        }

        private static float FillArea(PartGeometry pg)
        {
            float sum = 0f;
            for (int i = 0; i + 2 < pg.FillIndices.Length; i += 3)
                sum += Triangulator.TriangleArea(pg.FillPoints[pg.FillIndices[i]], pg.FillPoints[pg.FillIndices[i + 1]], pg.FillPoints[pg.FillIndices[i + 2]]);
            return sum;
        }

        // ---- tests ----

        [Theory]
        [InlineData(3f)]
        [InlineData(13f)]
        [InlineData(40f)]
        public void CirclePerimeterMatchesAnalytic(float r)
        {
            Vec2[] pts = Outline.Circle(r);
            float perimeter = Outline.Length(pts, true);
            Assert.InRange(perimeter / (2f * MathF.PI * r), 0.99f, 1.0f);
            Assert.InRange(pts.Length, Outline.MinPoints, Outline.MaxPoints);
        }

        [Theory]
        [MemberData(nameof(SampleShapes))]
        public void EveryShapeTriangulatesToItsArea(PartDefinition p)
        {
            PartGeometry pg = Geom(p).Parts[0];
            Assert.True(pg.Area > 1f, p.Id + " has no area");
            Assert.True(pg.FillIndices.Length >= 3, p.Id + " has no fill triangles");
            float ratio = FillArea(pg) / pg.Area;
            Assert.True(ratio > 0.995f && ratio < 1.005f, p.Id + ": fill/area = " + ratio);
        }

        [Theory]
        [MemberData(nameof(SampleShapes))]
        public void OutlineIsSimple(PartDefinition p)
        {
            PartGeometry pg = Geom(p).Parts[0];
            Assert.True(Outline.IsSimple(pg.Outline), p.Id + " outline self-intersects");
            if (pg.InnerOutline != null) Assert.True(Outline.IsSimple(pg.InnerOutline));
        }

        [Fact]
        public void CrescentOpensForward()
        {
            PartGeometry pg = Geom(Part("c", Shape.Crescent, ("radius", 12f), ("cut_radius", 10f), ("cut_dx", 0f), ("cut_dy", -6f))).Parts[0];
            Vec2 centroid = Outline.Centroid(pg.Outline);
            Assert.True(centroid.Y > 0f, "mass should sit behind the cut, centroid.Y = " + centroid.Y);
            Assert.False(pg.ContainsPoint(new Vec2(0f, -8f)), "the maw is open");
            Assert.True(pg.ContainsPoint(new Vec2(0f, 9f)), "the back of the crescent is solid");
        }

        [Fact]
        public void CrescentRejectsNonIntersectingCircles()
        {
            Assert.Throws<ArgumentException>(() => Outline.Crescent(12f, 4f, 0f, -40f));
            Assert.Throws<ArgumentException>(() => Outline.Crescent(12f, 4f, 0f, -1f));
        }

        [Theory]
        [MemberData(nameof(SampleShapes))]
        public void BoundingCircleContainsOutline(PartDefinition p)
        {
            PartGeometry pg = Geom(p).Parts[0];
            foreach (Vec2 v in pg.Outline)
                Assert.True(Vec2.Distance(pg.Centre, v) <= pg.BoundRadius + 1e-4f, p.Id);
        }

        [Theory]
        [MemberData(nameof(SampleShapes))]
        public void UIsMonotoneAndStaysBelowOne(PartDefinition p)
        {
            PartGeometry pg = Geom(p).Parts[0];
            Assert.Equal(0f, pg.U[0]);
            for (int i = 1; i < pg.U.Length; i++) Assert.True(pg.U[i] > pg.U[i - 1], p.Id + " u not increasing at " + i);
            Assert.True(pg.U[pg.U.Length - 1] < 1f);
            Assert.True(pg.Perimeter > 0f);
        }

        [Fact]
        public void DrawOrderIsRingTetherOuterBodyComponent()
        {
            var ember = Part("ember", Shape.Circle, ColorRole.LightningYellow, 0f, -13f, 0f, ("radius", 3f));
            ember.Component = "flame_spray";
            var body = Part("body", Shape.Triangle, ("base", 14f), ("height", 22f));
            var wing = Part("wing", Shape.Triangle, ColorRole.FireRed, 12f, 6f, 0f, ("base", 10f), ("height", 14f));
            wing.Layer = PartLayer.Outer;
            var reach = Part("reach", Shape.Circle, ("radius", 30f));
            reach.Dashed = true;
            var tether = new PartDefinition { Id = "tether_wing", Shape = Shape.Tether, From = "body", To = "wing", Color = ColorRole.FireRed };

            ShipGeometry g = Geom(ember, body, wing, reach, tether);
            Assert.Equal(new[] { "reach", "tether_wing", "wing", "body", "ember" }, g.Parts.ConvertAll(x => x.Id).ToArray());
        }

        [Fact]
        public void RotationAndPositionApply()
        {
            PartGeometry pg = Geom(Part("t", Shape.Triangle, ColorRole.FireRed, 10f, 0f, 90f, ("base", 10f), ("height", 20f))).Parts[0];
            Vec2 apex = pg.Outline[0];
            Assert.InRange(apex.X, 19.99f, 20.01f);
            Assert.InRange(apex.Y, -0.01f, 0.01f);
            Assert.Equal(new Vec2(10f, 0f), pg.Centre);
        }

        [Fact]
        public void ContainsPointRespectsHoles()
        {
            PartGeometry ring = Geom(Part("r", Shape.Ring, ("radius", 15f), ("thickness", 2f))).Parts[0];
            Assert.True(ring.ContainsPoint(new Vec2(15f, 0f)));
            Assert.False(ring.ContainsPoint(new Vec2(0f, 0f)));
            Assert.False(ring.ContainsPoint(new Vec2(30f, 0f)));
            PartGeometry hex = Geom(Part("h", Shape.Hexagon, ("radius", 13f))).Parts[0];
            Assert.True(hex.ContainsPoint(Vec2.Zero));
            Assert.False(hex.ContainsPoint(new Vec2(14f, 0f)));
        }

        [Fact]
        public void TetherFollowsPartCentres()
        {
            var a = Part("a", Shape.Circle, ColorRole.CorruptionGreen, 0f, 0f, 0f, ("radius", 5f));
            var b = Part("b", Shape.Circle, ColorRole.CorruptionGreen, 30f, 0f, 0f, ("radius", 5f));
            var t = new PartDefinition { Id = "tether_b", Shape = Shape.Tether, From = "a", To = "b", Color = ColorRole.CorruptionGreen };
            ShipGeometry g = Geom(a, b, t);
            PartGeometry tg = g.Find("tether_b");
            Assert.True(tg.IsTether);
            Assert.Equal(new Vec2(0f, 0f), tg.Outline[0]);
            Assert.Equal(new Vec2(30f, 0f), tg.Outline[1]);
            Assert.Equal(30f, tg.Perimeter, 3);
            Assert.Equal(new[] { 0f, 1f }, tg.U);
        }

        [Fact]
        public void DegeneratePartsAndDanglingTethersAreSkipped()
        {
            var zero = Part("zero", Shape.Circle, ("radius", 0f));
            var t = new PartDefinition { Id = "tether_x", Shape = Shape.Tether, From = "zero", To = "missing", Color = ColorRole.FireRed };
            ShipGeometry g = Geom(zero, t);
            Assert.Empty(g.Parts);
        }

        [Fact]
        public void PointAtUWalksClockwiseFromTheFront()
        {
            PartGeometry pg = Geom(Part("c", Shape.Circle, ("radius", 10f))).Parts[0];
            Vec2 front = pg.PointAtU(0f), right = pg.PointAtU(0.25f), back = pg.PointAtU(0.5f);
            Assert.InRange(front.Y, -10.01f, -9.9f);
            Assert.InRange(right.X, 9.85f, 10.01f);
            Assert.InRange(back.Y, 9.85f, 10.01f);
        }

        [Fact]
        public void FootprintCoversPartsAndCore()
        {
            ShipGeometry g = Geom(Part("c", Shape.Circle, ("radius", 13f)));
            Assert.InRange(g.Footprint, 25.8f, 26.05f);
            Assert.InRange(g.BoundRadius, 12.9f, 13.05f);
            ShipGeometry empty = ShipGeometry.Build(ResolvedShip.From(Ship()));
            Assert.Equal(6f, empty.Footprint, 3);   // just the 3 px core
        }
    }
}
