using System;
using Gridlock.Core;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;
using Xunit;
using static Gridlock.Core.Tests.TestHelpers;

namespace Gridlock.Core.Tests
{
    /// <summary>
    /// Regressions for defects found by the spec-compliance audit. One test per
    /// confirmed finding, named for what it protects.
    /// </summary>
    public class AuditRegressionTests
    {
        // ---- Loader: strict typing, version default ----

        [Fact]
        public void Loader_Reject_WrongTypedValue_InsteadOfSilentDefault()
        {
            string json = LevelWriter.Write(DevBoards.TwoNodeStrip()).Replace("\"q\": 2", "\"q\": \"2\"");
            var ex = Assert.Throws<LevelValidationException>(() => LevelLoader.LoadFromJson(json, new Tuning()));
            Assert.Contains("must be a number", ex.Message);
        }

        [Fact]
        public void Loader_Reject_FractionalIntegerKey_InsteadOfTruncating()
        {
            string json = LevelWriter.Write(DevBoards.TwoNodeStrip()).Replace("\"q\": 2", "\"q\": 2.5");
            var ex = Assert.Throws<LevelValidationException>(() => LevelLoader.LoadFromJson(json, new Tuning()));
            Assert.Contains("whole number", ex.Message);
        }

        [Fact]
        public void Loader_Reject_WrongTypedString()
        {
            string json = LevelWriter.Write(DevBoards.TwoNodeStrip()).Replace("\"name\": \"Dev Strip\"", "\"name\": 7");
            Assert.Contains("\"name\": 7", json);
            var ex = Assert.Throws<LevelValidationException>(() => LevelLoader.LoadFromJson(json, new Tuning()));
            Assert.Contains("must be a string", ex.Message);
        }

        [Fact]
        public void Loader_Accepts_MissingVersion_AsFormatV1()
        {
            // The spec §10.1 example JSON carries no "version" key; it must load.
            string json = LevelWriter.Write(DevBoards.TwoNodeStrip());
            int cut = json.IndexOf("\"version\"", StringComparison.Ordinal);
            int end = json.IndexOf('\n', cut) + 1;
            string versionless = json.Remove(cut, end - cut);
            Assert.DoesNotContain("\"version\"", versionless);

            BuiltLevel built = LevelLoader.LoadFromJson(versionless, new Tuning());
            Assert.Equal(2, built.Nodes.Count);
        }

        [Fact]
        public void Loader_Reject_ExplicitWrongVersion()
        {
            string json = LevelWriter.Write(DevBoards.TwoNodeStrip()).Replace("\"version\": 1", "\"version\": 3");
            var ex = Assert.Throws<LevelValidationException>(() => LevelLoader.LoadFromJson(json, new Tuning()));
            Assert.Contains("Unsupported level version 3", ex.Message);
        }

        // ---- StateHash covers send counters ----

        [Fact]
        public void StateHash_DistinguishesSendCounts()
        {
            // Same board state, different send counts: on an Efficiency level the
            // next release behaves differently, so the fingerprints must differ.
            LevelData Make()
            {
                LevelData l = DevBoards.TwoNodeStrip(playerCharge: 12f);
                l.Objective = ObjectiveType.Efficiency;
                l.ObjectiveMaxSends = 5;
                return l;
            }
            var a = NewSim(Make(), FrozenTuning());
            var b = NewSim(Make(), FrozenTuning());

            // Burn one send in `a` with zero lasting board effect: hold, then let
            // the release fire and immediately restore the charge it spent.
            a.EnqueueBeginHold(Owner.Player, 0);
            a.EnqueueReleaseSend(Owner.Player, 0, 0);
            a.Step();
            foreach (Beam beam in new System.Collections.Generic.List<Beam>(a.Beams)) { }
            Assert.Equal(1, a.PlayerSends);
            Assert.Equal(0, b.PlayerSends);

            // Force identical node/beam state by clearing a's beam effect: compare
            // hashes of two sims whose ONLY difference is the send counter.
            var c = NewSim(Make(), FrozenTuning());
            var d = NewSim(Make(), FrozenTuning());
            c.EnqueueBeginHold(Owner.Player, 0);
            c.EnqueueCancelHold(Owner.Player, 0);
            c.Step();
            d.Step();
            Assert.Equal(StateHash.Compute(c), StateHash.Compute(d)); // a cancel is not a send
            Assert.NotEqual(StateHash.Compute(a), StateHash.Compute(b));
        }

        // ---- Overcharge armed latch ----

        [Fact]
        public void OverchargeArmed_FiresOnce_AndSurvivesLiveTuningChange()
        {
            var tuning = FrozenTuning();
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), tuning);
            int armedCount = 0;
            sim.NodeOverchargeArmed += id => armedCount++;

            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();
            StepN(sim, 40);
            Assert.Equal(0, armedCount);

            // Debug panel drops the burst threshold below the elapsed hold: the
            // armed signal must still fire (it is a latch on >=, not an equality).
            tuning.OverchargeTime = 0.5f; // 30 ticks < 41 elapsed
            sim.Step();
            Assert.Equal(1, armedCount);

            StepN(sim, 30);
            Assert.Equal(1, armedCount); // exactly once per hold

            // And the release does burst, matching what the signal promised.
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            sim.Step();
            Assert.Equal(NodeState.Disabled, sim.NodeById(0).State);
        }

        [Fact]
        public void OverchargeArmed_ResetsForTheNextHold()
        {
            var sim = NewSim(DevBoards.Chain3(playerCharge: 12f), FrozenTuning());
            int armedCount = 0;
            sim.NodeOverchargeArmed += id => armedCount++;

            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();
            StepN(sim, 90);
            Assert.Equal(1, armedCount);
            sim.EnqueueCancelHold(Owner.Player, 0);
            sim.Step();
            Assert.False(sim.NodeById(0).OverchargeArmed);

            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();
            StepN(sim, 90);
            Assert.Equal(2, armedCount); // a second hold arms again
        }

        // ---- Contest reinforcement is power-only ----

        [Fact]
        public void Reinforce_DoesNotChangeSideSpeed_SurvivorKeepsOriginalSpeed()
        {
            var tuning = FrozenTuning();
            tuning.ContestPushSpeed = 0f; // isolate: resolve by side death, not endpoint
            var sim = NewSim(DevBoards.TwoNodeStrip(), tuning);
            Contest c = sim.SpawnContestForTest(0, 0.5f, 5f, 5f, 1, 4f, 4f);
            sim.SpawnBeamForTest(0, Owner.Player, 20f, 10f, 0.2f, 1); // burst-speed reinforcement

            int t = StepUntil(sim, s => s.Beams.Count == 0, 60);
            Assert.True(t >= 0, "reinforcement never absorbed");
            Assert.Equal(4f, c.SpeedPlayer); // power lent, momentum not
            Assert.True(c.PowerPlayer > 24f);

            int t2 = StepUntil(sim, s => s.Contests.Count == 0, 4000);
            Assert.True(t2 >= 0, "contest never resolved");
            Assert.Single(sim.Beams);
            Assert.Equal(4f, sim.Beams[0].Speed); // survivor resumes at its ORIGINAL speed
        }

        // ---- Survive objective is decided at the deadline ----

        [Fact]
        public void Objective_Survive_ZeroNodesAtDeadline_IsALoss_NotADeferredWin()
        {
            LevelData level = DevBoards.Chain3(playerCharge: 1f);
            level.Objective = ObjectiveType.Survive;
            level.ObjectiveSeconds = 1f; // deadline at tick 60
            var sim = NewSim(level, FrozenTuning());

            // The player's only node falls at ~tick 6, while a slow player beam
            // is still crossing the far wire — it would capture the AI node at
            // ~tick 120, i.e. LONG after the bell. The old standing-condition
            // check handed the player a retroactive win there.
            sim.SpawnBeamForTest(1, Owner.Player, 30f, 2f, 0f, 1);
            sim.SpawnBeamForTest(0, Owner.Ai, 20f, 4f, 0.1f, -1);

            int t = StepUntil(sim, s => s.NodeById(0).Owner == Owner.Ai, 60);
            Assert.True(t >= 0, "home never fell");

            int t2 = StepUntil(sim, s => s.Result != MatchResult.None, 300);
            Assert.True(t2 >= 0, "match never decided");
            Assert.Equal(MatchResult.AiWin, sim.Result); // held nothing at the bell
            Assert.True(sim.Tick <= 61, "decided at the deadline, not later (tick " + sim.Tick + ")");
            Assert.Single(sim.Beams); // and the would-be winning beam was still in flight
        }
    }
}
