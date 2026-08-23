using System;
using System.Diagnostics;
using Gridlock.Core;
using Gridlock.Core.Ai;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;
using Xunit;
using static Gridlock.Core.Tests.TestHelpers;

namespace Gridlock.Core.Tests
{
    public class DeterminismAndAiTests
    {
        [Fact]
        public void Determinism_SameSeed_IdenticalResultAndHash()
        {
            MatchStats a = HeadlessMatch.Run(DevBoards.Duel(), new Tuning(), 5, 5, seed: 42);
            MatchStats b = HeadlessMatch.Run(DevBoards.Duel(), new Tuning(), 5, 5, seed: 42);
            Assert.Equal(a.Result, b.Result);
            Assert.Equal(a.Ticks, b.Ticks);
            Assert.Equal(a.FinalHash, b.FinalHash);
        }

        [Fact]
        public void Determinism_DifferentSeeds_Diverge()
        {
            MatchStats a = HeadlessMatch.Run(DevBoards.Duel(), new Tuning(), 5, 5, seed: 1);
            MatchStats b = HeadlessMatch.Run(DevBoards.Duel(), new Tuning(), 5, 5, seed: 2);
            Assert.NotEqual(a.FinalHash, b.FinalHash);
        }

        [Fact]
        public void Determinism_ScriptedIntentTrajectory_HashesMatchEvery60Ticks()
        {
            Simulation Make() => NewSim(DevBoards.Chain3(playerCharge: 10f, aiCharge: 10f));
            Simulation s1 = Make();
            Simulation s2 = Make();
            void Script(Simulation s, int tick)
            {
                if (tick == 10) { s.EnqueueBeginHold(Owner.Player, 0); }
                if (tick == 40) { s.EnqueueReleaseSend(Owner.Player, 0, 0); }
                if (tick == 50) { s.EnqueueBeginHold(Owner.Ai, 2); }
                if (tick == 140) { s.EnqueueReleaseSend(Owner.Ai, 2, 1); }
            }
            for (int t = 0; t < 600; t++)
            {
                Script(s1, t);
                Script(s2, t);
                s1.Step();
                s2.Step();
                if (t % 60 == 0)
                    Assert.Equal(StateHash.Compute(s1), StateHash.Compute(s2));
            }
            Assert.Equal(StateHash.Compute(s1), StateHash.Compute(s2));
        }

        [Fact]
        public void Ai_TierTable_MatchesSpecExactly()
        {
            AiDifficulty t1 = AiDifficulty.FromTier(1);
            Assert.Equal(3.0f, t1.DecisionInterval);
            Assert.Equal(0.50f, t1.NoiseFactor);
            Assert.Equal(8f, t1.ActionThreshold);
            Assert.False(t1.BurstEnabled);
            Assert.False(t1.ThreatResponse);
            Assert.False(t1.Anticipate);

            AiDifficulty t3 = AiDifficulty.FromTier(3);
            Assert.True(t3.ThreatResponse);
            Assert.False(t3.BurstEnabled);

            AiDifficulty t4 = AiDifficulty.FromTier(4);
            Assert.True(t4.BurstEnabled);
            Assert.False(t4.Anticipate);

            AiDifficulty t6 = AiDifficulty.FromTier(6);
            Assert.True(t6.Anticipate);

            AiDifficulty t10 = AiDifficulty.FromTier(10);
            Assert.Equal(0.6f, t10.DecisionInterval);
            Assert.Equal(0.05f, t10.NoiseFactor);
            Assert.Equal(3f, t10.ActionThreshold);
        }

        [Fact]
        public void AiVsAi_RunsToCompletion_PrintsAWinner()
        {
            // Spec M1 exit bar: a full AI-vs-AI match terminates with a winner.
            foreach (ulong seed in new ulong[] { 1, 2, 3 })
            {
                MatchStats stats = HeadlessMatch.Run(DevBoards.Duel(), new Tuning(), 5, 5, seed);
                Assert.True(stats.Result == MatchResult.PlayerWin || stats.Result == MatchResult.AiWin,
                    "seed " + seed + " ended " + stats.Result + " after " + stats.SimSeconds + "s");
            }
        }

        [Fact]
        public void Ai_UsesHoldPipeline_OpponentSeesOvercharging()
        {
            var sim = NewSim(DevBoards.Duel());
            var rng = new DeterministicRandom(7);
            sim.AddController(new AiController(Owner.Player, AiDifficulty.FromTier(5), rng.Fork(1)));
            sim.AddController(new AiController(Owner.Ai, AiDifficulty.FromTier(5), rng.Fork(2)));

            bool playerBrightened = false, aiBrightened = false;
            sim.NodeStateChanged += (nodeId, state, prev) =>
            {
                if (state != NodeState.Overcharging) return;
                if (sim.NodeById(nodeId).Owner == Owner.Player) playerBrightened = true;
                else if (sim.NodeById(nodeId).Owner == Owner.Ai) aiBrightened = true;
            };

            int t = StepUntil(sim, s => (playerBrightened && aiBrightened) || s.Result != MatchResult.None, 36000);
            Assert.True(playerBrightened, "player-side AI never telegraphed a hold");
            Assert.True(aiBrightened, "ai-side AI never telegraphed a hold");
        }

        [Fact]
        public void Ai_HardFilter_NeverOffersAnUnwinnableSend()
        {
            // The player node's only wire carries an overwhelming enemy beam:
            // every candidate must be discarded BEFORE noise, at every tier.
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 12f), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Ai, 50f, 4f, 0.9f, -1);

            var rng = new DeterministicRandom(1);
            Candidate best = CandidateScorer.PickBest(sim, Owner.Player,
                AiDifficulty.FromTier(10), rng, out int rejected);
            Assert.Null(best);
            Assert.True(rejected >= 1, "filter should have rejected the doomed candidates");
        }

        [Fact]
        public void Ai_Reinforce_FlippableContestGetsSent()
        {
            // Losing contest on the wire that CAN be flipped: the filter allows it
            // and W_REINFORCE makes it attractive.
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 12f), FrozenTuning());
            sim.SpawnContestForTest(0, 0.5f, 3f, 6f, 1, 4f, 4f); // player losing by 3

            var rng = new DeterministicRandom(1);
            Candidate best = CandidateScorer.PickBest(sim, Owner.Player,
                AiDifficulty.FromTier(10), rng, out _);
            Assert.NotNull(best);
            Assert.Equal(0, best.WireId);
            Assert.True(best.ProjectedPower + 3f > 6f, "must send enough to flip");
        }

        [Fact]
        public void Perf_AiVsAiDuel_MeanStepBudget()
        {
            // Realistic workload: a full tier-8 duel. Budget: mean Step ≤ 250 µs
            // (the M5 perf gate re-measures on real campaign boards).
            var sw = Stopwatch.StartNew();
            MatchStats stats = HeadlessMatch.Run(DevBoards.Duel(), new Tuning(), 8, 8, seed: 11);
            sw.Stop();
            double usPerTick = sw.Elapsed.TotalMilliseconds * 1000.0 / Math.Max(1, stats.Ticks);
            Assert.True(usPerTick < 250.0,
                "mean Step " + usPerTick.ToString("F1") + " µs over " + stats.Ticks + " ticks");
        }

        [Fact]
        [Trait("Category", "Balance")]
        public void Balance_Smoke_MirroredPairs_NoStalls_BothSidesWin()
        {
            var level = DevBoards.Duel();
            int playerWins = 0, aiWins = 0, timeouts = 0;
            const int pairs = 50;
            for (ulong seed = 1; seed <= pairs; seed++)
            {
                foreach (bool mirror in new[] { false, true })
                {
                    MatchStats s = HeadlessMatch.Run(DevBoards.Duel(), new Tuning(), 5, 5, seed, mirrorSeeds: mirror);
                    if (s.Result == MatchResult.PlayerWin) playerWins++;
                    else if (s.Result == MatchResult.AiWin) aiWins++;
                    else timeouts++;
                }
            }
            Assert.Equal(0, timeouts);
            int total = playerWins + aiWins;
            Assert.True(playerWins > total / 5 && aiWins > total / 5,
                "lopsided smoke: player " + playerWins + " / ai " + aiWins);
        }
    }
}
