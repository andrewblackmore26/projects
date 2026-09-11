using System;
using System.Collections.Generic;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Xunit;

namespace Lightship.Core.Tests
{
    public class BulletHashTests
    {
        [Fact]
        public void HashQueryEqualsBruteForce()
        {
            var rng = new DeterministicRandom(5);
            var pool = new BulletPool(4096);
            float w = 2400f, h = 1350f;
            for (int i = 0; i < 2000; i++)
                pool.Spawn(Faction.Enemy, Element.Fire, BulletShape.Triangle, rng.Range(-30f, w + 30f), rng.Range(-30f, h + 30f), 0f, 0f, 3f, 1f, 100, 0);
            // Free a few so the free list is exercised.
            for (int i = 0; i < 2000; i += 7) pool.Free(i);
            var hash = new SpatialHash(w, h, 64f, 4096);
            hash.Rebuild(pool);

            var found = new List<int>();
            for (int q = 0; q < 200; q++)
            {
                float x = rng.Range(-50f, w + 50f), y = rng.Range(-50f, h + 50f), r = rng.Range(5f, 150f);
                hash.Query(x, y, r, found);
                var set = new HashSet<int>(found);
                for (int i = 0; i < pool.High; i++)
                {
                    if (!pool.Alive[i]) continue;
                    float dx = pool.X[i] - x, dy = pool.Y[i] - y;
                    if (dx * dx + dy * dy <= r * r) Assert.Contains(i, set);
                }
                foreach (int i in found) Assert.True(pool.Alive[i]);
                Assert.True(found.Count <= pool.Live);
            }
        }

        [Fact]
        public void PoolReusesFreedSlotsAndCountsLive()
        {
            var pool = new BulletPool(8);
            var ids = new List<int>();
            for (int i = 0; i < 8; i++) ids.Add(pool.Spawn(Faction.Player, Element.None, BulletShape.Circle, 0, 0, 0, 0, 1, 1, 10, 0));
            Assert.Equal(-1, pool.Spawn(Faction.Player, Element.None, BulletShape.Circle, 0, 0, 0, 0, 1, 1, 10, 0));
            Assert.Equal(8, pool.Live);
            pool.Free(3);
            pool.Free(3);   // double free is harmless
            Assert.Equal(7, pool.Live);
            Assert.Equal(3, pool.Spawn(Faction.Player, Element.None, BulletShape.Circle, 0, 0, 0, 0, 1, 1, 10, 0));
            Assert.Equal(8, pool.High);
        }

        [Fact]
        public void CoreHitDamagesOnceAndFreesBullet()
        {
            Game game = SimTestHelpers.QuietGame();
            Arena a = game.Arena;
            Vec2 p = a.Player.Pos;
            int b = a.SpawnBullet(Faction.Enemy, Element.Fire, new Vec2(p.X - 60f, p.Y), new Vec2(300f, 0f), 3f, 8f, 120);
            int ticks = SimTestHelpers.StepUntil(game, g => !g.Arena.Bullets.Alive[b], 60);
            Assert.True(ticks > 0, "bullet never reached the core");
            Assert.Equal(92f, a.Player.Hp, 3);
            Assert.Equal(1, game.Events.Count(EventKind.PlayerDamaged));
            SimTestHelpers.StepN(game, 30);
            Assert.True(a.Player.Hp >= 92f);   // hit once, never twice
        }

        [Fact]
        public void BulletsGrazingTheBodyDoNotHurtThePlayer()
        {
            // The hitbox is the core only (spec 9): a bullet passing 12 units off centre crosses the
            // blob's body but not the 3 px core, so HP is untouched.
            Game game = SimTestHelpers.QuietGame();
            Arena a = game.Arena;
            Vec2 p = a.Player.Pos;
            a.SpawnBullet(Faction.Enemy, Element.Fire, new Vec2(p.X - 60f, p.Y + 12f), new Vec2(300f, 0f), 3f, 8f, 120);
            SimTestHelpers.StepN(game, 40);
            Assert.Equal(100f, a.Player.Hp, 3);
        }

        [Fact]
        public void InvulnerableDuringReshape()
        {
            Game game = SimTestHelpers.QuietGame();
            Arena a = game.Arena;
            game.Run.Reshape = new ReshapeState { From = game.Run.Ship, To = game.Run.Ship, StartTick = a.Tick, EndTick = a.Tick + 1000 };
            Vec2 p = a.Player.Pos;
            int b = a.SpawnBullet(Faction.Enemy, Element.Fire, new Vec2(p.X - 60f, p.Y), new Vec2(300f, 0f), 3f, 8f, 120);
            SimTestHelpers.StepUntil(game, g => !g.Arena.Bullets.Alive[b], 60);
            Assert.Equal(100f, a.Player.Hp, 3);
            Assert.Equal(0, game.Events.Count(EventKind.PlayerDamaged));
        }

        [Fact]
        public void TtlExpiresAndArenaEdgeFrees()
        {
            Game game = SimTestHelpers.QuietGame();
            Arena a = game.Arena;
            int b = a.SpawnBullet(Faction.Enemy, Element.Fire, new Vec2(100f, 100f), Vec2.Zero, 3f, 1f, 10);
            int e = a.SpawnBullet(Faction.Enemy, Element.Fire, new Vec2(10f, 100f), new Vec2(-3000f, 0f), 3f, 1f, 1000);
            SimTestHelpers.StepN(game, 9);
            Assert.True(a.Bullets.Alive[b]);
            Assert.False(a.Bullets.Alive[e]);
            SimTestHelpers.StepN(game, 1);
            Assert.False(a.Bullets.Alive[b]);
        }

        [Fact]
        public void EnemyBodyContactDamagesCore()
        {
            Game game = SimTestHelpers.QuietGame();
            Arena a = game.Arena;
            ShipDefinition fire = SimTestHelpers.Catalog().Find(Element.Fire, 1);
            Ship e = a.SpawnShip(fire, Faction.Enemy, a.Player.Pos, null, 1000f, 0f);
            SimTestHelpers.StepN(game, 60);
            Assert.InRange(a.Player.Hp, 100f - 15f - 0.5f, 100f - 15f + 0.5f);
            Assert.True(e.Alive);
        }

        [Fact]
        public void PlayerBulletHitsEnemyBodyAndShedsLight()
        {
            Game game = SimTestHelpers.QuietGame();
            Arena a = game.Arena;
            ShipDefinition fire = SimTestHelpers.Catalog().Find(Element.Fire, 1);
            Vec2 p = a.Player.Pos;
            Ship e = a.SpawnShip(fire, Faction.Enemy, new Vec2(p.X + 120f, p.Y), null, 40f, 0f);
            e.Facing = new Vec2(-1f, 0f);
            int b = a.SpawnBullet(Faction.Player, Element.None, new Vec2(p.X + 60f, p.Y), new Vec2(300f, 0f), 2.5f, 10f, 120);
            int ticks = SimTestHelpers.StepUntil(game, g => !g.Arena.Bullets.Alive[b], 60);
            Assert.True(ticks > 0);
            Assert.Equal(30f, e.Hp, 3);
            Assert.Equal(1, game.Events.Count(EventKind.Hit));
            Assert.Equal(1, a.Pickups.Live);
            Assert.Equal((byte)Element.Fire, a.Pickups.Elem[0]);
        }

        [Fact]
        public void KillDropsLightScaledByTierGap()
        {
            Game game = SimTestHelpers.QuietGame();
            Arena a = game.Arena;
            ShipDefinition fire = SimTestHelpers.Catalog().Find(Element.Fire, 1);
            Ship e = a.SpawnShip(fire, Faction.Enemy, new Vec2(400f, 400f), null, 40f, 0f);
            e.Tier = 3;   // two tiers above the tier-1 player: x1.5^2
            a.DamageEnemy(e, 1000f, e.Pos);
            Assert.False(e.Alive);
            Assert.Equal(1, game.Events.Count(EventKind.Kill));
            float expected = MathF.Round(Rewards.DropEnergy(3) * 2.25f) + 1f;   // drops plus the one shed light
            Assert.Equal(expected, SimTestHelpers.SumPickupValues(a), 3);
            Assert.Equal(1, game.Run.EnemiesKilled);
        }

        [Fact]
        public void MagnetPullsAndCoreAbsorbs()
        {
            Game game = SimTestHelpers.QuietGame();
            Arena a = game.Arena;
            Vec2 p = a.Player.Pos;
            a.SpawnPickup(Element.Fire, 1, new Vec2(p.X + 50f, p.Y), false);     // inside the tier-1 magnet (60)
            a.SpawnPickup(Element.Fire, 2, new Vec2(p.X + 400f, p.Y), false);    // far outside: drifts only
            SimTestHelpers.StepN(game, 30);
            Assert.Equal(5f, game.Run.Energy, 3);
            Assert.Equal(5f, game.Run.Absorbed[(int)Element.Fire], 3);
            Assert.Equal(1, a.Pickups.Live);
            Assert.Equal(1, game.Events.Count(EventKind.Absorb));
        }
    }
}
