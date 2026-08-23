using System;
using Gridlock.Core;
using Gridlock.Core.Levels;
using Xunit;
using static Gridlock.Core.Tests.TestHelpers;

namespace Gridlock.Core.Tests
{
    public class ContestMathTests
    {
        [Fact]
        public void Contest_Tick1_ExactValues()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            Contest c = sim.SpawnContestForTest(0, 0.5f, 10f, 5f, dirPlayer: 1, speedPlayer: 4f, speedAi: 4f);
            sim.Step();

            // burnP = 5·0.30/60 = 0.025 ; burnA = 10·0.30/60 = 0.05
            Assert.True(Math.Abs(c.PowerPlayer - 9.975f) < 1e-5f, "P " + c.PowerPlayer);
            Assert.True(Math.Abs(c.PowerAi - 4.95f) < 1e-5f, "A " + c.PowerAi);
            // push = (9.975−4.95)/14.925 (POST-burn values per spec ordering)
            float push = (9.975f - 4.95f) / (9.975f + 4.95f);
            float expectedT = 0.5f + push * 0.55f / 60f;
            Assert.True(Math.Abs(c.ContactT - expectedT) < 1e-6f,
                "contactT " + c.ContactT + " expected " + expectedT);
        }

        [Fact]
        public void Contest_DiscreteLanchesterInvariant()
        {
            // (P² − A²)ₙ = (P₀² − A₀²)·(1 − r²dt²)ⁿ — exact for the spec's
            // pre-tick-burn update rule; a tolerance-free correctness oracle.
            // Push disabled so the front cannot reach an endpoint mid-measurement.
            // Sides close enough (10 vs 9.5) that both outlive every checkpoint:
            // continuous Lanchester predicts the weaker side dies at
            // atanh(0.95)/0.30 ≈ 6.1 s ≈ 366 ticks, past the last checkpoint.
            var tuning = FrozenTuning();
            tuning.ContestPushSpeed = 0f;
            var sim = NewSim(DevBoards.TwoNodeStrip(), tuning);
            Contest c = sim.SpawnContestForTest(0, 0.5f, 10f, 9.5f, 1, 4f, 4f);

            double rdt = 0.30 / 60.0;
            double factor = 1.0 - rdt * rdt;
            double inv0 = 100.0 - 90.25;

            foreach (int n in new[] { 1, 59, 240 })
            {
                long start = sim.Tick;
                while (sim.Tick < start + n) sim.Step();
                Assert.Single(sim.Contests); // both sides must still be alive to measure
                double expected = inv0 * Math.Pow(factor, sim.Tick);
                double actual = (double)c.PowerPlayer * c.PowerPlayer - (double)c.PowerAi * c.PowerAi;
                Assert.True(Math.Abs(actual - expected) / expected < 1e-3,
                    "tick " + sim.Tick + ": invariant " + actual + " expected " + expected);
            }
        }

        [Fact]
        public void Contest_StrongerWins_SurvivorNearSqrtInvariant()
        {
            // Slow push so the weaker side burns out long before the front could
            // reach an endpoint — this test targets the side-death path.
            var tuning = FrozenTuning();
            tuning.ContestPushSpeed = 0.05f;
            var sim = NewSim(DevBoards.TwoNodeStrip(), tuning);
            sim.SpawnContestForTest(0, 0.5f, 10f, 5f, 1, 4f, 4f);
            Owner winner = Owner.Neutral;
            float survivorPower = -1f;
            sim.ContestResolved += (id, wireId, w, p) => { winner = w; survivorPower = p; };

            int ticks = StepUntil(sim, s => s.Contests.Count == 0, 20000);
            Assert.True(ticks >= 0, "contest never resolved");
            Assert.Equal(Owner.Player, winner);
            // Continuous Lanchester predicts sqrt(10² − 5²) = 8.660; discrete is very close.
            Assert.True(Math.Abs(survivorPower - 8.660f) < 0.05f, "survivor " + survivorPower);
            Assert.Equal(1, sim.ContestSideDeathResolutions);

            // The survivor resumes as a beam with its own speed and direction.
            Assert.Single(sim.Beams);
            Assert.Equal(Owner.Player, sim.Beams[0].Owner);
            Assert.Equal(1, sim.Beams[0].Dir);
            Assert.Equal(4f, sim.Beams[0].Speed);
        }

        [Fact]
        public void Contest_EqualPowers_NoPush_MutualDeath()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            Contest c = sim.SpawnContestForTest(0, 0.4f, 5f, 5f, 1, 4f, 4f);
            Owner winner = Owner.Player;
            sim.ContestResolved += (id, wireId, w, p) => winner = w;

            StepN(sim, 100);
            Assert.Equal(0.4f, c.ContactT); // push is exactly zero while equal
            int ticks = StepUntil(sim, s => s.Contests.Count == 0, 4000);
            Assert.True(ticks >= 0, "never resolved");
            Assert.Equal(Owner.Neutral, winner); // mutual annihilation
            Assert.Equal(1, sim.ContestMutualDeaths);
            Assert.Empty(sim.Beams);
        }

        [Fact]
        public void Contest_PushDirection_TowardWeakerSide_BothDirections()
        {
            // Player stronger, player travelling A→B: front moves toward B (up).
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            Contest c1 = sim.SpawnContestForTest(0, 0.5f, 10f, 5f, 1, 4f, 4f);
            sim.Step();
            Assert.True(c1.ContactT > 0.5f);

            // Player stronger but travelling B→A: front moves toward A (down).
            var sim2 = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            Contest c2 = sim2.SpawnContestForTest(0, 0.5f, 10f, 5f, -1, 4f, 4f);
            sim2.Step();
            Assert.True(c2.ContactT < 0.5f);
        }

        [Fact]
        public void Contest_EndpointReached_WinnerArrivesAndCaptures_LoserDestroyed()
        {
            // Overwhelming player side near the ai end: the front is shoved into
            // node B while BOTH sides are alive → player arrives with remaining
            // power, ai side's power is destroyed (matrix #14).
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            sim.SpawnContestForTest(0, 0.98f, 100f, 10f, 1, 4f, 4f);
            Owner captured = Owner.Neutral;
            sim.NodeCaptured += (nodeId, newOwner, prev) => { if (nodeId == 1) captured = newOwner; };

            int ticks = StepUntil(sim, s => s.Contests.Count == 0, 600);
            Assert.True(ticks >= 0, "never resolved");
            Assert.Equal(1, sim.ContestEndpointResolutions);
            Assert.Equal(Owner.Player, captured); // arrived and flipped the (0-charge) ai node
            Assert.Empty(sim.Beams);              // loser side left nothing behind
            Assert.Equal(MatchResult.PlayerWin, sim.Result);
        }

        [Fact]
        public void Contest_SittingOnBoundaryWithZeroPush_DoesNotArrive()
        {
            // Formed exactly at t=0 with equal powers: no movement → no endpoint
            // arrival; it grinds to mutual death (matrix #11 + #15).
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            sim.SpawnContestForTest(0, 0f, 0.001f, 0.001f, 1, 4f, 4f);
            StepN(sim, 500);
            Assert.Empty(sim.Contests);
            Assert.Equal(0, sim.ContestEndpointResolutions);
            Assert.Equal(1, sim.ContestMutualDeaths);
        }

        [Fact]
        public void Contest_DefenderCollapse_EnemyArrivesAtAttackerOriginNode()
        {
            // AI side stronger, player travelling A→B (so the AI side travels
            // B→A): the AI shoves the front all the way back to node A — the
            // PLAYER's own node — and arrives there (matrix #14 reverse case).
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 3f), FrozenTuning());
            sim.SpawnContestForTest(0, 0.02f, 10f, 100f, 1, 4f, 4f);
            Owner captured = Owner.Neutral;
            sim.NodeCaptured += (nodeId, newOwner, prev) => { if (nodeId == 0) captured = newOwner; };

            int ticks = StepUntil(sim, s => s.Contests.Count == 0, 600);
            Assert.True(ticks >= 0);
            Assert.Equal(Owner.Ai, captured); // 100-ish power vs 3 charge: flipped
            Assert.Equal(1, sim.ContestEndpointResolutions);
        }
    }
}
