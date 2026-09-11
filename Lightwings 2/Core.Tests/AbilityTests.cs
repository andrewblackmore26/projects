using System;
using Lightship.Core.Config;
using Lightship.Core.Ships;
using Lightship.Core.Sim;
using Lightship.Core.Sim.Abilities;
using Xunit;

namespace Lightship.Core.Tests
{
    /// <summary>
    /// Spec 11.7 / M1 acceptance: every visible part is an ability, and a tester
    /// can point at each part and say what it does. One scenario per component
    /// of the M1 player forms, each a differential against a form without it.
    /// </summary>
    public class AbilityTests
    {
        private static Game Quiet(string seedShip, ulong seed = 1)
        {
            var game = new Game(new Tuning(), SimTestHelpers.Catalog(), seed, seedShip, new StaticPilot());
            game.Arena.SpawnEnemies = false;
            game.Arena.SpawnAmbientLight = false;
            return game;
        }

        private static StaticPilot PilotOf(Game g) => (StaticPilot)g.Arena.Player.Pilot;

        /// <summary>A fire enemy that never moves or shoots, at an offset from the player.</summary>
        private static Ship Dummy(Game g, float dx, float dy, float hp = 40f)
        {
            ShipDefinition fire = SimTestHelpers.Catalog().Find(Element.Fire, 1);
            Vec2 p = g.Arena.Player.Pos;
            Ship e = g.Arena.SpawnShip(fire, Faction.Enemy, new Vec2(p.X + dx, p.Y + dy), null, hp, 0f);
            e.Facing = new Vec2(0f, 1f);
            return e;
        }

        [Fact]
        public void SporeBudFiresInfectingShotsFromItsOwnPart()
        {
            Game g = Quiet("corruption_t1_glitch");
            Ship player = g.Arena.Player;
            PilotOf(g).Input = new PlayerInput { Fire = true, Aim = new Vec2(0f, -1f) };
            g.Step(default);
            int b = -1;
            for (int i = 0; i < g.Arena.Bullets.High; i++) if (g.Arena.Bullets.Alive[i]) b = i;
            Assert.True(b >= 0, "no shot");
            Assert.Equal(Sides.Player, g.Arena.Bullets.Side[b]);
            Assert.True((g.Arena.Bullets.Flags[b] & BulletFlags.Infect) != 0, "the spore bud's shot must infect");
            // It left from the spore bud (0, -12 in ship space), then flew one tick.
            Vec2 muzzle = player.ToWorld(new Vec2(0f, -12f));
            float flown = new Tuning().PlayerBulletSpeed / 60f;
            Assert.InRange(g.Arena.Bullets.X[b], muzzle.X - 0.01f, muzzle.X + 0.01f);
            Assert.InRange(g.Arena.Bullets.Y[b], muzzle.Y - flown - 0.01f, muzzle.Y - flown + 0.01f);
        }

        [Fact]
        public void InfectionDealsDamageOverTimeAfterTheHit()
        {
            Game g = Quiet("corruption_t1_glitch");
            Ship e = Dummy(g, 0f, -150f);
            PilotOf(g).Input = new PlayerInput { Fire = true, Aim = new Vec2(0f, -1f) };
            g.Step(default);
            PilotOf(g).Input = new PlayerInput { Aim = new Vec2(0f, -1f) };
            int hitTick = SimTestHelpers.StepUntil(g, x => e.Hp < 40f, 60);
            Assert.True(hitTick >= 0);
            Assert.True(e.Infected(g.Arena.Tick));
            SimTestHelpers.StepN(g, 200);
            // The shot's damage, then InfectDps for InfectDurationTicks.
            var t = new Tuning();
            float expected = 40f - t.PlayerBulletDamage - t.InfectDps * t.InfectDurationTicks / 60f;
            Assert.InRange(e.Hp, expected - 0.2f, expected + 0.2f);
            Assert.Equal(1, g.Events.Count(EventKind.Infected));
            Assert.False(e.Infected(g.Arena.Tick));
        }

        [Fact]
        public void InfectionKillCreditsThePlayer()
        {
            Game g = Quiet("corruption_t1_glitch");
            Ship e = Dummy(g, 0f, -150f, hp: 12f);   // 8 from the shot, the DoT finishes it
            PilotOf(g).Input = new PlayerInput { Fire = true, Aim = new Vec2(0f, -1f) };
            g.Step(default);
            PilotOf(g).Input = default;
            SimTestHelpers.StepN(g, 150);
            Assert.False(e.Alive);
            Assert.Equal(1, g.Run.EnemiesKilled);
            Assert.True(SimTestHelpers.SumPickupValues(g.Arena) > Rewards.DropEnergy(1) - 1f, "the DoT kill must drop energy");
        }

        [Theory]
        [InlineData("corruption_t2_worm", true)]
        [InlineData("corruption_t1_glitch", false)]
        public void NucleusSpreadsInfectionToTheNearestEnemy(string form, bool spreads)
        {
            Game g = Quiet(form);
            Ship a = Dummy(g, 0f, -150f, hp: 400f);
            Ship b = Dummy(g, 110f, -150f, hp: 400f);
            PilotOf(g).Input = new PlayerInput { Fire = true, Aim = new Vec2(0f, -1f) };
            g.Step(default);
            PilotOf(g).Input = default;
            SimTestHelpers.StepUntil(g, x => a.Infected(x.Arena.Tick), 60);
            SimTestHelpers.StepN(g, 70);
            Assert.Equal(spreads, b.Infected(g.Arena.Tick));
            Assert.Equal(spreads ? 1 : 0, g.Events.Count(EventKind.InfectSpread));
        }

        [Theory]
        [InlineData("corruption_t3_trojan", 2)]
        [InlineData("corruption_t2_worm", 0)]
        public void PodsHatchDronesThatRamEnemies(string form, int pods)
        {
            Game g = Quiet(form);
            Ship player = g.Arena.Player;
            Ship e = Dummy(g, 0f, -300f, hp: 400f);
            g.Step(default);
            g.Step(default);
            Assert.Equal(pods, g.Events.Count(EventKind.DroneHatched));
            if (pods == 0) return;

            // Each drone was born on its pod (+-26, 2 in ship space) and belongs to the player's side.
            int onPod = 0;
            foreach (Ship s in g.Arena.Ships)
            {
                if (!s.IsDrone) continue;
                Assert.Equal(Sides.Player, s.Side);
                Vec2 local = player.ToLocal(s.Pos);
                if (MathF.Abs(MathF.Abs(local.X) - 26f) < 6f) onPod++;
            }
            Assert.Equal(2, onPod);

            // They ram: the enemy takes ram damage and is infected (the trojan infects), and the drones are spent.
            SimTestHelpers.StepN(g, 90);
            Assert.True(e.Hp <= 400f - 2f * new Tuning().DroneRamDamage + 0.01f, "hp " + e.Hp);
            Assert.True(e.Infected(g.Arena.Tick) || g.Events.Count(EventKind.Infected) > 0);
            Assert.Equal(0, g.Arena.AliveDrones());
            // One drone per pod at a time, a fresh one after the hatch interval.
            SimTestHelpers.StepN(g, new Tuning().HatchIntervalTicks);
            Assert.Equal(4, g.Events.Count(EventKind.DroneHatched));
        }

        [Fact]
        public void EnemiesOfOneElementDoNotHurtEachOtherButOtherSidesDo()
        {
            Game g = Quiet("corruption_t1_glitch");
            Ship a = Dummy(g, 200f, 0f);
            Vec2 at = a.Pos;
            g.Arena.SpawnBullet(Faction.Enemy, Element.Fire, new Vec2(at.X - 30f, at.Y), new Vec2(300f, 0f), 3f, 8f, 60);
            SimTestHelpers.StepN(g, 20);
            Assert.Equal(40f, a.Hp, 3);
            // A corruption-side bullet (a corruption rival's, M2) hurts the fire enemy.
            g.Arena.SpawnBullet(Faction.Enemy, Element.Corruption, new Vec2(at.X - 30f, at.Y), new Vec2(300f, 0f), 3f, 8f, 60);
            SimTestHelpers.StepN(g, 20);
            Assert.Equal(32f, a.Hp, 3);
        }

        [Fact]
        public void BulletsBesideATriangleTipMissItsBody()
        {
            // The hit test is the drawn body: a bullet in the empty corner of the Ember's
            // bounding circle (beside its nose) passes; one on the hull hits.
            Game g = Quiet("corruption_t1_glitch");
            Ship e = Dummy(g, 0f, -200f);
            e.Facing = new Vec2(0f, -1f);
            Vec2 nose = e.ToWorld(new Vec2(9f, -10f));   // beside the body triangle's apex, inside its bounding circle
            Assert.False(Arena.HitsBody(e, nose, 1f));
            Assert.True(Arena.HitsBody(e, e.ToWorld(new Vec2(0f, 4f)), 1f));
        }

        [Fact]
        public void LoadoutsFollowTheForm()
        {
            var t = new Tuning();
            Loadout l1 = Loadout.Build(SimTestHelpers.Catalog().Get("corruption_t1_glitch"), t);
            Loadout l3 = Loadout.Build(SimTestHelpers.Catalog().Get("corruption_t3_trojan"), t);
            Assert.True(l1.Has("infect") && !l1.Has("spread") && !l1.Has("hatch"));
            Assert.True(l3.Has("infect") && l3.Has("spread") && l3.Has("hatch"));
            Assert.Equal(BulletFlags.Infect, l1.BulletFlags);
            Assert.Equal(BulletFlags.Infect | BulletFlags.Spreads, l3.BulletFlags);
            Assert.Equal(2, l3.Get<HatchAbility>().Mounts.Count);
        }

        [Fact]
        public void EvolvingRebuildsTheLoadout()
        {
            Game g = Quiet("corruption_t1_glitch");
            g.Run.OnAbsorb(Element.Corruption, 100f);
            g.Run.RecomputeOffer();
            g.Run.Evolve(0);
            Assert.True(g.Arena.Player.Loadout.Has("spread"));
        }
    }
}
