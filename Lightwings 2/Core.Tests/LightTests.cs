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
        public void ScheduleSpreadsPeriodsAndPhases()
        {
            var parts = new List<PartDefinition>();
            for (int i = 0; i < 12; i++) parts.Add(new PartDefinition { Id = "p" + i, Shape = Shape.Circle });
            var dashed = new PartDefinition { Id = "reach", Shape = Shape.Circle, Dashed = true };
            parts.Insert(4, dashed);
            LightSchedule.Assign(parts);

            int fast = 0;
            var phases = new int[3];
            foreach (PartDefinition p in parts)
            {
                if (p.Dashed) { Assert.Equal(-1, p.PeriodIndex); continue; }
                if (p.PeriodIndex == 1) fast++;
                phases[p.PhaseIndex]++;
            }
            Assert.Equal(3, fast);                         // every fourth part runs at 1.6 s
            Assert.Equal(new[] { 4, 4, 4 }, phases);       // phases 0 / -0.7 / -1.3 evenly spread
            Assert.Equal(1, parts[3].PeriodIndex);
            Assert.Equal(0, parts[0].PeriodIndex);
        }

        [Fact]
        public void PinnedScheduleValuesAreKept()
        {
            var parts = new List<PartDefinition>
            {
                new PartDefinition { Id = "a", Shape = Shape.Circle, PeriodIndex = 1, PhaseIndex = 2 },
                new PartDefinition { Id = "b", Shape = Shape.Circle },
            };
            LightSchedule.Assign(parts);
            Assert.Equal((1, 2), (parts[0].PeriodIndex, parts[0].PhaseIndex));
            Assert.Equal((0, 1), (parts[1].PeriodIndex, parts[1].PhaseIndex));
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
