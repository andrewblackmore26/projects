using System;
using Gridlock.Core;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;
using Xunit;
using static Gridlock.Core.Tests.TestHelpers;

namespace Gridlock.Core.Tests
{
    public class CaptureAndWinTests
    {
        [Fact]
        public void Capture_StrictlyGreaterOnly_EqualityChipsToZero()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(aiCharge: 12f), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 12f, 4f, 0.99f, 1); // power == defense exactly
            sim.Step();
            GameNode target = sim.NodeById(1);
            Assert.Equal(Owner.Ai, target.Owner); // NOT captured (spec: strictly >)
            Assert.Equal(0f, target.Charge);      // chipped to exactly zero
        }

        [Fact]
        public void Capture_ChargeIsPowerMinusDefense_AndLocks()
        {
            // Middle node made ai-owned so this capture does NOT end the match
            // (a finished match freezes all timers, including the lock).
            LevelData level = DevBoards.Chain3();
            level.Nodes[1].Owner = "ai";
            level.Nodes[1].Charge = 12f;
            var sim = NewSim(level, FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 13f, 4f, 0.99f, 1);
            sim.Step();
            GameNode target = sim.NodeById(1);
            Assert.Equal(Owner.Player, target.Owner);
            Assert.Equal(1f, target.Charge);
            Assert.Equal(NodeState.CaptureLocked, target.State);

            // Lock blocks a hold, then expires after exactly CAPTURE_LOCK_TICKS.
            sim.EnqueueBeginHold(Owner.Player, 1);
            sim.Step();
            Assert.Equal(NodeState.CaptureLocked, target.State);
            StepN(sim, 29);
            Assert.Equal(NodeState.Idle, target.State);
        }

        [Fact]
        public void Neutral_DefenseChips_AndNeverRegenerates()
        {
            var sim = NewSim(DevBoards.Chain3(), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 10f, 4f, 0.99f, 1);
            sim.Step();
            GameNode mid = sim.NodeById(1);
            Assert.Equal(Owner.Neutral, mid.Owner);
            Assert.Equal(6f, mid.NeutralDefense); // 16 − 10

            StepN(sim, 600); // ten seconds later: still 6 (no regeneration)
            Assert.Equal(6f, mid.NeutralDefense);

            sim.SpawnBeamForTest(0, Owner.Player, 6.5f, 4f, 0.99f, 1);
            sim.Step();
            Assert.Equal(Owner.Player, mid.Owner); // 6.5 > 6: the chipped hub falls
            Assert.True(Math.Abs(mid.Charge - 0.5f) < 1e-4f);
        }

        [Fact]
        public void Deposit_CappedOverflowLost()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), FrozenTuning());
            sim.SpawnBeamForTest(0, Owner.Player, 9f, 4f, 0.01f, -1); // toward own node 0
            sim.Step();
            Assert.Equal(12f, sim.NodeById(0).Charge); // 10 + 9 capped at 12 (degree 1)
        }

        [Fact]
        public void Deposit_ToDisabledFriendlyNode_Allowed_RaisesDefense()
        {
            var sim = NewSim(DevBoards.Chain3(playerCharge: 10f), FrozenTuning());
            // Burst empties node 0 and disables it.
            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();
            StepN(sim, 83);
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            sim.Step();
            Assert.Equal(NodeState.Disabled, sim.NodeById(0).State);
            Assert.Equal(0f, sim.NodeById(0).Charge);

            // Garrisoning the dark node: a friendly deposit lands and raises its
            // (frozen-at-charge) defense — the intended counterplay to the gamble.
            sim.SpawnBeamForTest(0, Owner.Player, 5f, 4f, 0.01f, -1);
            sim.Step();
            Assert.Equal(NodeState.Disabled, sim.NodeById(0).State);
            Assert.Equal(5f, sim.NodeById(0).Charge);
        }

        [Fact]
        public void Disabled_ZeroDefense_CapturedByAnyPower_LockReplacesDisable()
        {
            var sim = NewSim(DevBoards.Chain3(playerCharge: 10f), FrozenTuning());
            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();
            StepN(sim, 83);
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            sim.Step(); // burst: node 0 dark at charge 0

            sim.SpawnBeamForTest(0, Owner.Ai, 0.5f, 4f, 0.01f, -1); // tiny ai beam, arrives this tick
            sim.Step();
            GameNode node = sim.NodeById(0);
            Assert.Equal(Owner.Ai, node.Owner);          // 0.5 > 0: captured
            Assert.Equal(NodeState.CaptureLocked, node.State); // lock replaces disable
            Assert.True(Math.Abs(node.Charge - 0.5f) < 1e-5f);
        }

        [Fact]
        public void Capture_CancelsHoldInProgress()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), FrozenTuning());
            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();
            StepN(sim, 20);
            Assert.Equal(NodeState.Overcharging, sim.NodeById(0).State);

            sim.SpawnBeamForTest(0, Owner.Ai, 25f, 4f, 0.01f, -1);
            sim.Step();
            GameNode node = sim.NodeById(0);
            Assert.Equal(Owner.Ai, node.Owner);
            Assert.Equal(NodeState.CaptureLocked, node.State);
            Assert.Equal(-1, (int)node.HoldStartTick); // hold gone

            // The stale release from the old owner is dropped harmlessly.
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            sim.Step();
            Assert.Equal(Owner.Ai, node.Owner);
            Assert.Empty(sim.Beams);
        }

        [Fact]
        public void Win_InFlightBeamPostponesLoss_ChipFailureEndsIt()
        {
            // Chain3, two separate wires: the ai captures the player's home while
            // a too-small player beam is still flying at the far ai node. The
            // in-flight beam postpones the loss (spec §5.8); its failed chip ends it.
            var sim = NewSim(DevBoards.Chain3(aiCharge: 12f), FrozenTuning());
            sim.SpawnBeamForTest(1, Owner.Player, 5f, 4f, 0.5f, 1);  // wire 1 → ai node, will only chip
            sim.SpawnBeamForTest(0, Owner.Ai, 25f, 4f, 0.1f, -1);    // wire 0 → player home, captures

            int t = StepUntil(sim, s => s.NodeById(0).Owner == Owner.Ai, 60);
            Assert.True(t >= 0, "home never fell");
            Assert.Equal(MatchResult.None, sim.Result); // beam in flight keeps the player alive

            int t2 = StepUntil(sim, s => s.Result != MatchResult.None, 120);
            Assert.True(t2 >= 0, "match never ended");
            Assert.Equal(MatchResult.AiWin, sim.Result);
            Assert.Equal(12f - 5f, sim.NodeById(2).Charge); // the chip landed before the end
        }

        [Fact]
        public void Win_ContestSideCountsAsAlive()
        {
            // The player's last node falls, but player power still lives inside a
            // contest — no loss until that side burns out.
            var sim = NewSim(DevBoards.Chain3(aiCharge: 12f), FrozenTuning());
            sim.SpawnContestForTest(1, 0.5f, 0.001f, 0.001f, 1, 4f, 4f);
            sim.SpawnBeamForTest(0, Owner.Ai, 25f, 4f, 0.1f, -1);

            int t = StepUntil(sim, s => s.NodeById(0).Owner == Owner.Ai, 60);
            Assert.True(t >= 0);
            Assert.Equal(MatchResult.None, sim.Result); // contest side keeps the player in

            int t2 = StepUntil(sim, s => s.Result != MatchResult.None, 1000);
            Assert.True(t2 >= 0, "match never ended");
            Assert.Equal(MatchResult.AiWin, sim.Result);
            Assert.Equal(1, sim.ContestMutualDeaths);
        }

        [Fact]
        public void Objective_Survive_WinsAtDeadlineWithANode()
        {
            LevelData level = DevBoards.TwoNodeStrip(playerCharge: 5f);
            level.Objective = ObjectiveType.Survive;
            level.ObjectiveSeconds = 1f;
            var sim = NewSim(level, FrozenTuning());
            StepN(sim, 59);
            Assert.Equal(MatchResult.None, sim.Result);
            sim.Step();
            Assert.Equal(MatchResult.PlayerWin, sim.Result);
        }

        [Fact]
        public void Objective_Capture_AllListedNodesSimultaneously()
        {
            LevelData level = DevBoards.Chain3(playerCharge: 0f);
            level.Objective = ObjectiveType.Capture;
            level.ObjectiveNodeIds.Add(1);
            var sim = NewSim(level, FrozenTuning());
            Assert.Equal(MatchResult.None, sim.Result);
            sim.SpawnBeamForTest(0, Owner.Player, 20f, 4f, 0.99f, 1); // takes the 16-defense mid
            sim.Step();
            Assert.Equal(Owner.Player, sim.NodeById(1).Owner);
            Assert.Equal(MatchResult.PlayerWin, sim.Result);
        }

        // Note: MatchResult.Draw is unreachable in Eliminate under these rules —
        // captures TRANSFER ownership, so the union of owned nodes never shrinks
        // and at least one side always owns a node. The Draw branch stays as
        // defensive plumbing only.
    }
}
