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

        // ---- Sweep: the single-contest invariant is now TRUE, not asserted ----

        [Fact]
        public void Sweep_NoSecondContestOnAWire_OpposingBeamsNeverPassThrough()
        {
            // The exact sequence that used to trip the invariant guard: one side
            // puts two beams on a wire travelling opposite ways, then the other
            // side attacks from both ends, producing two disjoint crossings.
            // With netting the friendly pair collapses first, so only ONE front
            // can ever exist — and no opposing pair survives a crossing.
            var sim = NewSim(DevBoards.Chain3(), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 6f, 4f, 0.48f, 1);
            sim.SpawnBeamForTest(0, Owner.Player, 6f, 4f, 0.52f, -1);
            StepN(sim, 4);
            sim.SpawnBeamForTest(0, Owner.Ai, 5f, 4f, 0.0f, 1);
            sim.SpawnBeamForTest(0, Owner.Ai, 5f, 4f, 1.0f, -1);

            for (int i = 0; i < 400; i++)
            {
                sim.Step();
                Assert.True(CountContestsOnWire(sim, 0) <= 1,
                    "two contests on one wire at tick " + sim.Tick);
                AssertNoOpposingPairPassedThrough(sim);
            }
        }

        [Fact]
        public void Sweep_FuzzedTraffic_KeepsTheSingleContestInvariant()
        {
            // Random legal traffic on one wire from both sides. The invariant is
            // the thing the two-sided Contest type depends on, so it is worth
            // hammering rather than reasoning about.
            var rng = new DeterministicRandom(20260824);
            for (int seed = 0; seed < 40; seed++)
            {
                var sim = NewSim(DevBoards.Chain3(), FrozenTuning());
                for (int tick = 0; tick < 300; tick++)
                {
                    if (rng.NextFloat() < 0.06f)
                    {
                        Owner owner = rng.NextFloat() < 0.5f ? Owner.Player : Owner.Ai;
                        int dir = rng.NextFloat() < 0.5f ? 1 : -1;
                        float speed = rng.NextFloat() < 0.3f ? 10f : 4f;
                        sim.SpawnBeamForTest(0, owner, rng.Range(1f, 12f), speed, dir > 0 ? 0f : 1f, dir);
                    }
                    sim.Step();
                    Assert.True(CountContestsOnWire(sim, 0) <= 1,
                        "seed " + seed + ": two contests on one wire at tick " + sim.Tick);
                    AssertNoOpposingPairPassedThrough(sim);
                }
            }
        }

        private static int CountContestsOnWire(Simulation sim, int wireId)
        {
            int n = 0;
            foreach (Contest c in sim.Contests)
            {
                if (c.WireId == wireId) n++;
            }
            return n;
        }

        /// <summary>Two opposing beams on one wire must never end up ordered so that they have crossed.</summary>
        private static void AssertNoOpposingPairPassedThrough(Simulation sim)
        {
            foreach (Beam a in sim.Beams)
            {
                foreach (Beam b in sim.Beams)
                {
                    if (a.Id >= b.Id || a.WireId != b.WireId || a.Owner == b.Owner) continue;
                    // A pair that has crossed shows as: the one moving toward B
                    // is now PAST the one moving toward A.
                    Beam toB = a.Dir > 0 ? a : b;
                    Beam toA = a.Dir > 0 ? b : a;
                    if (toB.Dir != 1 || toA.Dir != -1) continue;
                    Assert.True(toB.T <= toA.T + 1e-4f,
                        "opposing beams passed through each other on wire " + a.WireId +
                        " (" + toB.T + " past " + toA.T + ")");
                }
            }
        }

        // ---- Merge keeps the faster beam's position ----

        [Fact]
        public void Merge_TakesFasterBeamsPositionWithItsSpeed()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(), FrozenTuning());
            Beam front = sim.SpawnBeamForTest(0, Owner.Player, 3f, 4f, 0.30f, 1);
            Beam rear = sim.SpawnBeamForTest(0, Owner.Player, 5f, 12f, 0.28f, 1);

            // Positions after one tick if they had not merged.
            float rearSolo = 0.28f + 12f / 4f / 60f;

            sim.Step();
            Assert.Single(sim.Beams);
            Beam merged = sim.Beams[0];
            Assert.Equal(front.Id, merged.Id);
            Assert.Equal(12f, merged.Speed);
            // The merged packet moves at the speed it was just given, so it ends
            // the tick where the fast beam would have been, not where the slow
            // one was.
            Assert.True(Math.Abs(merged.T - rearSolo) < 1e-5f,
                "merged T " + merged.T + " expected " + rearSolo);
        }

        // ---- Contest survivor pushed off the end arrives with a real tau ----

        [Fact]
        public void ContestSurvivor_ShovedOffTheEnd_ArrivesImmediately()
        {
            // A side dies in the same tick the front runs off the end. The
            // survivor is heading that way, so it arrives now rather than being
            // parked exactly on the boundary with a fabricated tau of zero.
            var sim = NewSim(DevBoards.Chain3(aiCharge: 0f), FrozenTuning());
            sim.SpawnContestForTest(1, 0.999f, 40f, 0.0002f, 1, 4f, 4f);

            sim.Step();
            Assert.Empty(sim.Contests);
            Assert.Empty(sim.Beams); // no beam parked on the boundary
            Assert.Equal(Owner.Player, sim.NodeById(2).Owner); // it landed and captured
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
