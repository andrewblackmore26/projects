using Gridlock.Core;
using Gridlock.Core.Config;
using Gridlock.Core.Levels;
using Xunit;
using static Gridlock.Core.Tests.TestHelpers;

namespace Gridlock.Core.Tests
{
    public class ChargeAndSendTests
    {
        [Fact]
        public void Charge_AccrualPerDegree_CapAtMax()
        {
            var sim = NewSim(DevBoards.Chain3()); // accrual ON (default tuning)
            GameNode player = sim.NodeById(0);    // degree 1
            StepN(sim, 60);
            Assert.True(System.Math.Abs(player.Charge - 1.2f) < 1e-3f,
                "after 1s expected 1.2, got " + player.Charge);
            StepN(sim, 60 * 60); // long past the cap
            Assert.Equal(12f, player.Charge); // MAX_CHARGE_PER_DEGREE × 1
        }

        [Fact]
        public void Charge_NeutralDoesNotAccrue()
        {
            var sim = NewSim(DevBoards.Chain3());
            StepN(sim, 120);
            Assert.Equal(0f, sim.NodeById(1).Charge);
            Assert.Equal(16f, sim.NodeById(1).NeutralDefense); // untouched
        }

        [Fact]
        public void Intents_OneTickLatency_Contract()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), FrozenTuning());
            sim.EnqueueBeginHold(Owner.Player, 0);
            Assert.Equal(NodeState.Idle, sim.NodeById(0).State); // not yet drained
            sim.Step();
            Assert.Equal(NodeState.Overcharging, sim.NodeById(0).State);
        }

        [Fact]
        public void Hold_BeginRequiresOwnedIdleAndMinCharge()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 1f), FrozenTuning());
            sim.EnqueueBeginHold(Owner.Player, 0); // below MIN_SEND_CHARGE (2)
            sim.Step();
            Assert.Equal(NodeState.Idle, sim.NodeById(0).State);

            sim.EnqueueBeginHold(Owner.Player, 1); // not our node
            sim.Step();
            Assert.Equal(NodeState.Idle, sim.NodeById(1).State);

            sim.EnqueueBeginHold(Owner.Ai, 1); // ai holds its own node: fine
            sim.Step();
            Assert.Equal(NodeState.Idle, sim.NodeById(1).State); // ...but ai node has charge 0 < min
        }

        [Fact]
        public void Send_InstantTap_SendsMinFraction()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), FrozenTuning());
            float spawnedPower = -1f;
            sim.BeamSpawned += (id, wireId, owner, power, dir) => spawnedPower = power;

            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.EnqueueReleaseSend(Owner.Player, 0, 0); // same drain: holdTicks == 0
            sim.Step();

            Assert.True(System.Math.Abs(spawnedPower - 3.5f) < 1e-5f, "got " + spawnedPower);
            Assert.True(System.Math.Abs(sim.NodeById(0).Charge - 6.5f) < 1e-5f);
            Assert.Equal(NodeState.Idle, sim.NodeById(0).State);
            Assert.Single(sim.Beams);
            Assert.Equal(1, sim.Beams[0].Dir); // node 0 is wire end A
            Assert.Equal(0f, sim.Beams[0].PrevT);
        }

        [Fact]
        public void Send_ReleaseAtTick83_IsMaxNonBurst()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), FrozenTuning());
            float spawnedPower = -1f;
            sim.BeamSpawned += (id, wireId, owner, power, dir) => spawnedPower = power;

            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();                    // hold starts (HoldStartTick = 0)
            StepN(sim, 82);                // tick now 83
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            sim.Step();                    // drained at tick 83 → holdTicks = 83

            float expected = 10f * (0.35f + 0.65f * (83f / 84f));
            Assert.True(System.Math.Abs(spawnedPower - expected) < 1e-4f,
                "expected " + expected + ", got " + spawnedPower);
            Assert.Equal(NodeState.Idle, sim.NodeById(0).State); // no burst at 83
            Assert.Equal(4f, sim.Beams[0].Speed); // base speed, not burst
        }

        [Fact]
        public void Send_ReleaseAtTick84_IsBurst()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), FrozenTuning());
            float spawnedPower = -1f;
            bool disabledFired = false;
            sim.BeamSpawned += (id, wireId, owner, power, dir) => spawnedPower = power;
            sim.NodeDisabled += id => disabledFired = true;

            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();
            StepN(sim, 83);
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            sim.Step();                    // holdTicks = 84 == OverchargeTicks → burst

            Assert.Equal(10f, spawnedPower);            // sends EVERYTHING
            Assert.Equal(0f, sim.NodeById(0).Charge);
            Assert.Equal(10f, sim.Beams[0].Speed);      // 4 × 2.5
            Assert.Equal(NodeState.Disabled, sim.NodeById(0).State);
            Assert.True(disabledFired);
        }

        [Fact]
        public void Burst_DisabledLastsExactly300Ticks_NoAccrualDuring()
        {
            // Chain3: the burst beam lands on the 16-defense neutral and only chips,
            // so the match keeps running while we watch the disable window.
            var tuning = new Tuning(); // accrual ON to verify the pause
            var sim = NewSim(DevBoards.Chain3(playerCharge: 10f), tuning);
            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();
            StepN(sim, 83);
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            sim.Step(); // burst executed at tick 84 → DisabledUntil = 84 + 300

            StepN(sim, 299);
            Assert.Equal(NodeState.Disabled, sim.NodeById(0).State);
            Assert.Equal(0f, sim.NodeById(0).Charge); // no accrual while dark

            sim.Step(); // tick 384: expiry fires before accrual, then one accrual lands
            Assert.Equal(NodeState.Idle, sim.NodeById(0).State);
            Assert.True(System.Math.Abs(sim.NodeById(0).Charge - 0.02f) < 1e-5f,
                "exactly one accrual tick expected, got " + sim.NodeById(0).Charge);
        }

        [Fact]
        public void Cancel_RestoresIdle_CostsNothing()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), FrozenTuning());
            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();
            StepN(sim, 40);
            sim.EnqueueCancelHold(Owner.Player, 0);
            sim.Step();
            Assert.Equal(NodeState.Idle, sim.NodeById(0).State);
            Assert.Equal(10f, sim.NodeById(0).Charge);
            Assert.Empty(sim.Beams);
        }

        [Fact]
        public void Send_OverchargeProgress_DrivesVisibleBrightness()
        {
            var sim = NewSim(DevBoards.TwoNodeStrip(playerCharge: 10f), FrozenTuning());
            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.Step();     // hold starts at tick 0; sim.Tick is now 1
            StepN(sim, 41); // sim.Tick = 42 → holdTicks = 42, half of 84
            float progress = sim.NodeById(0).OverchargeProgress(sim.Tick, sim.Tuning);
            Assert.True(System.Math.Abs(progress - 0.5f) < 1e-4f, "got " + progress);
        }

        [Fact]
        public void Objective_Efficiency_SendBeyondBudgetRejected()
        {
            LevelData level = DevBoards.TwoNodeStrip(playerCharge: 10f);
            level.Objective = ObjectiveType.Efficiency;
            level.ObjectiveMaxSends = 1;
            var sim = NewSim(level, FrozenTuning());

            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            sim.Step();
            Assert.Single(sim.Beams); // first send fine

            sim.EnqueueBeginHold(Owner.Player, 0);
            sim.EnqueueReleaseSend(Owner.Player, 0, 0);
            sim.Step();
            Assert.Single(sim.Beams); // second rejected: budget spent
            Assert.Equal(1, sim.PlayerSends);
            Assert.Equal(NodeState.Idle, sim.NodeById(0).State); // degraded to a free cancel
        }
    }
}
