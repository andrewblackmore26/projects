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

        // ---- M2: fire T2 and T3 (spec 12) ----

        private static int LiveBullets(Game g, Func<int, bool> match)
        {
            int n = 0;
            BulletPool b = g.Arena.Bullets;
            for (int i = 0; i < b.High; i++) if (b.Alive[i] && match(i)) n++;
            return n;
        }

        /// <summary>Flare's tail vents drop burning embers behind it while it moves, and only then; an enemy flying through burns.</summary>
        [Fact]
        public void TailVentsLeaveABurningTrailOnlyWhileMoving()
        {
            Game g = Quiet("fire_t2_flare");
            Tuning t = g.T;
            Ship player = g.Arena.Player;
            Assert.True(player.Loadout.Has("burning_trail"));
            SimTestHelpers.StepN(g, 60);
            Assert.Equal(0, LiveBullets(g, i => g.Arena.Bullets.OwnerId[i] == player.Id));

            PilotOf(g).Input = new PlayerInput { Move = new Vec2(1f, 0f), Aim = new Vec2(1f, 0f) };
            SimTestHelpers.StepN(g, 30);
            int embers = LiveBullets(g, i => g.Arena.Bullets.OwnerId[i] == player.Id && g.Arena.Bullets.Damage[i] == t.TrailDamage);
            // Two vents, one ember each every TrailIntervalTicks.
            Assert.InRange(embers, 2 * (30 / t.TrailIntervalTicks) - 2, 2 * (30 / t.TrailIntervalTicks) + 2);
            // They are behind the ship (it flies east, facing east).
            BulletPool b = g.Arena.Bullets;
            for (int i = 0; i < b.High; i++)
                if (b.Alive[i] && b.OwnerId[i] == player.Id) Assert.True(b.X[i] < player.Pos.X, "an ember ahead of the ship");

            // An enemy parked on the path takes the trail's damage.
            Ship e = Dummy(g, -40f, 0f, 1000f);
            PilotOf(g).Input = new PlayerInput { Move = new Vec2(-1f, 0f), Aim = new Vec2(-1f, 0f) };
            SimTestHelpers.StepN(g, 20);
            PilotOf(g).Input = new PlayerInput { Move = new Vec2(1f, 0f), Aim = new Vec2(1f, 0f) };
            SimTestHelpers.StepN(g, 60);
            Assert.True(e.Hp < 1000f, "the trail never burned the enemy on its path");
        }

        /// <summary>Scorch's crown embers each fire a spray: three overlapping cones, the flanks turned out by WideConeAngleDeg.</summary>
        [Fact]
        public void ScorchFiresThreeOverlappingSprays()
        {
            Game g = Quiet("fire_t3_scorch");
            Tuning t = g.T;
            Ship player = g.Arena.Player;
            Weapon w = player.Loadout.Primary;
            Assert.Equal(3, w.Barrels.Count);
            Assert.Equal(0f, w.Barrels[0].AngleDeg);
            Assert.Contains(w.Barrels, b => b.AngleDeg == -t.WideConeAngleDeg && b.Mount.X < 0f);
            Assert.Contains(w.Barrels, b => b.AngleDeg == t.WideConeAngleDeg && b.Mount.X > 0f);

            PilotOf(g).Input = new PlayerInput { Fire = true, Aim = new Vec2(0f, -1f) };
            g.Step(default);
            BulletPool bp = g.Arena.Bullets;
            float minDeg = 999f, maxDeg = -999f;
            int shots = 0;
            for (int i = 0; i < bp.High; i++)
            {
                if (!bp.Alive[i] || bp.OwnerId[i] != player.Id || bp.Damage[i] == t.TrailDamage) continue;
                shots++;
                float deg = MathF.Atan2(bp.VX[i], -bp.VY[i]) * 180f / MathF.PI;   // 0 = straight ahead (up)
                minDeg = MathF.Min(minDeg, deg);
                maxDeg = MathF.Max(maxDeg, deg);
            }
            Assert.Equal(3 * w.Count, shots);
            // Centre spray covers +-15; the flanks reach 20 + 15 either side.
            Assert.Equal(-(t.WideConeAngleDeg + w.SpreadDeg / 2f), minDeg, 2);
            Assert.Equal(t.WideConeAngleDeg + w.SpreadDeg / 2f, maxDeg, 2);

            // Differential: the Flare (no wide_cone) fires one spray.
            Game f = Quiet("fire_t2_flare");
            PilotOf(f).Input = new PlayerInput { Fire = true, Aim = new Vec2(0f, -1f) };
            f.Step(default);
            Assert.Equal(f.Arena.Player.Loadout.Primary.Count,
                LiveBullets(f, i => f.Arena.Bullets.OwnerId[i] == f.Arena.Player.Id && f.Arena.Bullets.Damage[i] != t.TrailDamage));
        }

        /// <summary>
        /// Spec 11.7 for enemies too: a regular enemy's pattern is its weapon, and its other parts
        /// work. A Flare enemy's vents leave a trail as it closes in; a Worm enemy's nucleus makes
        /// its spores spread; a Glitch enemy (no nucleus) does not.
        /// </summary>
        [Fact]
        public void RegularEnemiesUseTheirOtherPartsToo()
        {
            Game g = Quiet("corruption_t1_glitch");
            ShipCatalog cat = SimTestHelpers.Catalog();
            Tuning t = g.T;
            Vec2 p = g.Arena.Player.Pos;
            Ship flare = g.Arena.SpawnEnemy(cat.Get("fire_t2_flare"), p + new Vec2(600f, 0f), Sim.Patterns.PatternLibrary.FlameSpray(2));
            Ship worm = g.Arena.SpawnEnemy(cat.Get("corruption_t2_worm"), p + new Vec2(-500f, 0f), Sim.Patterns.PatternLibrary.SporeBurst(2));
            Ship glitch = g.Arena.SpawnEnemy(cat.Get("corruption_t1_glitch"), p + new Vec2(0f, 400f), Sim.Patterns.PatternLibrary.SporeBurst(1));
            g.Arena.Player.MaxHp = g.Arena.Player.Hp = 1e6f;
            int trail = 0;
            byte wormFlags = 0, glitchFlags = 0;
            for (int i = 0; i < 60 * 6; i++)
            {
                g.Step(default);
                BulletPool b = g.Arena.Bullets;
                for (int k = 0; k < b.High; k++)
                {
                    if (!b.Alive[k] || b.Born[k] != g.Arena.Tick) continue;
                    if (b.OwnerId[k] == flare.Id && b.Damage[k] == t.TrailDamage) trail++;
                    if (b.OwnerId[k] == worm.Id) wormFlags |= b.Flags[k];
                    if (b.OwnerId[k] == glitch.Id) glitchFlags |= b.Flags[k];
                }
            }
            Assert.True(trail >= 6, "the Flare enemy's vents left " + trail + " embers");
            Assert.True((wormFlags & BulletFlags.Spreads) != 0 && (wormFlags & BulletFlags.Infect) != 0, "worm spores flags " + wormFlags);
            Assert.True((glitchFlags & BulletFlags.Infect) != 0 && (glitchFlags & BulletFlags.Spreads) == 0, "glitch spores flags " + glitchFlags);
        }

        /// <summary>A ship pinned against a wall is standing still: its velocity is its real motion, so no trail.</summary>
        [Fact]
        public void APinnedShipLeavesNoTrail()
        {
            Game g = Quiet("fire_t2_flare");
            Ship player = g.Arena.Player;
            player.Pos = player.PrevPos = new Vec2(g.Arena.Width, 600f);
            PilotOf(g).Input = new PlayerInput { Move = new Vec2(1f, 0f), Aim = new Vec2(1f, 0f) };
            SimTestHelpers.StepN(g, 60);
            Assert.Equal(0f, player.Vel.Length(), 3);
            Assert.Equal(0, LiveBullets(g, i => g.Arena.Bullets.OwnerId[i] == player.Id));
        }

        /// <summary>Corruption enemies (spec 8: "spreading infection") shoot spores that infect even the player's core.</summary>
        [Fact]
        public void CorruptionEnemySporesInfectThePlayersCore()
        {
            Game g = Quiet("fire_t1_ember");
            Ship player = g.Arena.Player;
            Vec2 from = player.Pos + new Vec2(0f, -60f);
            g.Arena.SpawnBullet(Sides.Of(Faction.Enemy, Element.Corruption), Element.Corruption, from, new Vec2(0f, 170f), 3.5f, 4f, 90, BulletFlags.Infect);
            SimTestHelpers.StepUntil(g, gg => gg.Arena.Player.Infected(gg.Arena.Tick), 60);
            Assert.True(player.Infected(g.Arena.Tick), "the spore hit but did not infect");
            float hp = player.Hp;
            SimTestHelpers.StepN(g, 60);
            Assert.True(player.Hp < hp - 4f, "no damage over time on the player: " + hp + " -> " + player.Hp);
        }
    }
}
