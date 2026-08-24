using System;
using Gridlock.Core;
using Gridlock.Core.Levels;
using Xunit;
using static Gridlock.Core.Tests.TestHelpers;

namespace Gridlock.Core.Tests
{
    public class SweepInteractionTests
    {
        [Fact]
        public void Crossing_OpposingBeams_SpawnContestAtContactPoint()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 10f, 4f, 0f, 1);
            sim.SpawnBeamForTest(0, Owner.Ai, 5f, 4f, 1f, -1);
            float contactT = -1f;
            sim.ContestStarted += (id, wireId, t) => contactT = t;

            int ticks = StepUntil(sim, s => s.Contests.Count == 1, 60);
            Assert.True(ticks >= 0, "no contest formed");
            Assert.Empty(sim.Beams); // both beams consumed
            Assert.True(Math.Abs(contactT - 0.5f) < 0.02f, "contactT " + contactT);
            Assert.Equal(1, sim.Contests[0].DirPlayer);
            Assert.Equal(1, sim.ContestsStarted);
        }

        [Fact]
        public void Reinforce_AbsorbedIntoOwnSide_FromBehind()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            Contest c = sim.SpawnContestForTest(0, 0.5f, 5f, 5f, 1, 4f, 4f);
            sim.SpawnBeamForTest(0, Owner.Player, 3f, 4f, 0.1f, 1);
            Owner reinforcedSide = Owner.Neutral;
            float reinforcedPower = -1f;
            sim.ContestReinforced += (id, wireId, side, p) => { reinforcedSide = side; reinforcedPower = p; };

            int ticks = StepUntil(sim, s => s.Beams.Count == 0, 60);
            Assert.True(ticks >= 0, "beam never absorbed");
            Assert.Equal(Owner.Player, reinforcedSide);
            Assert.Equal(3f, reinforcedPower);
            // Equal burn kept the sides level until absorption, so post-absorb
            // difference is exactly the beam's power.
            Assert.True(Math.Abs((c.PowerPlayer - c.PowerAi) - 3f) < 1e-3f,
                "difference " + (c.PowerPlayer - c.PowerAi));
        }

        [Fact]
        public void Reinforce_AbsorbedIntoOwnSide_FromTheWrongGeometricSide()
        {
            // A player beam coming from the B end (owner-based absorption — the
            // post-capture reinforcement case, matrix #5).
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            Contest c = sim.SpawnContestForTest(0, 0.5f, 5f, 5f, 1, 4f, 4f);
            sim.SpawnBeamForTest(0, Owner.Player, 4f, 4f, 0.9f, -1);

            int ticks = StepUntil(sim, s => s.Beams.Count == 0, 60);
            Assert.True(ticks >= 0, "beam never absorbed");
            Assert.True(c.PowerPlayer > c.PowerAi + 3.9f);
        }

        [Fact]
        public void Reinforce_LendsPowerNotSpeed()
        {
            // Spec §5.6: reinforcement adds POWER to the side; the survivor later
            // resumes at its "original speed". Speed and power stay separate axes
            // (§5.4). Full survivor-speed regression lives in AuditRegressionTests.
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            Contest c = sim.SpawnContestForTest(0, 0.5f, 5f, 5f, 1, 4f, 4f);
            sim.SpawnBeamForTest(0, Owner.Player, 3f, 10f, 0.2f, 1); // burst-speed reinforcement
            StepUntil(sim, s => s.Beams.Count == 0, 60);
            Assert.Equal(4f, c.SpeedPlayer);
            Assert.Equal(4f, c.SpeedAi);
            Assert.True(c.PowerPlayer > c.PowerAi + 2.9f);
        }

        [Fact]
        public void Merge_PowerSum_SpeedMax_FrontIdKept()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            Beam front = sim.SpawnBeamForTest(0, Owner.Player, 3f, 4f, 0.3f, 1);
            Beam rear = sim.SpawnBeamForTest(0, Owner.Player, 5f, 10f, 0.1f, 1);
            int keptId = -1, goneId = -1;
            sim.BeamMerged += (kept, gone) => { keptId = kept; goneId = gone; };

            int ticks = StepUntil(sim, s => s.Beams.Count == 1, 60);
            Assert.True(ticks >= 0, "never merged");
            Assert.Equal(front.Id, keptId);
            Assert.Equal(rear.Id, goneId);
            Assert.Equal(8f, sim.Beams[0].Power);
            Assert.Equal(10f, sim.Beams[0].Speed);
        }

        [Fact]
        public void SameOwner_OppositeDirections_NetOut()
        {
            // Charge flowing both ways along one wire nets out; the difference
            // carries on in the direction of the larger send. Letting them pass
            // through instead is what allowed a second front on one wire — see
            // AuditRegressionTests.Sweep_NoSecondContestOnAWire.
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 3f, 4f, 0.2f, 1);
            Beam bigger = sim.SpawnBeamForTest(0, Owner.Player, 5f, 4f, 0.8f, -1);

            int t = StepUntil(sim, s => s.Beams.Count <= 1, 60);
            Assert.True(t >= 0, "beams never netted");
            Assert.Single(sim.Beams);
            Assert.Equal(bigger.Id, sim.Beams[0].Id);
            Assert.True(Math.Abs(sim.Beams[0].Power - 2f) < 1e-5f, "power " + sim.Beams[0].Power);
            Assert.Equal(-1, sim.Beams[0].Dir);
        }

        [Fact]
        public void SameOwner_OppositeDirections_EqualPower_BothConsumed()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 4f, 4f, 0.2f, 1);
            sim.SpawnBeamForTest(0, Owner.Player, 4f, 4f, 0.8f, -1);
            int t = StepUntil(sim, s => s.Beams.Count == 0, 60);
            Assert.True(t >= 0, "beams never netted");
        }

        [Fact]
        public void Chase_StrongerRearCatchesWeakerFront_SurvivesWithDifference()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 3f, 4f, 0.3f, 1);
            Beam rear = sim.SpawnBeamForTest(0, Owner.Ai, 5f, 10f, 0.1f, 1);
            int survivorId = -2;
            sim.BeamClashed += (id, wireId) => survivorId = id;

            int ticks = StepUntil(sim, s => s.Beams.Count == 1, 60);
            Assert.True(ticks >= 0, "never clashed");
            Assert.Equal(rear.Id, survivorId);
            Assert.Equal(Owner.Ai, sim.Beams[0].Owner);
            Assert.True(Math.Abs(sim.Beams[0].Power - 2f) < 1e-5f);
            Assert.Equal(0, sim.ContestsStarted); // a chase never becomes a contest
        }

        [Fact]
        public void Chase_EqualPower_BothDestroyed()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 4f, 4f, 0.3f, 1);
            sim.SpawnBeamForTest(0, Owner.Ai, 4f, 10f, 0.1f, 1);
            int survivorId = -2;
            sim.BeamClashed += (id, wireId) => survivorId = id;

            int ticks = StepUntil(sim, s => s.Beams.Count == 0, 60);
            Assert.True(ticks >= 0);
            Assert.Equal(-1, survivorId);
        }

        [Fact]
        public void Merge_BeforeCrossing_ChronologicalOrder()
        {
            // Three beams: two player beams merge first (τ ≈ early), then the
            // merged beam meets the ai beam → the contest carries the SUMMED power.
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 3f, 4f, 0.28f, 1);
            sim.SpawnBeamForTest(0, Owner.Player, 5f, 12f, 0.22f, 1); // fast rear, catches in ~2 ticks
            sim.SpawnBeamForTest(0, Owner.Ai, 6f, 4f, 0.95f, -1);

            int ticks = StepUntil(sim, s => s.Contests.Count == 1, 120);
            Assert.True(ticks >= 0, "no contest");
            Assert.True(Math.Abs(sim.Contests[0].PowerPlayer - 8f) < 1e-4f,
                "merged power should enter the contest, got " + sim.Contests[0].PowerPlayer);
            Assert.Equal(6f, sim.Contests[0].PowerAi);
        }

        [Fact]
        public void SpawnOntoWireWithContestBetweenBeamAndTarget_AbsorbedNotDuplicated()
        {
            // A beam spawned at t=0 with the contest at 0.15 travelling toward it:
            // absorbed on contact; never forms a second contest (matrix #7/#10).
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), FrozenTuning());
            sim.SpawnContestForTest(0, 0.15f, 5f, 5f, 1, 4f, 4f);
            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            StepN(sim, 20);
            Assert.Single(sim.Contests);
            Assert.Empty(sim.Beams);
            Assert.True(sim.Contests[0].PowerPlayer > sim.Contests[0].PowerAi + 3f);
        }

        [Fact]
        public void Arrivals_SameTick_EarlierTauResolvesFirst()
        {
            // Player beam (τ ≈ 0.06) and ai beam (τ ≈ 0.3) reach the ai node in
            // the SAME tick. τ-order: the player beam captures first (12 > 10 →
            // charge 2), then the ai beam re-captures (5 > 2 → charge 3, Ai).
            // The wrong order would instead deposit-then-chip and end at charge 0
            // — so this asserts the ordering, not just the endpoint.
            var sim = NewSim(DevBoards.TwoNodeStrip(aiCharge: 10f), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 12f, 4f, 0.999f, 1);
            sim.SpawnBeamForTest(0, Owner.Ai, 5f, 4f, 0.995f, 1); // same dir, same speed: no clash
            var captures = new System.Collections.Generic.List<Owner>();
            sim.NodeCaptured += (nodeId, newOwner, prev) => captures.Add(newOwner);

            sim.Step();
            Assert.Equal(new[] { Owner.Player, Owner.Ai }, captures.ToArray());
            Assert.Equal(Owner.Ai, sim.NodeById(1).Owner);
            Assert.True(Math.Abs(sim.NodeById(1).Charge - 3f) < 1e-4f,
                "charge " + sim.NodeById(1).Charge);
            Assert.Empty(sim.Beams);
        }
    }
}
