using System.Collections.Generic;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
using Xunit;

namespace Lightship.Core.Tests
{
    public class TweenTests
    {
        private static ShipDefinition From()
        {
            var body = GeometryTests.Part("body", Shape.Circle, ColorRole.CorruptionGreen, 0f, 0f, 0f, ("radius", 10f));
            var tail = GeometryTests.Part("tail_1", Shape.Circle, ColorRole.CorruptionGreen, 0f, 12f, 350f, ("radius", 3f));
            var gone = GeometryTests.Part("gone", Shape.Circle, ColorRole.CorruptionGreen, 20f, 0f, 0f, ("radius", 5f));
            return GeometryTests.Ship(body, tail, gone);
        }

        private static ShipDefinition To()
        {
            var body = GeometryTests.Part("body", Shape.Circle, ColorRole.PlayerBlue, 0f, -4f, 0f, ("radius", 12f));
            var tail = GeometryTests.Part("tail_1", Shape.Circle, ColorRole.CorruptionGreen, 0f, 16f, 10f, ("radius", 5f));
            var pod = GeometryTests.Part("pod_r", Shape.Circle, ColorRole.CorruptionGreen, 24f, 0f, 0f, ("radius", 6f));
            var tether = new PartDefinition { Id = "tether_pod_r", Shape = Shape.Tether, From = "body", To = "pod_r", Color = ColorRole.CorruptionGreen };
            ShipDefinition s = GeometryTests.Ship(body, tail, pod, tether);
            s.CoreRadius = 5f;
            return s;
        }

        private static HashSet<string> Ids(ResolvedShip r)
        {
            var ids = new HashSet<string>();
            foreach (PartDefinition p in r.Parts) ids.Add(p.Id);
            return ids;
        }

        [Fact]
        public void BlendEndpointsAreExact()
        {
            ResolvedShip start = ShipTween.Blend(From(), To(), 0f);
            Assert.Equal(new HashSet<string> { "body", "tail_1", "gone" }, Ids(start));
            Assert.Equal(new Vec2(0f, 12f), start.FindPart("tail_1").Pos);
            Assert.Equal(3f, start.FindPart("tail_1").Param("radius"));
            Assert.Equal(350f, start.FindPart("tail_1").RotDeg);
            Assert.Equal(ColorRole.CorruptionGreen, start.FindPart("body").Color);
            Assert.Equal(3f, start.CoreRadius);

            ResolvedShip end = ShipTween.Blend(From(), To(), 1f);
            Assert.Equal(new HashSet<string> { "body", "tail_1", "pod_r", "tether_pod_r" }, Ids(end));
            Assert.Equal(new Vec2(24f, 0f), end.FindPart("pod_r").Pos);
            Assert.Equal(6f, end.FindPart("pod_r").Param("radius"));
            Assert.Equal(10f, end.FindPart("tail_1").RotDeg, 3);
            Assert.Equal(ColorRole.PlayerBlue, end.FindPart("body").Color);
            Assert.Equal(5f, end.CoreRadius);
        }

        [Fact]
        public void MatchedPartsLerpAlongTheShortestArc()
        {
            ResolvedShip mid = ShipTween.Blend(From(), To(), 0.5f);   // smoothstep(0.5) = 0.5
            PartDefinition body = mid.FindPart("body");
            Assert.Equal(new Vec2(0f, -2f), body.Pos);
            Assert.Equal(11f, body.Param("radius"), 3);
            PartDefinition tail = mid.FindPart("tail_1");
            Assert.Equal(new Vec2(0f, 14f), tail.Pos);
            Assert.Equal(0f, ((tail.RotDeg % 360f) + 360f) % 360f, 2);   // 350 -> 10 passes through 0, not 180
            Assert.Equal(4f, mid.CoreRadius, 3);
        }

        [Fact]
        public void NewPartGrowsFromCoreAndRemovedPartShrinksIntoIt()
        {
            ResolvedShip mid = ShipTween.Blend(From(), To(), 0.5f);
            PartDefinition pod = mid.FindPart("pod_r");
            Assert.Equal(new Vec2(12f, 0f), pod.Pos);
            Assert.Equal(3f, pod.Param("radius"), 3);
            PartDefinition gone = mid.FindPart("gone");
            Assert.Equal(new Vec2(10f, 0f), gone.Pos);
            Assert.Equal(2.5f, gone.Param("radius"), 3);

            ResolvedShip early = ShipTween.Blend(From(), To(), 0.1f);   // smoothstep(0.1) = 0.028
            Assert.True(early.FindPart("pod_r").Param("radius") < 0.2f);
            Assert.True(early.FindPart("gone").Param("radius") > 4.8f);
        }

        [Fact]
        public void DiscreteFieldsSnapAtHalfway()
        {
            Assert.Equal(ColorRole.CorruptionGreen, ShipTween.Blend(From(), To(), 0.45f).FindPart("body").Color);
            Assert.Equal(ColorRole.PlayerBlue, ShipTween.Blend(From(), To(), 0.55f).FindPart("body").Color);
            Assert.Equal(From().ChassisColor, ShipTween.Blend(From(), To(), 0.45f).ChassisColor);
        }

        [Fact]
        public void TetherFollowsBlendedEndpoints()
        {
            ResolvedShip mid = ShipTween.Blend(From(), To(), 0.5f);
            ShipGeometry g = ShipGeometry.Build(mid);
            PartGeometry t = g.Find("tether_pod_r");
            Assert.NotNull(t);
            Assert.Equal(mid.FindPart("body").Pos, t.Outline[0]);
            Assert.Equal(mid.FindPart("pod_r").Pos, t.Outline[1]);
        }

        [Fact]
        public void SameIdDifferentShapeCrossFades()
        {
            var a = GeometryTests.Ship(GeometryTests.Part("body", Shape.Circle, ColorRole.FireRed, 0f, 0f, 0f, ("radius", 10f)));
            var b = GeometryTests.Ship(GeometryTests.Part("body", Shape.Hexagon, ColorRole.FireRed, 0f, 0f, 0f, ("radius", 13f)));
            ResolvedShip mid = ShipTween.Blend(a, b, 0.5f);
            Assert.Equal(new HashSet<string> { "body", "body~old" }, Ids(mid));
            Assert.Equal(Shape.Hexagon, mid.FindPart("body").Shape);
            Assert.Equal(Shape.Circle, mid.FindPart("body~old").Shape);
            Assert.Equal(new HashSet<string> { "body" }, Ids(ShipTween.Blend(a, b, 1f)));
        }

        [Fact]
        public void BlendedShipsAlwaysBuildGeometry()
        {
            for (float t = 0f; t <= 1f; t += 0.05f)
            {
                ShipGeometry g = ShipGeometry.Build(ShipTween.Blend(From(), To(), t));
                Assert.True(g.Footprint >= 6f);
            }
            // The M1 progression must also tween cleanly.
            ShipCatalog c = LoaderTests.Authored(out _);
            ShipDefinition t1 = c.Find(Element.Corruption, 1), t2 = c.Find(Element.Corruption, 2), t3 = c.Find(Element.Corruption, 3);
            for (float t = 0f; t <= 1f; t += 0.1f)
            {
                Assert.True(ShipGeometry.Build(ShipTween.Blend(t1.AsPlayerVariant(), t2.AsPlayerVariant(), t)).Parts.Count > 0);
                Assert.True(ShipGeometry.Build(ShipTween.Blend(t2.AsPlayerVariant(), t3.AsPlayerVariant(), t)).Parts.Count > 0);
            }
        }
    }
}
