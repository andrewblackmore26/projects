using System;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Lightship.Core.Sim.Patterns;
using Xunit;

namespace Lightship.Core.Tests
{
    public class PatternTests
    {
        private static Ship SpawnFlameEnemy(Game game, float distance, float rangeOverride = -1f)
        {
            Arena a = game.Arena;
            ShipDefinition fire = SimTestHelpers.Catalog().Find(Element.Fire, 1);
            Vec2 p = a.Player.Pos;
            Ship e = a.SpawnShip(fire, Faction.Enemy, new Vec2(p.X + distance, p.Y), new StaticPilot { Input = new PlayerInput { Fire = true }, AimAtPlayer = true }, 40f, 0f);
            PatternDefinition def = PatternLibrary.FlameSpray();
            if (rangeOverride > 0f) def.Range = rangeOverride;
            e.Pattern = new PatternRunner(def, a.Tick);
            return e;
        }

        [Fact]
        public void FlameSprayCadenceAndSpread()
        {
            // Fired from beyond its reach (range overridden) so no bullet lands and the counts are pure cadence.
            Game game = SimTestHelpers.QuietGame();
            Arena a = game.Arena;
            Ship e = SpawnFlameEnemy(game, 300f, 400f);

            SimTestHelpers.StepN(game, 29);
            Assert.Equal(0, a.Bullets.Live);
            SimTestHelpers.StepN(game, 1);           // tick 30: first burst
            Assert.Equal(5, a.Bullets.Live);

            // Spread: five bullets across 30 degrees about the direction to the player.
            Vec2 aim = (a.Player.Pos - e.Pos).Normalized();
            float maxDeg = 0f, minDeg = 999f;
            for (int i = 0; i < a.Bullets.High; i++)
            {
                if (!a.Bullets.Alive[i]) continue;
                var v = new Vec2(a.Bullets.VX[i], a.Bullets.VY[i]);
                Assert.InRange(v.Length(), 219.9f, 220.1f);
                float deg = MathF.Abs(MathF.Atan2(Vec2.Cross(aim, v.Normalized()), Vec2.Dot(aim, v.Normalized()))) * 180f / MathF.PI;
                maxDeg = MathF.Max(maxDeg, deg);
                minDeg = MathF.Min(minDeg, deg);
                Assert.Equal((byte)BulletShape.Triangle, a.Bullets.Shape[i]);
            }
            Assert.InRange(maxDeg, 14.9f, 15.1f);
            Assert.InRange(minDeg, 0f, 0.1f);

            SimTestHelpers.StepN(game, 20);          // tick 50: second burst
            Assert.Equal(10, a.Bullets.Live);
            SimTestHelpers.StepN(game, 20);          // tick 70: third burst
            Assert.Equal(15, a.Bullets.Live);
            SimTestHelpers.StepN(game, 2);           // tick 72: the first burst expires (ttl 42)
            Assert.Equal(10, a.Bullets.Live);
            SimTestHelpers.StepN(game, 40);          // tick 112: all expired, still in the pause
            Assert.Equal(0, a.Bullets.Live);
            SimTestHelpers.StepN(game, 29);          // tick 141
            Assert.Equal(0, a.Bullets.Live);
            SimTestHelpers.StepN(game, 1);           // tick 142: pause of 72 over, next burst
            Assert.Equal(5, a.Bullets.Live);
        }

        [Fact]
        public void EveryPatternCanReachItsPreferredRange()
        {
            foreach (PatternDefinition p in new[] { PatternLibrary.FlameSpray() })
            {
                Assert.True(p.PreferredRange < p.Reach, p.Id + ": holds " + p.PreferredRange + " but reaches " + p.Reach);
                Assert.True(p.Range <= p.Reach + 20f, p.Id + ": fires from " + p.Range + " but reaches " + p.Reach);
            }
        }

        [Fact]
        public void PatternHoldsFireOutOfRange()
        {
            Game game = SimTestHelpers.QuietGame();
            SpawnFlameEnemy(game, 600f);
            SimTestHelpers.StepN(game, 200);
            Assert.Equal(0, game.Arena.Bullets.Live);
        }

        [Fact]
        public void FlameSprayLandsOnAStationaryCoreFromItsPreferredRange()
        {
            Game game = SimTestHelpers.QuietGame();
            SpawnFlameEnemy(game, PatternLibrary.FlameSpray().PreferredRange);
            SimTestHelpers.StepN(game, 120);
            Assert.True(game.Events.Count(EventKind.PlayerDamaged) >= 1, "a cone from the preferred range must be able to hit");
        }

        [Fact]
        public void PlayerFiresAtItsCadenceWhileHeld()
        {
            Game game = SimTestHelpers.QuietGame();
            var pilot = (StaticPilot)game.Arena.Player.Pilot;
            pilot.Input = new PlayerInput { Fire = true, Aim = new Vec2(1f, 0f) };
            SimTestHelpers.StepN(game, 60);
            // 15-tick interval: shots at ticks 1, 16, 31, 46 -> 4 in the first second, ttl 72 keeps them alive.
            Assert.Equal(4, game.Arena.Bullets.Live);
            for (int i = 0; i < game.Arena.Bullets.High; i++)
                if (game.Arena.Bullets.Alive[i]) Assert.Equal((byte)Faction.Player, game.Arena.Bullets.Owner[i]);
        }
    }
}
