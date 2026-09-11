using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Xunit;

namespace Lightship.Core.Tests
{
    public class HealthEnergyTests
    {
        private static readonly Tuning T = new Tuning();

        [Theory]
        [InlineData(1, 100f)]
        [InlineData(2, 125f)]
        [InlineData(5, 200f)]
        public void MaxHpPerTier(int tier, float expected) => Assert.Equal(expected, Health.MaxHp(tier, T));

        [Fact]
        public void RegenStartsAfter3sAndIs10PercentPerSecond()
        {
            Assert.Equal(50f, Health.Regen(50f, 100f, 1000, 1000 - 179, T));
            float hp = 50f;
            for (int i = 0; i < 60; i++) hp = Health.Regen(hp, 100f, 1000 + i, 1000 - 180, T);
            Assert.Equal(60f, hp, 2);
            Assert.Equal(100f, Health.Regen(99.99f, 100f, 1000, 0, T), 3);
        }

        [Theory]
        [InlineData(99f, 1)]
        [InlineData(100f, 2)]
        [InlineData(300f, 3)]
        [InlineData(700f, 4)]
        [InlineData(1500f, 5)]
        [InlineData(5000f, 5)]
        public void TierFromThresholds(float energy, int tier) => Assert.Equal(tier, Rewards.TierForEnergy(energy, T));

        [Fact]
        public void RewardByGap()
        {
            Assert.Equal(2.25f, Rewards.Scale(3, 1, 1.5f), 4);
            Assert.Equal(1f, Rewards.Scale(1, 3, 1.5f), 4);
            Assert.Equal(1.5f, Rewards.Scale(2, 1, 1.5f), 4);
        }

        [Fact]
        public void EnergyKeepsAccruingWhileOfferWaits()
        {
            Game game = SimTestHelpers.QuietGame();
            Run run = game.Run;
            Assert.False(run.EvolveAvailable);
            run.OnAbsorb(Element.Corruption, 150f);
            run.RecomputeOffer();
            Assert.True(run.EvolveAvailable);
            Assert.Equal(1, run.Offer.Count);
            run.OnAbsorb(Element.Corruption, 10f);
            SimTestHelpers.StepN(game, 5);
            Assert.Equal(160f, run.Energy, 3);
            Assert.Equal(1, run.Tier);   // player-triggered, never automatic
        }

        [Fact]
        public void EvolveReshapesInvulnerablyAndAdds25Hp()
        {
            Game game = SimTestHelpers.QuietGame();
            Run run = game.Run;
            run.OnAbsorb(Element.Corruption, 100f);
            run.RecomputeOffer();
            run.Player.Hp = 60f;
            run.Player.LastDamageTick = game.Arena.Tick;   // recently hurt, so no regen muddies the +25
            ((StaticPilot)run.Player.Pilot).Input = new PlayerInput { Evolve = true, EvolveChoice = 0 };
            game.Step(default);
            long before = game.Arena.Tick;   // evolution starts on the tick the pilot asked for it
            Assert.Equal(2, run.Tier);
            Assert.Equal(Element.Corruption, run.Root);
            Assert.Equal("corruption_t2_worm_player", run.Ship.Id);
            Assert.Equal(2, run.Player.Def.Tier);
            Assert.Equal(125f, run.Player.MaxHp);
            Assert.Equal(85f, run.Player.Hp, 3);
            Assert.NotNull(run.Reshape);
            Assert.Equal(before + T.ReshapeTicks, run.Reshape.EndTick);
            Assert.True(run.Invulnerable);
            Assert.Equal(0f, run.Absorbed[(int)Element.Corruption]);
            Assert.Equal(100f, run.Energy, 3);   // energy is never spent
            Assert.Equal(1, game.Events.Count(EventKind.Evolved));
            Assert.Equal(300f, run.Threshold);

            ((StaticPilot)run.Player.Pilot).Input = default;
            SimTestHelpers.StepN(game, T.ReshapeTicks - 1);
            Assert.NotNull(run.Reshape);
            SimTestHelpers.StepN(game, 1);
            Assert.Null(run.Reshape);
            Assert.Equal(1, game.Events.Count(EventKind.ReshapeEnded));
            Assert.InRange(run.Zoom, 0.899f, 0.901f);
            Assert.InRange(run.PlayerCoreRadius, 3f / 0.9f - 0.01f, 3f / 0.9f + 0.01f);
        }

        [Fact]
        public void EvolveIgnoredBelowThreshold()
        {
            Game game = SimTestHelpers.QuietGame();
            game.Run.OnAbsorb(Element.Corruption, 99f);
            ((StaticPilot)game.Run.Player.Pilot).Input = new PlayerInput { Evolve = true };
            game.Step(default);
            Assert.Equal(1, game.Run.Tier);
            game.Run.OnAbsorb(Element.Corruption, 1f);
            game.Step(default);
            Assert.Equal(2, game.Run.Tier);   // the same held intent fires once the threshold is met
        }

        [Fact]
        public void HumanEvolveIntentReachesTheRun()
        {
            // The human path: input handed to Game.Step reaches the run through HumanPilot.
            var game = new Game(new Tuning(), SimTestHelpers.Catalog(), 1);
            game.Arena.SpawnEnemies = false;
            game.Run.OnAbsorb(Element.Corruption, 100f);
            game.Step(new PlayerInput { Evolve = true, EvolveChoice = 0 });
            Assert.Equal(2, game.Run.Tier);
        }

        [Fact]
        public void DamageResetsRegen()
        {
            Game game = SimTestHelpers.QuietGame();
            SimTestHelpers.StepN(game, 10);
            game.Arena.DamagePlayer(30f, game.Arena.Player.Pos);
            Assert.Equal(game.Arena.Tick, game.Arena.Player.LastDamageTick);
            SimTestHelpers.StepN(game, 179);
            Assert.Equal(70f, game.Arena.Player.Hp, 2);
            SimTestHelpers.StepN(game, 60);
            Assert.InRange(game.Arena.Player.Hp, 79.5f, 80.5f);
        }

        [Fact]
        public void DamageShedsNoLightByDefault()
        {
            Game game = SimTestHelpers.QuietGame();
            game.Run.OnAbsorb(Element.Corruption, 50f);
            game.Arena.DamagePlayer(20f, game.Arena.Player.Pos);
            Assert.Equal(50f, game.Run.Energy, 3);
            Assert.Equal(0, game.Arena.Pickups.Live);
        }

        [Fact]
        public void DamageShedsLightBeyondTheMagnetButNeverBelowTheTierFloor()
        {
            var t = new Tuning { DamageShedsLightFraction = 0.5f };
            Game game = SimTestHelpers.QuietGame(1, t);
            Run run = game.Run;
            run.OnAbsorb(Element.Corruption, 50f);
            game.Arena.DamagePlayer(20f, game.Arena.Player.Pos);
            Assert.Equal(40f, run.Energy, 3);
            Assert.Equal(10f, SimTestHelpers.SumPickupValues(game.Arena), 3);
            for (int i = 0; i < game.Arena.Pickups.High; i++)
                if (game.Arena.Pickups.Alive[i])
                    Assert.True(Vec2.Distance(new Vec2(game.Arena.Pickups.X[i], game.Arena.Pickups.Y[i]), game.Arena.Player.Pos) > run.MagnetRadius);

            // At tier 2 with 305 energy, the floor is 100: a huge hit sheds 205 and no more.
            run.OnAbsorb(Element.Corruption, 60f);
            run.RecomputeOffer();
            run.Evolve(0);
            run.OnAbsorb(Element.Corruption, 205f);   // 305
            game.Arena.Player.Hp = 10000f;
            game.Arena.DamagePlayer(1000f, game.Arena.Player.Pos);
            Assert.Equal(100f, run.Energy, 3);
            Assert.Equal(2, run.Tier);
        }

        [Fact]
        public void DeathResetsTheRunAndKeepsMeta()
        {
            Game game = SimTestHelpers.QuietGame();
            game.Run.OnAbsorb(Element.Corruption, 250f);
            game.Arena.DamagePlayer(1000f, game.Arena.Player.Pos);
            Run old = game.Run;
            game.Step(default);
            Assert.NotSame(old, game.Run);
            Assert.Equal(0f, game.Run.Energy);
            Assert.Equal(1, game.Run.Tier);
            Assert.Equal(1, game.Meta.Deaths);
            Assert.Equal(1, game.Events.Count(EventKind.PlayerDied));
            Assert.True(game.Run.Player.Alive);
        }
    }
}
