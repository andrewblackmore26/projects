using System;
using System.Collections.Generic;
using Lightship.Core.Geometry;
using Lightship.Core.Ships;
using Xunit;

namespace Lightship.Core.Tests
{
    public class LightTests
    {
        [Fact]
        public void OffsetFollowsTimePhaseAndPeriod()
        {
            Assert.Equal(0f, LightSegment.Offset(2f, 0f, 0f), 5);
            Assert.Equal(0.5f, LightSegment.Offset(2f, 0f, 1f), 5);
            Assert.Equal(0f, LightSegment.Offset(1.6f, 0f, 1.6f), 5);
            Assert.Equal(0.65f, LightSegment.Offset(2f, -0.7f, 0f), 5);
            // One full lap per period: offset advances linearly and wraps.
            Assert.Equal(LightSegment.Offset(2f, 0f, 0.3f), LightSegment.Offset(2f, 0f, 2.3f), 5);
        }

        [Fact]
        public void SegmentCoversThirteenPercentAndWraps()
        {
            Assert.True(LightSegment.IsLit(0.05f, 0f));
            Assert.False(LightSegment.IsLit(0.13f, 0f));
            Assert.False(LightSegment.IsLit(0.999f, 0f));
            Assert.True(LightSegment.IsLit(0.02f, 0.95f));    // wraps past u = 1
            Assert.False(LightSegment.IsLit(0.10f, 0.95f));
            int lit = 0;
            for (int i = 0; i < 1000; i++) if (LightSegment.IsLit(i / 1000f, 0.37f)) lit++;
            Assert.InRange(lit, 129, 131);
        }

        [Fact]
        public void LitCentreAndDarkPointAreHalfALapApart()
        {
            for (float offset = 0f; offset < 1f; offset += 0.1f)
            {
                float lit = LightSegment.LitCentreU(offset), dark = LightSegment.DarkU(offset);
                Assert.True(LightSegment.IsLit(lit, offset));
                Assert.False(LightSegment.IsLit(dark, offset));
                Assert.Equal(0.5f, LightSegment.Frac(dark - lit), 5);
            }
        }

        [Fact]
        public void ScheduleSpreadsPeriodsAndPhasesAcrossIds()
        {
            // Spec 11.5: about one part in four at 1.6 s, phases spread over three values.
            var parts = new List<PartDefinition>();
            for (int i = 0; i < 400; i++) parts.Add(new PartDefinition { Id = "part_" + i, Shape = Shape.Circle });
            parts.Add(new PartDefinition { Id = "reach", Shape = Shape.Circle, Dashed = true });
            LightSchedule.Assign(parts);
            int fast = 0;
            var phases = new int[3];
            foreach (PartDefinition p in parts)
            {
                if (p.Dashed) { Assert.Equal(-1, p.PeriodIndex); continue; }
                if (p.PeriodIndex == 1) fast++;
                phases[p.PhaseIndex]++;
            }
            Assert.InRange(fast / 400f, 0.18f, 0.32f);
            foreach (int n in phases) Assert.InRange(n / 400f, 0.25f, 0.42f);
        }

        [Fact]
        public void CarriedPartsKeepTheirScheduleWhateverTheListOrder()
        {
            // A part carried between tiers keeps its light, so it runs on continuously through the reshape.
            var a = new List<PartDefinition> { new PartDefinition { Id = "blob", Shape = Shape.Circle }, new PartDefinition { Id = "tail_1", Shape = Shape.Circle } };
            var b = new List<PartDefinition>
            {
                new PartDefinition { Id = "tether_tail_1", Shape = Shape.Tether },
                new PartDefinition { Id = "pod_l", Shape = Shape.Circle },
                new PartDefinition { Id = "tail_1", Shape = Shape.Circle },
                new PartDefinition { Id = "blob", Shape = Shape.Circle },
            };
            LightSchedule.Assign(a);
            LightSchedule.Assign(b);
            Assert.Equal((a[0].PeriodIndex, a[0].PhaseIndex), (b[3].PeriodIndex, b[3].PhaseIndex));
            Assert.Equal((a[1].PeriodIndex, a[1].PhaseIndex), (b[2].PeriodIndex, b[2].PhaseIndex));
            // The crossfading old copy of a part keeps its schedule too.
            var old = new List<PartDefinition> { new PartDefinition { Id = "blob~old", Shape = Shape.Circle } };
            LightSchedule.Assign(old);
            Assert.Equal((a[0].PeriodIndex, a[0].PhaseIndex), (old[0].PeriodIndex, old[0].PhaseIndex));
        }

        [Fact]
        public void PinnedScheduleValuesAreKept()
        {
            var parts = new List<PartDefinition> { new PartDefinition { Id = "a", Shape = Shape.Circle, PeriodIndex = 1, PhaseIndex = 2 } };
            LightSchedule.Assign(parts);
            Assert.Equal((1, 2), (parts[0].PeriodIndex, parts[0].PhaseIndex));
        }

        [Fact]
        public void PartGeometryExposesPeriodAndPhaseInSeconds()
        {
            var p = GeometryTests.Part("c", Shape.Circle, ("radius", 5f));
            p.PeriodIndex = 1;
            p.PhaseIndex = 2;
            PartGeometry pg = GeometryTests.Geom(p).Parts[0];
            Assert.Equal(1.6f, pg.Period);
            Assert.Equal(-1.3f, pg.Phase);
        }
    }
}
